# frozen_string_literal: true

module Kapusta
  class Reader
    WHITESPACE = [' ', "\t", "\n", "\r", "\f", "\v", ','].freeze
    DELIMS = ['(', ')', '[', ']', '{', '}', '"', ';'].freeze

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
        skip_ws
        break if eof?

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

    def skip_ws
      until eof?
        char = peek
        if WHITESPACE.include?(char)
          advance
        elsif !@preserve_comments && char == ';'
          advance until eof? || peek == "\n"
        else
          break
        end
      end
    end

    def delim?(char)
      char.nil? || WHITESPACE.include?(char) || DELIMS.include?(char)
    end

    def read_next_item
      skip_ws
      raise 'unexpected eof' if eof?

      return read_comment if @preserve_comments && peek == ';'

      read_form
    end

    def read_form
      skip_ws
      raise 'unexpected eof' if eof?

      return read_comment if @preserve_comments && peek == ';'

      form =
        case peek
        when '(' then read_list
        when '[' then read_vec
        when '{' then read_hash
        when '"' then read_string
        when '#' then read_hashfn
        else
          read_atom
        end

      read_postfix(form)
    end

    def read_list
      advance
      items = []
      loop do
        skip_ws
        raise 'unclosed (' if eof?
        break if peek == ')'

        items << read_next_item
      end
      advance
      List.new(items)
    end

    def read_vec
      advance
      items = []
      loop do
        skip_ws
        raise 'unclosed [' if eof?
        break if peek == ']'

        items << read_next_item
      end
      advance
      Vec.new(items)
    end

    def read_hash
      advance
      entries = []
      pending = []
      loop do
        skip_ws
        raise 'unclosed {' if eof?
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
      advance

      raise 'odd number of forms in hash' unless pending.empty?

      HashLit.new(entries)
    end

    def read_string
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
      raise 'unterminated string' if eof?

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
      start = @pos
      advance until delim?(peek)
      token = @src[start...@pos]
      raise 'empty token' if token.empty?

      parse_atom(token)
    end

    def parse_atom(token)
      return true if token == 'true'
      return false if token == 'false'
      return nil if token == 'nil'
      return token.to_i if token.match?(/\A-?\d+\z/)
      return token.to_f if token.match?(/\A-?\d+\.\d+\z/)

      if token.start_with?(':') && token.length > 1
        Kapusta.kebab_to_snake(token[1..]).to_sym
      else
        Sym.new(token)
      end
    end

    def normalize_hash_pair(item, value)
      if item.is_a?(Sym) && item.name == ':'
        raise 'bad shorthand' unless value.is_a?(Sym)

        key = Kapusta.kebab_to_snake(value.name).to_sym
        [key, value]
      else
        [item, value]
      end
    end
  end
end
