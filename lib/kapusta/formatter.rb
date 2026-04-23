# frozen_string_literal: true

require_relative '../kapusta'

module Kapusta
  class Formatter
    MAX_WIDTH = 80
    INDENT = 2
    STDIN_PATH = '-'

    PIPELINE_FORMS = %w[-> ->> -?> -?>> doto].freeze

    def initialize(argv)
      @mode = :stdout
      @files = []
      parse_args(argv)
    end

    def run
      validate_args!

      formatted = @files.map do |path|
        original = read_source(path)
        [path, original, format_source(original)]
      end

      case @mode
      when :stdout
        $stdout.write(formatted.first[2])
      when :fix
        formatted.each do |path, _original, rewritten|
          raise Error, 'Cannot use --fix with stdin (-).' if stdin_path?(path)

          File.write(path, rewritten)
        end
      when :check
        dirty = formatted.reject { |_path, original, rewritten| original == rewritten }
        dirty.each do |path, _original, _rewritten|
          warn "Not formatted: #{path}"
        end
        return 1 unless dirty.empty?
      end

      0
    rescue Error => e
      warn e.message
      1
    end

    private

    def parse_args(argv)
      argv.each do |arg|
        case arg
        when '--fix'
          ensure_mode!(:fix)
        when '--check'
          ensure_mode!(:check)
        when '--help', '-h'
          print_help
          exit 0
        else
          @files << arg
        end
      end
    end

    def ensure_mode!(mode)
      raise Error, 'Use at most one of --fix or --check.' if @mode != :stdout && @mode != mode

      @mode = mode
    end

    def validate_args!
      raise Error, 'Usage: kapfmt [--fix] [--check] FILENAME...' if @files.empty?
      raise Error, 'stdin (-) may only be specified once.' if @files.count { |path| stdin_path?(path) } > 1
      raise Error, 'Cannot use --fix with stdin (-).' if @mode == :fix && @files.any? { |path| stdin_path?(path) }

      return unless @mode == :stdout && @files.length != 1

      raise Error, 'Without --fix or --check, kapfmt accepts exactly one file.'
    end

    def read_source(path)
      return File.read(path) unless stdin_path?(path)

      @stdin_read ||= false
      raise Error, 'stdin (-) may only be specified once.' if @stdin_read

      @stdin_read = true
      $stdin.read
    end

    def format_source(source)
      reject_comments!(source)

      forms = Reader.read_all(source)
      rendered = forms.map { |form| render(form, 0, top_level: true) }
      return '' if rendered.empty?

      output = +''
      rendered.each_with_index do |form, index|
        output << separator_for(forms[index - 1], forms[index]) unless index.zero?
        output << form
      end
      output << "\n"
    rescue StandardError => e
      raise Error, e.message
    end

    def separator_for(previous, current)
      if consecutive_requires?(previous, current) ||
         (groupable_top_level_form?(previous) && groupable_top_level_form?(current))
        "\n"
      else
        "\n\n"
      end
    end

    def reject_comments!(source)
      index = 0

      while index < source.length
        char = source[index]

        if char == '"'
          index = consume_string(source, index)
        elsif char == ';'
          raise Error, 'kapfmt does not support comments yet.'
        else
          index += 1
        end
      end
    end

    def consume_string(source, start)
      index = start + 1

      while index < source.length
        char = source[index]
        index += 1

        if char == '\\'
          index += 1
        elsif char == '"'
          break
        end
      end

      index
    end

    def render(form, indent, layout: nil, top_level: false, force_expand: false)
      flat = flat_render(form)
      return flat if !force_expand && flat && fits?(flat, indent) && allow_flat?(form, top_level:, layout:)

      case form
      when List then render_list(form, indent, top_level:)
      when Vec then render_vec(form, indent, layout:, top_level:, force_expand:)
      when HashLit then render_hash(form, indent)
      else
        flat || raise(Error, "cannot format form: #{form.inspect}")
      end
    end

    def flat_render(form)
      case form
      when Sym
        form.name
      when Vec
        "[#{form.items.map { |item| flat_render(item) }.join(' ')}]"
      when HashLit
        "{#{form.pairs.map { |key, value| flat_hash_pair(key, value) }.join(' ')}}"
      when List
        return "##{flat_render(form.items[1])}" if hashfn_literal?(form)

        "(#{form.items.map { |item| flat_render(item) }.join(' ')})"
      when String, Numeric, true, false, nil
        form.inspect
      when Symbol
        ":#{form.to_s.tr('_', '-')}"
      end
    end

    def render_list(list, indent, top_level: false)
      return '()' if list.empty?
      return "##{render(list.items[1], indent, top_level:)}" if hashfn_literal?(list)

      head = list.head
      head_name = head.is_a?(Sym) ? head.name : nil

      case head_name
      when 'fn', 'lambda', 'λ' then render_fn(head_name, list, indent, top_level:)
      when 'let' then render_let(list, indent)
      when 'do', 'finally' then render_prefix_body_form(head_name, [], list.rest, indent)
      when 'try' then render_try(list, indent)
      when 'while', 'when', 'unless', 'for', 'each', 'icollect', 'collect', 'fcollect', 'accumulate', 'faccumulate'
        render_prefix_body_form(head_name, list.rest.take(1), list.rest.drop(1), indent)
      when 'module' then render_prefix_body_form('module', list.rest.take(1), list.rest.drop(1), indent)
      when 'class' then render_class(list, indent)
      when 'catch' then render_catch(list, indent)
      when 'if' then render_if(list, indent)
      when 'case', 'match' then render_case(head_name, list.rest, indent)
      when *PIPELINE_FORMS then render_pipeline(head_name, list.rest, indent)
      else
        render_call(list, indent)
      end
    end

    def render_fn(head, list, indent, top_level: false)
      args = list.rest
      if args[0].is_a?(Sym) && args[1].is_a?(Vec)
        render_prefix_body_form(head, args.take(2), args.drop(2), indent, force_body_multiline: top_level)
      else
        render_prefix_body_form(head, args.take(1), args.drop(1), indent, force_body_multiline: top_level)
      end
    end

    def render_catch(list, indent)
      args = list.rest
      prefix = args.take(2)
      body = args.drop(2)
      render_prefix_body_form('catch', prefix, body, indent)
    end

    def render_class(list, indent)
      args = list.rest
      prefix = args[1].is_a?(Vec) ? args.take(2) : args.take(1)
      body = args.drop(prefix.length)
      render_prefix_body_form('class', prefix, body, indent)
    end

    def render_try(list, indent)
      args = list.rest
      lines = ['(try']

      if args.any?
        first = render(args.first, indent + '(try '.length)
        candidate = "(try #{first}"
        if single_line?(first) && fits?(candidate, indent)
          lines[0] = candidate
        else
          lines << indent_block(first, INDENT)
        end
      end

      args.drop(1).each do |form|
        lines << indent_block(render(form, indent + INDENT), INDENT)
      end

      append_suffix(lines, ')')
    end

    def render_let(list, indent)
      bindings = list.rest.first
      body = list.rest.drop(1)
      unless bindings.is_a?(Vec)
        return render_prefix_body_form('let', list.rest.take(1), body, indent,
                                       layouts: [:pairwise])
      end

      rendered_bindings = render_let_bindings(bindings, indent)
      lines = rendered_bindings.lines(chomp: true)
      lines[0] = "(let #{lines[0]}"
      body.each do |form|
        lines << indent_block(render(form, indent + INDENT), INDENT)
      end
      append_suffix(lines, ')')
    end

    def render_prefix_body_form(head, prefix_forms, body_forms, indent, layouts: [], force_body_multiline: false)
      line = "(#{head}"
      lines = [line]
      current_first_line = line

      prefix_forms.each_with_index do |form, index|
        rendered = render(form, indent + INDENT, layout: layouts[index])
        candidate = "#{current_first_line} #{rendered}"

        if single_line?(rendered) && fits?(candidate, indent)
          current_first_line = candidate
          lines[0] = current_first_line
        else
          lines << indent_block(rendered, INDENT)
        end
      end

      body_forms.each do |form|
        body = render(
          form,
          indent + INDENT,
          force_expand: force_body_multiline && force_multiline_body?(form)
        )
        lines << indent_block(body, INDENT)
      end

      append_suffix(lines, ')')
    end

    def render_if(list, indent)
      args = list.rest
      lines = []
      hanging = ' ' * '(if '.length

      if args.length == 3
        flat = flat_render(list)
        return flat if inline_three_arg_if?(args) && flat && fits?(flat, indent)

        lines << "(if #{render(args[0], indent + '(if '.length)}"
        lines << "#{hanging}#{render(args[1], indent + '(if '.length)}"
        lines << "#{hanging}#{render(args[2], indent + '(if '.length)}"
        return append_suffix(lines, ')')
      end

      index = 0
      if args.length >= 2
        first_pair = render_pair(args[0], args[1], indent + '(if '.length)
        if first_pair
          lines << "(if #{first_pair}"
        else
          lines << "(if #{render(args[0], indent + '(if '.length)}"
          lines << "#{hanging}#{render(args[1], indent + '(if '.length)}"
        end
        index = 2
      else
        lines << '(if'
      end

      while index < args.length
        remaining = args.length - index
        if remaining >= 2
          pair = render_pair(args[index], args[index + 1], indent + '(if '.length)
          if pair
            lines << "#{hanging}#{pair}"
          else
            lines << "#{hanging}#{render(args[index], indent + '(if '.length)}"
            lines << "#{hanging}#{render(args[index + 1], indent + '(if '.length)}"
          end
          index += 2
        else
          lines << "#{hanging}#{render(args[index], indent + '(if '.length)}"
          index += 1
        end
      end

      append_suffix(lines, ')')
    end

    def render_case(head, args, indent)
      subject = args.first
      clauses = args.drop(1)
      lines = ['(case']

      if subject
        rendered_subject = render(subject, indent + INDENT)
        if single_line?(rendered_subject) && fits?("(#{head} #{rendered_subject}", indent)
          lines[0] = "(#{head} #{rendered_subject}"
        else
          lines[0] = "(#{head}"
          lines << indent_block(rendered_subject, INDENT)
        end
      end

      clauses.each_slice(2) do |pair|
        pattern, value = pair
        if pair.length == 2
          pair = render_pair(pattern, value, indent + INDENT)
          if pair
            lines << indent_block(pair, INDENT)
          else
            lines << indent_block(render(pattern, indent + INDENT), INDENT)
            lines << indent_block(render(value, indent + INDENT), INDENT)
          end
        else
          lines << indent_block(render(pattern, indent + INDENT), INDENT)
        end
      end

      append_suffix(lines, ')')
    end

    def render_pipeline(head, args, indent)
      base = "(#{head}"
      lines = [base]
      hanging = ' ' * (base.length + 1)

      args.each_with_index do |form, index|
        rendered = render(form, indent + base.length + 1)
        if index.zero?
          first_line, *rest = rendered.lines(chomp: true)
          candidate = "#{base} #{first_line}"
          if fits?(candidate, indent)
            lines[0] = candidate
            rest.each { |line| lines << "#{hanging}#{line}" }
          else
            lines << indent_block(rendered, INDENT)
          end
        else
          lines << "#{hanging}#{rendered}"
        end
      end

      append_suffix(lines, ')')
    end

    def render_call(list, indent)
      head = flat_render(list.head)
      raise Error, "cannot format form head: #{list.head.inspect}" unless head

      base = "(#{head}"
      lines = [base]
      args = list.rest

      unless args.empty?
        first = render(
          args.first,
          indent + base.length + 1,
          force_expand: args.length == 1 && fn_form?(args.first)
        )
        first_line, *rest = first.lines(chomp: true)
        candidate = "#{base} #{first_line}"

        if fits?(candidate, indent)
          lines[0] = candidate
          hanging = ' ' * (base.length + 1)
          rest.each { |line| lines << "#{hanging}#{line}" }
        else
          lines << indent_block(first, INDENT)
        end

        args.drop(1).each do |arg|
          lines << indent_block(render(arg, indent + INDENT), INDENT)
        end
      end

      append_suffix(lines, ')')
    end

    def render_vec(vec, indent, layout: nil, top_level: false, force_expand: false)
      flat = flat_render(vec)
      return flat if !force_expand && flat && fits?(flat, indent) && allow_flat?(vec, top_level:, layout:)

      if layout == :pairwise
        render_pairwise_vec(vec, indent)
      else
        lines = ['[']
        vec.items.each do |item|
          lines << indent_block(render(item, indent + INDENT), INDENT)
        end
        lines << ']'
        lines.join("\n")
      end
    end

    def render_pairwise_vec(vec, indent)
      lines = ['[']

      vec.items.each_slice(2) do |left, right|
        if right
          pair = render_pair(left, right, indent + INDENT)
          if pair
            lines << indent_block(pair, INDENT)
          else
            lines << indent_block(render(left, indent + INDENT), INDENT)
            lines << indent_block(render(right, indent + INDENT), INDENT)
          end
        else
          lines << indent_block(render(left, indent + INDENT), INDENT)
        end
      end

      lines << ']'
      lines.join("\n")
    end

    def render_let_bindings(bindings, indent)
      return render(bindings, indent + '(let '.length, layout: :pairwise) if bindings.items.length <= 2

      hanging = render_hanging_pairwise_vec(bindings)
      hanging || render(bindings, indent + '(let '.length, layout: :pairwise)
    end

    def render_hanging_pairwise_vec(vec)
      pairs = vec.items.each_slice(2).to_a
      rendered_pairs = pairs.map do |left, right|
        return nil unless right

        render_binding_pair(left, right)
      end
      return nil if rendered_pairs.any?(&:nil?)

      lines = ["[#{rendered_pairs.first}"]
      continuation = ' ' * '(let ['.length
      rendered_pairs.drop(1).each do |pair|
        lines << "#{continuation}#{pair}"
      end
      lines[-1] = "#{lines[-1]}]"
      lines.join("\n")
    end

    def render_hash(hash, indent)
      flat = flat_render(hash)
      return flat if flat && fits?(flat, indent)

      lines = ['{']

      hash.pairs.each do |key, value|
        pair = flat_hash_pair(key, value)
        if fits?(pair, indent + INDENT)
          lines << indent_block(pair, INDENT)
        else
          lines << indent_block(render_hash_key(key), INDENT)
          lines << indent_block(render(value, indent + INDENT), INDENT)
        end
      end

      lines << '}'
      lines.join("\n")
    end

    def flat_hash_pair(key, value)
      if hash_shorthand?(key, value)
        ": #{value.name}"
      else
        "#{render_hash_key(key)} #{flat_render(value)}"
      end
    end

    def render_hash_key(key)
      return ":#{key.to_s.tr('_', '-')}" if key.is_a?(Symbol)

      rendered = flat_render(key)
      raise Error, "cannot format hash key: #{key.inspect}" unless rendered

      rendered
    end

    def render_pair(left, right, indent)
      left_rendered = flat_render(left) || render(left, indent)
      right_rendered = flat_render(right) || render(right, indent)
      return nil unless single_line?(left_rendered) && single_line?(right_rendered)

      pair = "#{left_rendered} #{right_rendered}"
      fits?(pair, indent) ? pair : nil
    end

    def render_binding_pair(left, right)
      left_rendered = flat_render(left)
      return nil unless left_rendered

      right_rendered = render(right, '(let ['.length + left_rendered.length + 1)
      first_line, *rest = right_rendered.lines(chomp: true)
      pair = "#{left_rendered} #{first_line}"
      return nil unless pair.length <= MAX_WIDTH

      return pair if rest.empty?

      continuation = ' ' * ('(let ['.length + left_rendered.length + 1)
      ([pair] + rest.map { |line| "#{continuation}#{line}" }).join("\n")
    end

    def hash_shorthand?(key, value)
      key.is_a?(Symbol) && value.is_a?(Sym) && key == Kapusta.kebab_to_snake(value.name).to_sym
    end

    def hashfn_literal?(form)
      form.is_a?(List) &&
        form.items.length == 2 &&
        form.items[0].is_a?(Sym) &&
        form.items[0].name == 'hashfn'
    end

    def allow_flat?(form, top_level:, layout:)
      return false if layout == :pairwise && form.is_a?(Vec) && form.items.length > 2
      return true unless form.is_a?(List)

      head = form.head
      return true unless head.is_a?(Sym)

      case head.name
      when 'fn', 'lambda', 'λ', 'when', 'unless', 'for', 'each', 'icollect', 'collect', 'fcollect', 'accumulate',
           'faccumulate'
        !top_level
      else
        !%w[let case match try catch finally do -> ->> -?> -?>> doto].include?(head.name)
      end
    end

    def force_multiline_body?(form)
      return false unless form.is_a?(List) && form.head.is_a?(Sym)

      case form.head.name
      when 'if', 'case', 'match', 'let', 'try', 'catch', 'finally', 'do', 'for', '->', '->>', '-?>', '-?>>', 'doto',
           'fn', 'lambda', 'λ'
        true
      else
        flat = flat_render(form)
        flat && flat.length > 40
      end
    end

    def fn_body(form)
      args = form.rest
      if args[0].is_a?(Sym) && args[1].is_a?(Vec)
        args.drop(2)
      else
        args.drop(1)
      end
    end

    def consecutive_requires?(previous, current)
      require_form?(previous) && require_form?(current)
    end

    def groupable_top_level_form?(form)
      return true if require_form?(form)
      return false unless form.is_a?(List) && flat_render(form)

      head = form.head
      return false unless head.is_a?(Sym)

      !%w[fn module class let].include?(head.name)
    end

    def require_form?(form)
      form.is_a?(List) &&
        form.items.length == 2 &&
        form.head.is_a?(Sym) &&
        form.head.name == 'require'
    end

    def fn_form?(form)
      form.is_a?(List) &&
        form.head.is_a?(Sym) &&
        %w[fn lambda λ].include?(form.head.name)
    end

    def inline_three_arg_if?(args)
      then_branch = args[1]
      else_branch = args[2]

      atomish?(then_branch) || atomish?(else_branch)
    end

    def atomish?(form)
      case form
      when Sym, String, Numeric, true, false, nil, Symbol
        true
      else
        false
      end
    end

    def stdin_path?(path)
      path == STDIN_PATH
    end

    def fits?(text, indent)
      !text.include?("\n") && indent + text.length <= MAX_WIDTH
    end

    def single_line?(text)
      !text.include?("\n")
    end

    def indent_block(text, amount)
      prefix = ' ' * amount
      text.lines.map { |line| "#{prefix}#{line}" }.join
    end

    def append_suffix(lines, suffix)
      updated = lines.dup
      updated[-1] = "#{updated[-1]}#{suffix}"
      updated.join("\n")
    end

    def print_help
      puts 'Usage: kapfmt [--fix] [--check] FILENAME...'
      puts
      puts 'Formats Kapusta source using the built-in Kapusta reader and pretty-printer.'
    end

    class Error < StandardError; end
  end
end
