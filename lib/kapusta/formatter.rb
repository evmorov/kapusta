# frozen_string_literal: true

require_relative '../kapusta'

module Kapusta
  class Formatter
    MAX_WIDTH = 80
    INDENT = 2
    STDIN_PATH = '-'

    PIPELINE_FORMS = %w[-> ->> -?> -?>> doto].freeze

    def self.format(source, path: nil)
      new([]).send(:format_source, source, path)
    end

    def initialize(argv)
      @mode = :stdout
      @files = []
      @version = false
      parse_args(argv)
    end

    def run
      if @version
        puts "kapfmt #{Kapusta::VERSION}"
        return 0
      end

      validate_args!

      formatted = @files.map do |path|
        original = read_source(path)
        validate_kapusta_source(original, path)
        [path, original, format_source(original, path)]
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
    rescue Kapusta::Error => e
      warn e.formatted
      1
    end

    private

    def validate_kapusta_source(source, path)
      Kapusta::Compiler.compile(source, path:)
    end

    def parse_args(argv)
      argv.each do |arg|
        case arg
        when '--fix'
          ensure_mode!(:fix)
        when '--check'
          ensure_mode!(:check)
        when '--version', '-v'
          @version = true
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

    def format_source(source, path = nil)
      forms = Reader.read_all(source, preserve_comments: true)
      entries = top_level_entries(forms)
      return '' if entries.empty?

      output = +''
      entries.each_with_index do |entry, index|
        output << separator_for_entries(entries[index - 1], entry) unless index.zero?
        output << render_top_level_entry(entry)
      end
      output << "\n"
    rescue Kapusta::Error => e
      raise e.with_defaults(path:)
    rescue StandardError => e
      raise Error.new(e.message, path:)
    end

    def separator_for(_previous, _current)
      "\n"
    end

    def top_level_entries(forms)
      entries = []
      leading_comments = []
      pending_blank = false

      forms.each do |form|
        if form.is_a?(BlankLine)
          pending_blank = true
        elsif comment?(form)
          leading_comments << form
        else
          entries << { comments: leading_comments, form:, blank_before: pending_blank }
          leading_comments = []
          pending_blank = false
        end
      end

      entries << { comments: leading_comments, form: nil, blank_before: pending_blank } unless leading_comments.empty?
      entries
    end

    def separator_for_entries(_previous, current)
      current[:blank_before] ? "\n\n" : "\n"
    end

    def render_top_level_entry(entry)
      parts = entry[:comments].map { |comment| render(comment, 0) }
      parts << render(entry[:form], 0, top_level: true) if entry[:form]
      parts.join("\n")
    end

    def comment?(form)
      form.is_a?(Comment)
    end

    def blank_line?(form)
      form.is_a?(BlankLine)
    end

    def non_semantic?(form)
      comment?(form) || blank_line?(form)
    end

    def render(form, indent, layout: nil, top_level: false, force_expand: false)
      flat = flat_render(form)
      return flat if !force_expand && flat && fits?(flat, indent) && allow_flat?(form, top_level:, layout:)

      case form
      when Comment then form.text
      when List then form.sigil ? render_sigil(form) : render_list(form, indent, top_level:)
      when Vec then render_vec(form, indent, layout:, top_level:, force_expand:)
      when HashLit then render_hash(form, indent)
      when Quasiquote then render_prefix('`', form.form, indent, force_expand:)
      when Unquote then render_prefix(',', form.form, indent, force_expand:)
      when UnquoteSplice then render_prefix(',@', form.form, indent, force_expand:)
      else
        flat || raise(Error, "cannot format form: #{form.inspect}")
      end
    end

    SIGIL_PREFIXES = { ivar: '@', cvar: '@@', gvar: '$' }.freeze
    private_constant :SIGIL_PREFIXES

    def render_sigil(list)
      "#{SIGIL_PREFIXES.fetch(list.sigil)}#{list.items[1].name}"
    end

    def render_prefix(prefix, inner, indent, force_expand: false)
      rendered = render(inner, indent + prefix.length, force_expand:)
      lines = rendered.lines(chomp: true)
      pad = ' ' * prefix.length
      lines.each_with_index.map { |line, i| i.zero? ? "#{prefix}#{line}" : "#{pad}#{line}" }.join("\n")
    end

    def flat_render(form)
      case form
      when Comment
        nil
      when AutoGensym
        "#{form.name}#"
      when Sym
        form.name
      when Vec
        return if contains_comments?(form.items)
        return if multiline_in_source?(form)

        rendered = form.items.map { |item| flat_render(item) }
        return if rendered.any?(&:nil?)

        "[#{rendered.join(' ')}]"
      when HashLit
        return if contains_comments?(form.entries)
        return if multiline_in_source?(form)

        rendered = form.pairs.map { |key, value| flat_hash_pair(key, value) }
        return if rendered.any?(&:nil?)

        "{#{rendered.join(' ')}}"
      when List
        return render_sigil(form) if form.sigil
        return if contains_comments?(form.items)
        return "##{flat_render(semantic_items(form.items)[1])}" if hashfn_literal?(form)
        return if multiline_in_source?(form)
        return if let_with_multiple_bindings?(form)
        return if let_with_nested_binding_value?(form)

        rendered = form.items.map { |item| flat_render(item) }
        return if rendered.any?(&:nil?)

        "(#{rendered.join(' ')})"
      when Quasiquote
        inner = flat_render(form.form)
        inner ? "`#{inner}" : nil
      when Unquote
        inner = flat_render(form.form)
        inner ? ",#{inner}" : nil
      when UnquoteSplice
        inner = flat_render(form.form)
        inner ? ",@#{inner}" : nil
      when String, Numeric, true, false, nil
        form.inspect
      when Symbol
        ":#{form.to_s.tr('_', '-')}"
      end
    end

    def render_list(list, indent, top_level: false)
      return '()' if list.items.empty?
      return "##{render(semantic_items(list.items)[1], indent, top_level:)}" if hashfn_literal?(list)

      head = list_head(list)
      return render_generic_list(list, indent) unless head

      head_name = head.is_a?(Sym) ? head.name : nil
      raw_args = list_raw_rest(list)

      case head_name
      when 'fn', 'lambda', 'λ', 'macro' then render_fn(head_name, list, indent, top_level:)
      when 'let' then render_let(list, indent)
      when 'do', 'finally' then render_prefix_body_form(head_name, [], raw_args, indent)
      when 'try' then render_try(list, indent)
      when 'while', 'when', 'unless', 'for', 'each', 'icollect', 'collect', 'fcollect', 'accumulate', 'faccumulate'
        raw_prefix, raw_body = split_raw_items(raw_args, 1)
        render_prefix_body_form(head_name, raw_prefix, raw_body, indent)
      when 'module'
        raw_prefix, raw_body = split_raw_items(raw_args, 1)
        render_prefix_body_form('module', raw_prefix, raw_body, indent)
      when 'class' then render_class(list, indent)
      when 'catch' then render_catch(list, indent)
      when 'if' then render_if(list, indent)
      when 'case', 'match'
        if contains_comments?(raw_args)
          render_sequential_head_form(head_name, raw_args, indent)
        else
          render_case(head_name, list_rest(list), indent)
        end
      when *PIPELINE_FORMS then render_pipeline(head_name, raw_args, indent)
      else
        render_call(list, indent)
      end
    end

    def render_fn(head, list, indent, top_level: false)
      args = list_rest(list)
      raw_args = list_raw_rest(list)
      prefix_length = args[0].is_a?(Sym) && args[1].is_a?(Vec) ? 2 : 1
      raw_prefix, raw_body = split_raw_items(raw_args, prefix_length)
      force = top_level || fn_body_has_quasi_list?(raw_body)
      render_prefix_body_form(head, raw_prefix, raw_body, indent, force_body_multiline: force)
    end

    def fn_body_has_quasi_list?(body_forms)
      body_forms.any? { |form| form.is_a?(Quasiquote) && form.form.is_a?(List) }
    end

    def render_catch(list, indent)
      raw_prefix, raw_body = split_raw_items(list_raw_rest(list), 2)
      render_prefix_body_form('catch', raw_prefix, raw_body, indent)
    end

    def render_class(list, indent)
      args = list_rest(list)
      raw_args = list_raw_rest(list)
      prefix = args[1].is_a?(Vec) ? args.take(2) : args.take(1)
      raw_prefix, raw_body = split_raw_items(raw_args, prefix.length)
      render_prefix_body_form('class', raw_prefix, raw_body, indent)
    end

    def render_try(list, indent)
      args = list_rest(list)
      return render_sequential_head_form('try', list_raw_rest(list), indent) if contains_comments?(list_raw_rest(list))

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
      bindings = list_rest(list).first
      raw_args = list_raw_rest(list)
      raw_prefix, raw_body = split_raw_items(raw_args, 1)
      body = list_rest(list).drop(1)
      unless bindings.is_a?(Vec)
        return render_prefix_body_form('let', raw_prefix, raw_body, indent,
                                       layouts: [:pairwise])
      end

      if contains_comments?(raw_args) || contains_comments?(bindings.items)
        return render_prefix_body_form('let', raw_prefix, raw_body, indent,
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

    def append_prefix_form(lines, form, indent, current_first_line, inline_prefix, layouts, layout_index)
      if blank_line?(form)
        lines << ''
        return [current_first_line, false, layout_index]
      end
      if comment?(form)
        lines << indent_block(render(form, indent + INDENT), INDENT)
        return [current_first_line, false, layout_index]
      end

      rendered = render(form, indent + current_first_line.length + 1, layout: layouts[layout_index])
      rendered_lines = rendered.lines.map(&:chomp)
      candidate_first = "#{current_first_line} #{rendered_lines.first}"

      if inline_prefix && fits?(candidate_first, indent)
        lines[-1] = candidate_first
        if rendered_lines.length == 1
          [candidate_first, true, layout_index + 1]
        else
          hanging = ' ' * (current_first_line.length + 1)
          rendered_lines.drop(1).each { |line| lines << "#{hanging}#{line}" }
          [current_first_line, false, layout_index + 1]
        end
      else
        lines << indent_block(rendered, INDENT)
        [current_first_line, false, layout_index + 1]
      end
    end

    def render_prefix_body_form(head, prefix_forms, body_forms, indent, layouts: [], force_body_multiline: false)
      line = "(#{head}"
      lines = [line]
      current_first_line = line
      layout_index = 0
      inline_prefix = true

      prefix_forms.each do |form|
        current_first_line, inline_prefix, layout_index =
          append_prefix_form(lines, form, indent, current_first_line, inline_prefix, layouts, layout_index)
      end

      body_forms.each do |form|
        if blank_line?(form)
          lines << ''
          next
        end
        if comment?(form)
          lines << indent_block(render(form, indent + INDENT), INDENT)
          next
        end

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
      args = list_rest(list)
      return render_sequential_head_form('if', list_raw_rest(list), indent) if contains_comments?(list_raw_rest(list))

      lines = []
      hanging = ' ' * '(if '.length

      if args.length == 3
        flat = flat_render(list)
        return flat if inline_three_arg_if?(args) && flat && fits?(flat, indent)

        lines << "(if #{render(args[0], indent + '(if '.length)}"
        lines << prefix_continuation(hanging, render(args[1], indent + '(if '.length))
        lines << prefix_continuation(hanging, render(args[2], indent + '(if '.length))
        return append_suffix(lines, ')')
      end

      index = 0
      if args.length >= 2
        first_pair = render_pair(args[0], args[1], indent + '(if '.length)
        if first_pair
          lines << "(if #{first_pair}"
        else
          lines << "(if #{render(args[0], indent + '(if '.length)}"
          lines << prefix_continuation(hanging, render(args[1], indent + '(if '.length))
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
            lines << prefix_continuation(hanging, render(args[index], indent + '(if '.length))
            lines << prefix_continuation(hanging, render(args[index + 1], indent + '(if '.length))
          end
          index += 2
        else
          lines << prefix_continuation(hanging, render(args[index], indent + '(if '.length))
          index += 1
        end
      end

      append_suffix(lines, ')')
    end

    def prefix_continuation(prefix, rendered)
      first_line, *rest = rendered.lines(chomp: true)
      pad = ' ' * prefix.length
      ["#{prefix}#{first_line}", *rest.map { |line| "#{pad}#{line}" }].join("\n")
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

      semantic_index = 0
      args.each do |form|
        if comment?(form)
          lines << "#{hanging}#{render(form, indent + base.length + 1)}"
          next
        end

        rendered = render(form, indent + base.length + 1)
        if semantic_index.zero?
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
        semantic_index += 1
      end

      append_suffix(lines, ')')
    end

    def render_call(list, indent)
      head = flat_render(list_head(list))
      raise Error, "cannot format form head: #{list_head(list).inspect}" unless head

      base = "(#{head}"
      lines = [base]
      args = list_raw_rest(list)
      semantic_length = semantic_items(args).length

      semantic_index = 0
      args.each do |arg|
        if comment?(arg)
          lines << indent_block(render(arg, indent + INDENT), INDENT)
          next
        end

        if semantic_index.zero?
          first = render(
            arg,
            indent + base.length + 1,
            force_expand: semantic_length == 1 && fn_form?(arg)
          )
          first_line, *rest = first.lines(chomp: true)
          candidate = "#{base} #{first_line}"

          if lines.length == 1 && fits?(candidate, indent)
            lines[0] = candidate
            hanging = ' ' * (base.length + 1)
            rest.each { |line| lines << "#{hanging}#{line}" }
          else
            lines << indent_block(first, INDENT)
          end
        else
          lines << indent_block(render(arg, indent + INDENT), INDENT)
        end

        semantic_index += 1
      end

      append_suffix(lines, ')')
    end

    def render_vec(vec, indent, layout: nil, top_level: false, force_expand: false)
      flat = flat_render(vec)
      return flat if !force_expand && flat && fits?(flat, indent) && allow_flat?(vec, top_level:, layout:)

      return render_pairwise_vec(vec, indent) if layout == :pairwise && !contains_comments?(vec.items)
      return render_filled_vec(vec, indent) if !contains_comments?(vec.items) && !vec.items.empty?

      lines = ['[']
      vec.items.each do |item|
        lines << indent_block(render(item, indent + INDENT), INDENT)
      end
      append_suffix(lines, ']')
    end

    def render_filled_vec(vec, indent)
      output_lines = ['[']

      vec.items.each_with_index do |item, idx|
        if idx.zero?
          item_col = output_lines.last.length
          rendered_lines = render(item, indent + item_col).lines.map(&:chomp)
          output_lines[-1] += rendered_lines.first
          rendered_lines.drop(1).each { |line| output_lines << ((' ' * item_col) + line) }
          next
        end

        inline_col = output_lines.last.length + 1
        flat = flat_render(item)

        if flat && indent + inline_col + flat.length <= MAX_WIDTH
          output_lines[-1] += " #{flat}"
        elsif flat && indent + 1 + flat.length <= MAX_WIDTH
          output_lines << " #{flat}"
        else
          rendered_lines = render(item, indent + inline_col).lines.map(&:chomp)
          output_lines[-1] += " #{rendered_lines.first}"
          rendered_lines.drop(1).each { |line| output_lines << ((' ' * inline_col) + line) }
        end
      end

      output_lines[-1] += ']'
      output_lines.join("\n")
    end

    def render_pairwise_vec(vec, indent)
      lines = ['[']

      vec.items.each_slice(2) do |pair|
        left, right = pair
        if pair.length == 2
          rendered_pair = render_pair(left, right, indent + INDENT)
          if rendered_pair
            lines << indent_block(rendered_pair, INDENT)
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
      return render(bindings, indent + '(let '.length, force_expand: true) if contains_comments?(bindings.items)

      hanging = render_hanging_pairwise_vec(bindings)
      hanging || render(bindings, indent + '(let '.length, layout: :pairwise)
    end

    def render_hanging_pairwise_vec(vec)
      pairs = vec.items.each_slice(2).to_a
      return unless pairs.all? { |pair| pair.length == 2 }

      rendered_pairs = pairs.map do |left, right|
        render_binding_pair(left, right)
      end
      return if rendered_pairs.any?(&:nil?)

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
      return '{}' if hash.entries.empty?

      output_lines = []

      hash.entries.each_with_index do |entry, idx|
        if comment?(entry)
          output_lines << "#{idx.zero? ? '{' : ' '}#{render(entry, indent + 1)}"
          next
        end

        key, value = entry
        first_pair = output_lines.empty?
        if hash_shorthand?(key, value)
          output_lines << "#{first_pair ? '{' : ' '}: #{value.name}"
          next
        end

        key_str = render_hash_key(key)
        value_col = indent + 1 + key_str.length + 1
        rendered_value = render(value, value_col)
        value_lines = rendered_value.lines(chomp: true)

        prefix = "#{first_pair ? '{' : ' '}#{key_str} "
        output_lines << "#{prefix}#{value_lines.first}"
        pad = ' ' * prefix.length
        value_lines.drop(1).each { |line| output_lines << "#{pad}#{line}" }
      end

      output_lines[-1] = "#{output_lines[-1]}}"
      output_lines.join("\n")
    end

    def flat_hash_pair(key, value)
      return ": #{value.name}" if hash_shorthand?(key, value)

      rendered_value = flat_render(value)
      return unless rendered_value

      "#{render_hash_key(key)} #{rendered_value}"
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
      return unless single_line?(left_rendered) && single_line?(right_rendered)

      pair = "#{left_rendered} #{right_rendered}"
      fits?(pair, indent) ? pair : nil
    end

    def render_binding_pair(left, right)
      left_rendered = flat_render(left)
      return unless left_rendered

      right_rendered = render(right, '(let ['.length + left_rendered.length + 1)
      first_line, *rest = right_rendered.lines(chomp: true)
      pair = "#{left_rendered} #{first_line}"
      return unless pair.length <= MAX_WIDTH

      return pair if rest.empty?

      continuation = ' ' * ('(let ['.length + left_rendered.length + 1)
      ([pair] + rest.map { |line| "#{continuation}#{line}" }).join("\n")
    end

    def hash_shorthand?(key, value)
      key.is_a?(Symbol) && value.is_a?(Sym) && key == Kapusta.kebab_to_snake(value.name).to_sym
    end

    def hashfn_literal?(form)
      return false unless form.is_a?(List)

      items = semantic_items(form.items)
      items.length == 2 &&
        items[0].is_a?(Sym) &&
        items[0].name == 'hashfn'
    end

    def allow_flat?(form, top_level: false, layout: nil)
      return false if layout == :pairwise && form.is_a?(Vec) && semantic_items(form.items).length > 2
      return true unless form.is_a?(List)
      return true if !multiline_in_source?(form) && form.respond_to?(:multiline_source)

      head = list_head(form)
      return true unless head.is_a?(Sym)

      case head.name
      when 'fn', 'lambda', 'λ', 'macro', 'when', 'unless', 'for', 'each', 'icollect', 'collect', 'fcollect',
           'accumulate', 'faccumulate'
        !top_level
      else
        !%w[let case match try catch finally do -> ->> -?> -?>> doto].include?(head.name)
      end
    end

    def force_multiline_body?(form)
      return force_multiline_body?(form.form) if form.is_a?(Quasiquote)
      return false unless form.is_a?(List)
      return true if multiline_in_source?(form)

      head = list_head(form)
      return false unless head.is_a?(Sym)

      case head.name
      when 'if', 'case', 'match', 'let', 'try', 'catch', 'finally', 'do', 'for', '->', '->>', '-?>', '-?>>', 'doto',
           'fn', 'lambda', 'λ', 'macro'
        true
      else
        flat = flat_render(form)
        flat && flat.length > 40
      end
    end

    def multiline_in_source?(form)
      form.respond_to?(:multiline_source) && form.multiline_source
    end

    def let_with_multiple_bindings?(form)
      head = list_head(form)
      return false unless head.is_a?(Sym) && head.name == 'let'

      bindings = semantic_items(form.items)[1]
      return false unless bindings.is_a?(Vec)

      semantic_items(bindings.items).length > 2
    end

    def let_with_nested_binding_value?(form)
      head = list_head(form)
      return false unless head.is_a?(Sym) && head.name == 'let'

      bindings = semantic_items(form.items)[1]
      return false unless bindings.is_a?(Vec)

      semantic_items(bindings.items).each_slice(2).any? do |_pattern, value|
        value && contains_collection?(value)
      end
    end

    def contains_collection?(form)
      case form
      when List then semantic_items(form.items).any? { |item| collection?(item) }
      when Vec then form.items.any? { |item| collection?(item) }
      when HashLit then form.pairs.any? { |k, v| collection?(k) || collection?(v) }
      else false
      end
    end

    def collection?(form)
      form.is_a?(List) || form.is_a?(Vec) || form.is_a?(HashLit)
    end

    def fn_form?(form)
      return false unless form.is_a?(List)

      head = list_head(form)
      head.is_a?(Sym) &&
        %w[fn lambda λ].include?(head.name)
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
      if updated[-1].lstrip.start_with?(';')
        updated << suffix
      else
        updated[-1] = "#{updated[-1]}#{suffix}"
      end
      updated.join("\n")
    end

    def render_generic_list(list, indent)
      lines = ['(']
      list.items.each do |item|
        lines << indent_block(render(item, indent + INDENT), INDENT)
      end
      append_suffix(lines, ')')
    end

    def render_sequential_head_form(head, raw_items, indent)
      lines = ["(#{head}"]
      semantic_index = 0

      raw_items.each do |item|
        if comment?(item)
          lines << indent_block(render(item, indent + INDENT), INDENT)
          next
        end

        rendered = render(item, indent + INDENT)
        if semantic_index.zero?
          candidate = "(#{head} #{rendered}"
          if lines.length == 1 && single_line?(rendered) && fits?(candidate, indent)
            lines[0] = candidate
          else
            lines << indent_block(rendered, INDENT)
          end
        else
          lines << indent_block(rendered, INDENT)
        end
        semantic_index += 1
      end

      append_suffix(lines, ')')
    end

    def contains_comments?(items)
      items.any? { |item| non_semantic?(item) }
    end

    def semantic_items(items)
      items.reject { |item| non_semantic?(item) }
    end

    def list_head(list)
      semantic_items(list.items).first
    end

    def list_rest(list)
      semantic_items(list.items).drop(1)
    end

    def list_raw_rest(list)
      index = list.items.index { |item| !comment?(item) }
      return list.items if index.nil?

      list.items[(index + 1)..] || []
    end

    def split_raw_items(items, semantic_count)
      split_index = 0
      seen = 0

      while split_index < items.length && seen < semantic_count
        seen += 1 unless comment?(items[split_index])
        split_index += 1
      end

      [items.take(split_index), items.drop(split_index)]
    end

    def print_help
      puts 'Usage: kapfmt [--fix] [--check] FILENAME...'
      puts
      puts 'Formats Kapusta source using the built-in Kapusta reader and pretty-printer.'
    end

    class Error < Kapusta::Error; end
  end
end
