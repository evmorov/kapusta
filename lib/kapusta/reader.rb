# frozen_string_literal: true

require_relative 'error'

module Kapusta
  class Reader
    class Error < Kapusta::Error; end

    WHITESPACE = [' ', "\t", "\n", "\r", "\f", "\v"].freeze
    DELIMS = ['(', ')', '[', ']', '{', '}', '"', ';', '`', ','].freeze
    CLOSING_DELIMS = [')', ']', '}'].freeze

    def self.read_all(source, preserve_comments: false)
      new(source, preserve_comments:).read_all
    end

    def initialize(source, preserve_comments: false)
      @src = source
      @pos = 0
      @preserve_comments = preserve_comments
    end

    def read_all
      forms = []
      loop do
        had_blank = skip_ws
        break if eof?

        forms << BlankLine.new if @preserve_comments && had_blank && !forms.empty?
        forms << read_next_item
      end
      forms
    end

    private

    def eof?
      @pos >= @src.length
    end

    def peek
      @src[@pos]
    end

    def advance
      char = @src[@pos]
      @pos += 1
      char
    end

    def skip_ws # rubocop:disable Naming/PredicateMethod
      newlines = 0
      until eof?
        char = peek
        if char == "\n"
          newlines += 1
          advance
        elsif WHITESPACE.include?(char)
          advance
        elsif !@preserve_comments && char == ';'
          advance until eof? || peek == "\n"
        else
          break
        end
      end
      newlines >= 2
    end

    def delim?(char)
      char.nil? || WHITESPACE.include?(char) || DELIMS.include?(char)
    end

    def read_next_item
      skip_ws
      raise reader_error(:unexpected_eof, source_position) if eof?

      return read_comment if @preserve_comments && peek == ';'

      read_form
    end

    def read_form
      skip_ws
      raise reader_error(:unexpected_eof, source_position) if eof?

      return read_comment if @preserve_comments && peek == ';'

      position = source_position
      form =
        case peek
        when '(' then read_list
        when '[' then read_vec
        when '{' then read_hash
        when '"' then read_string
        when '#' then read_hashfn
        when '`' then read_quasiquote
        when ',' then read_unquote
        when *CLOSING_DELIMS then raise unexpected_closing_delim(peek)
        else
          read_atom
        end

      attach_position(form, position)
      read_postfix(form)
    end

    def attach_position(form, position)
      return form unless form.respond_to?(:line=)

      form.line ||= position[0]
      form.column ||= position[1]
      form
    end

    def read_quasiquote
      advance
      Quasiquote.new(read_form)
    end

    def read_unquote
      advance
      if peek == '@'
        advance
        UnquoteSplice.new(read_form)
      else
        Unquote.new(read_form)
      end
    end

    def read_list
      opening_position = source_position
      advance
      items = []
      loop do
        had_blank = skip_ws
        raise unclosed_opening_delim('(', opening_position) if eof?
        break if peek == ')'

        items << BlankLine.new if @preserve_comments && had_blank && !items.empty?
        items << read_next_item
      end
      closing_position = source_position
      advance
      list = List.new(items)
      list.multiline_source = closing_position[0] != opening_position[0]
      list.line = opening_position[0]
      list.column = opening_position[1]
      list
    end

    def read_vec
      opening_position = source_position
      advance
      items = []
      loop do
        had_blank = skip_ws
        raise unclosed_opening_delim('[', opening_position) if eof?
        break if peek == ']'

        items << BlankLine.new if @preserve_comments && had_blank && !items.empty?
        items << read_next_item
      end
      closing_position = source_position
      advance
      vec = Vec.new(items)
      vec.multiline_source = closing_position[0] != opening_position[0]
      vec.line = opening_position[0]
      vec.column = opening_position[1]
      vec
    end

    def read_hash
      opening_position = source_position
      advance
      entries = []
      pending = []
      loop do
        skip_ws
        raise unclosed_opening_delim('{', opening_position) if eof?
        break if peek == '}'

        item = read_next_item
        if item.is_a?(Comment)
          entries << item
          next
        end

        pending << item
        next unless pending.length == 2

        entries << normalize_hash_pair(pending[0], pending[1])
        pending.clear
      end
      closing_position = source_position
      advance

      raise reader_error(:odd_forms_in_hash, opening_position) unless pending.empty?

      hash = HashLit.new(entries)
      hash.multiline_source = closing_position[0] != opening_position[0]
      hash.line = opening_position[0]
      hash.column = opening_position[1]
      hash
    end

    def read_string
      opening_position = source_position
      advance
      buffer = +''
      until eof? || peek == '"'
        if peek == '\\'
          advance
          escaped = advance
          buffer << case escaped
                    when 'n' then "\n"
                    when 't' then "\t"
                    when 'r' then "\r"
                    when '\\' then '\\'
                    when '"' then '"'
                    when '0' then "\0"
                    when 'a' then "\a"
                    when 'b' then "\b"
                    when 'f' then "\f"
                    when 'v' then "\v"
                    else escaped
                    end
        else
          buffer << advance
        end
      end
      raise reader_error(:unterminated_string, opening_position) if eof?

      advance
      buffer
    end

    def read_hashfn
      advance
      form = read_form
      List.new([Sym.new('hashfn'), form])
    end

    def read_comment
      start = @pos
      advance until eof? || peek == "\n"
      Comment.new(@src[start...@pos].rstrip)
    end

    def read_postfix(form)
      current = form

      loop do
        break unless peek == '.'

        start = @pos
        advance until delim?(peek)
        token = @src[start...@pos]
        break unless token.start_with?('.') && token.length > 1

        token[1..].split('.').each do |name|
          current = List.new([Sym.new(':'), current, Kapusta.kebab_to_snake(name).to_sym])
        end
      end

      current
    end

    def read_atom
      position = source_position
      start = @pos
      advance until delim?(peek)
      token = @src[start...@pos]
      parse_atom(token, position)
    end

    def unexpected_closing_delim(char)
      reader_error(:unexpected_closing_delimiter, source_position, char:)
    end

    def unclosed_opening_delim(char, position)
      reader_error(:unclosed_delimiter, position, char:)
    end

    def reader_error(code, position, **args)
      Error.new(Kapusta::Errors.format(code, **args), line: position[0], column: position[1])
    end

    def source_position
      prefix = @src[0...@pos]
      line = prefix.count("\n") + 1
      last_newline = prefix.rindex("\n")
      column = last_newline ? prefix.length - last_newline : prefix.length + 1

      [line, column]
    end

    def parse_atom(token, position)
      return true if token == 'true'
      return false if token == 'false'
      return if token == 'nil'
      return Integer(token, 10) if token.match?(/\A-?\d+\z/)
      return Float(token) if token.match?(/\A-?\d+\.\d+\z/)

      raise reader_error(:could_not_read_number, position, token:) if token.match?(/\A-?\d/)

      if token.start_with?(':') && token.length > 1
        Kapusta.kebab_to_snake(token[1..]).to_sym
      elsif token.length > 1 && token.end_with?('#') && !token[0..-2].include?('#')
        AutoGensym.new(token.chomp('#'))
      else
        Sym.new(token)
      end
    end

    def normalize_hash_pair(item, value)
      if item.is_a?(Sym) && item.name == ':'
        raise reader_error(:bad_shorthand, source_position) unless value.is_a?(Sym)

        key = Kapusta.kebab_to_snake(value.name).to_sym
        [key, value]
      else
        [item, value]
      end
    end
  end
end
