# frozen_string_literal: true

require_relative '../kapusta'

module Kapusta
  class Formatter
    MAX_WIDTH = 80
    INDENT = 2
    STDIN_PATH = '-'

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
      return validate_macro_module_source(source, path) if macro_module_path?(path)

      Kapusta::Compiler.compile(source, path:)
    end

    def validate_macro_module_source(source, path)
      forms = Reader.read_all(source)
      raise Error, 'macro module has no export table' unless forms.last.is_a?(HashLit)

      processed = forms.map do |form|
        Compiler::MacroLowerer.lower_module_form(form, error_class: Error)
      end
      wrapper = List.new([List.new([Sym.new('fn'), Vec.new([]), *processed])])
      Compiler.compile_forms([wrapper], path:)
    rescue Kapusta::Error => e
      raise e.with_defaults(path:)
    end

    def macro_module_path?(path)
      path && File.extname(path) == '.kapm'
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
      lines.each_with_index.map do |line, i|
        next '' if line.empty?

        i.zero? ? "#{prefix}#{line}" : "#{pad}#{line}"
      end.join("\n")
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
      when *Compiler::Language::FUNCTION_DEFINITION_HEADS, 'macro'
        render_fn(head_name, list, indent, top_level:)
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
      when *Compiler::Language::PIPELINE_HEADS then render_pipeline(head_name, raw_args, indent)
      else
        render_call(list, indent)
      end
    end

    def render_fn(head, list, indent, top_level: false)
      args = list_rest(list)
      raw_args = list_raw_rest(list)
      prefix_length = Compiler::Language.parse_function_args(args)&.prefix_length || 1
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
      prefix_length = Compiler::Language.parse_class_args(args).prefix_length
      raw_prefix, raw_body = split_raw_items(raw_args, prefix_length)
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
      parsed = Compiler::Language.parse_let_args(list_rest(list))
      bindings = parsed.bindings
      raw_args = list_raw_rest(list)
      raw_prefix, raw_body = split_raw_items(raw_args, 1)
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
      parsed.body.each do |form|
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
      ["#{prefix}#{first_line}", *rest.map { |line| line.empty? ? '' : "#{pad}#{line}" }].join("\n")
    end

    def render_case(head, args, indent)
      parsed = Compiler::Language.parse_case_args(args)
      lines = ['(case']

      if parsed.subject
        rendered_subject = render(parsed.subject, indent + INDENT)
        if single_line?(rendered_subject) && fits?("(#{head} #{rendered_subject}", indent)
          lines[0] = "(#{head} #{rendered_subject}"
        else
          lines[0] = "(#{head}"
          lines << indent_block(rendered_subject, INDENT)
        end
      end

      parsed.arm_pairs.each do |pair|
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

    def render_call(list, indent, force_hang: false)
      head = flat_render(list_head(list))
      raise Error, "cannot format form head: #{list_head(list).inspect}" unless head

      base = "(#{head}"
      lines = [base]
      args = list_raw_rest(list)
      semantic_length = semantic_items(args).length
      hang_subsequent_args = force_hang || hang_call_args?(list, base, indent)

      semantic_index = 0
      hanging = nil
      args.each do |arg|
        if comment?(arg)
          lines << indent_block(render(arg, indent + INDENT), INDENT)
          next
        elsif semantic_index.zero?
          hanging = append_first_call_arg(lines, arg, base, indent, semantic_length)
        elsif append_packed_call_arg?(list, lines, arg, indent)
          nil
        elsif hanging && hang_subsequent_args
          lines << prefix_continuation(hanging, render(arg, indent + hanging.length))
        else
          lines << indent_block(render(arg, indent + INDENT), INDENT)
        end

        semantic_index += 1
      end

      append_suffix(lines, ')')
    end

    def append_first_call_arg(lines, arg, base, indent, semantic_length)
      first = render(
        arg,
        indent + base.length + 1,
        force_expand: semantic_length == 1 && fn_form?(arg)
      )
      first_line, *rest = first.lines(chomp: true)
      candidate = "#{base} #{first_line}"

      unless lines.length == 1 && fits?(candidate, indent)
        lines << indent_block(first, INDENT)
        return
      end

      hanging = ' ' * (base.length + 1)
      lines[0] = candidate
      rest.each { |line| lines << "#{hanging}#{line}" }
      hanging
    end

    def append_packed_call_arg?(list, lines, arg, indent)
      return false unless packable_call_arg?(list, arg)

      packed = packed_call_arg(lines.last, list, arg, indent)
      if packed
        lines[-1] = packed.first
        lines.concat(packed.drop(1))
        return true
      end

      false
    end

    def packable_call_arg?(list, arg)
      return false if fn_form?(arg)
      return true if packable_collection_call_arg?(list, arg)

      pack_call_args?(list) && flat_render(arg)
    end

    def packable_collection_call_arg?(list, arg)
      return true if arg.is_a?(Vec)

      arg.is_a?(HashLit) && packable_hash_call_arg?(list)
    end

    def packed_call_arg(current_line, list, arg, indent)
      packable_call_arg_renderings(list, arg, indent + current_line.length + 1).each do |rendered|
        first_line, *rest = rendered.lines(chomp: true)
        candidate = "#{current_line} #{first_line}"
        next unless inline_arg_fits?(candidate, indent)

        hanging = ' ' * (current_line.length + 1)
        return [candidate, *rest.map { |line| "#{hanging}#{line}" }]
      end

      nil
    end

    def packable_call_arg_renderings(list, arg, indent)
      [
        flat_collection_render(arg),
        flat_render(arg),
        multiline_packable_call_arg_rendering(list, arg, indent)
      ].compact.uniq
    end

    def multiline_packable_call_arg_rendering(list, arg, indent)
      return render(arg, indent) if arg.is_a?(Vec)
      return render(arg, indent) if local_hash_call_arg?(list, arg)

      nil
    end

    def local_hash_call_arg?(list, arg)
      arg.is_a?(HashLit) && head_name(list) == 'local'
    end

    def flat_collection_render(form)
      case form
      when Vec
        flat_delimited_render(form.items, '[', ']') { |item| flat_render(item) }
      when HashLit
        return if contains_comments?(form.entries)

        flat_delimited_render(form.pairs, '{', '}') { |key, value| flat_hash_pair(key, value) }
      end
    end

    def flat_delimited_render(items, open, close)
      return if contains_comments?(items)

      rendered = items.map do |item|
        item.is_a?(Array) ? yield(*item) : yield(item)
      end
      return if rendered.any?(&:nil?)

      "#{open}#{rendered.join(' ')}#{close}"
    end

    def hang_call_args?(list, base, indent)
      return true if source_hangs_call_args?(list, base)
      return true if set_function_value?(list)

      flat = flat_call_render(list)
      return false unless flat

      overflowing = !fits?(flat, indent)
      return true if overflowing && hanging_overflow_call?(list)

      operator_call?(list) && overflowing
    end

    def pack_call_args?(list)
      head_name(list)&.match?(/\A[a-z0-9_-][\w-]*\./)
    end

    def packable_hash_call_arg?(list)
      head_name(list) == 'local' || pack_call_args?(list)
    end

    def hanging_overflow_call?(list)
      hash_first_call_arg?(list) || pack_call_args?(list)
    end

    def hash_first_call_arg?(list)
      list_rest(list).first.is_a?(HashLit)
    end

    def set_function_value?(list)
      head_name(list) == 'set' && fn_form?(list_rest(list)[1])
    end

    def source_hangs_call_args?(list, base)
      return false unless list.respond_to?(:column) && list.column

      args = list_rest(list)
      return false if args.length < 2

      expected_column = list.column + base.length + 1
      args.drop(1).all? do |arg|
        arg.respond_to?(:column) && arg.column == expected_column
      end
    end

    def operator_call?(list)
      head_name(list)&.match?(/\A[^\w.]+\z/)
    end

    def ordinary_call_form?(list)
      name = head_name(list)
      name && !Compiler::Language::SPECIAL_FORMS.include?(name)
    end

    def flat_call_render(list)
      head = flat_render(list_head(list))
      return unless head

      rendered_args = semantic_items(list_raw_rest(list)).map { |arg| flat_call_arg_render(arg) }
      return if rendered_args.any?(&:nil?)

      "(#{[head, *rendered_args].join(' ')})"
    end

    def flat_call_arg_render(arg)
      collection = flat_collection_render(arg)
      return collection if collection

      flat_render(arg)
    end

    def render_vec(vec, indent, layout: nil, top_level: false, force_expand: false)
      flat = flat_render(vec)
      return flat if !force_expand && flat && fits?(flat, indent) && allow_flat?(vec, top_level:, layout:)

      return render_pairwise_vec(vec, indent) if layout == :pairwise && !contains_comments?(vec.items)
      if multiline_in_source?(vec) && multiline_vec_items_should_separate?(vec) && !contains_comments?(vec.items)
        return render_multiline_vec(vec, indent)
      end
      return render_filled_vec(vec, indent) if !contains_comments?(vec.items) && !vec.items.empty?

      lines = ['[']
      vec.items.each do |item|
        lines << indent_block(render(item, indent + INDENT), INDENT)
      end
      append_suffix(lines, ']')
    end

    def render_multiline_vec(vec, indent)
      return '[]' if vec.items.empty?

      lines = []
      vec.items.each_with_index do |item, idx|
        prefix = idx.zero? ? '[' : ' '
        rendered_lines = render_multiline_vec_item(item, indent + 1).lines.map(&:chomp)
        lines << "#{prefix}#{rendered_lines.first}"
        pad = ' ' * prefix.length
        rendered_lines.drop(1).each { |line| lines << "#{pad}#{line}" }
      end
      lines[-1] = "#{lines[-1]}]"
      lines.join("\n")
    end

    def render_multiline_vec_item(item, indent)
      return render_call(item, indent, force_hang: true) if hanging_multiline_vec_call_item?(item)

      render(item, indent)
    end

    def hanging_multiline_vec_call_item?(item)
      item.is_a?(List) && multiline_in_source?(item) && ordinary_call_form?(item)
    end

    def multiline_vec_items_should_separate?(vec)
      multiline_vec_items_on_separate_lines?(vec) || semantic_items(vec.items).all? { |item| collection?(item) }
    end

    def multiline_vec_items_on_separate_lines?(vec)
      items = semantic_items(vec.items)
      return false if items.length < 2

      lines = items.filter_map { |item| item.line if item.respond_to?(:line) }
      return true if lines.length < 2

      lines.uniq.length == lines.length
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

      hanging = render_hanging_pairwise_vec(bindings, indent)
      hanging || render(bindings, indent + '(let '.length, layout: :pairwise)
    end

    def render_hanging_pairwise_vec(vec, indent)
      pairs = vec.items.each_slice(2).to_a
      return unless pairs.all? { |pair| pair.length == 2 }

      rendered_pairs = pairs.map do |left, right|
        render_binding_pair(left, right, indent)
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

    def render_binding_pair(left, right, indent)
      left_rendered = flat_render(left)
      return unless left_rendered

      right_indent = indent + '(let ['.length + left_rendered.length + 1
      right_rendered = render(right, right_indent)
      first_line, *rest = right_rendered.lines(chomp: true)
      pair = "#{left_rendered} #{first_line}"
      return unless fits?(pair, indent + '(let ['.length)

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
      when *Compiler::Language::FLAT_BODY_HEADS
        !top_level
      else
        !Compiler::Language.never_flat_head?(head.name)
      end
    end

    def force_multiline_body?(form)
      return force_multiline_body?(form.form) if form.is_a?(Quasiquote)
      return false unless form.is_a?(List)
      return true if multiline_in_source?(form)

      head = list_head(form)
      return false unless head.is_a?(Sym)

      case head.name
      when *Compiler::Language::MULTILINE_BODY_HEADS
        true
      else
        false
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
        Compiler::Language.function_head?(head.name)
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

    def inline_arg_fits?(text, indent)
      !text.include?("\n") && indent + text.length < MAX_WIDTH
    end

    def single_line?(text)
      !text.include?("\n")
    end

    def indent_block(text, amount)
      prefix = ' ' * amount
      text.lines.map { |line| line.strip.empty? ? blank_line_for(line) : "#{prefix}#{line}" }.join
    end

    def blank_line_for(line)
      line.end_with?("\n") ? "\n" : ''
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

    def head_name(list)
      head = list_head(list)
      head.name if head.is_a?(Sym)
    end

    def list_rest(list)
      semantic_items(list.items).drop(1)
    end

    def list_raw_rest(list)
      index = list.items.index { |item| !non_semantic?(item) }
      return list.items if index.nil?

      list.items[(index + 1)..] || []
    end

    def split_raw_items(items, semantic_count)
      split_index = 0
      seen = 0

      while split_index < items.length && seen < semantic_count
        seen += 1 unless non_semantic?(items[split_index])
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
