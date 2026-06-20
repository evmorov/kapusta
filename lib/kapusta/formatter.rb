# frozen_string_literal: true

require_relative '../kapusta'
require_relative 'formatter/ast_helpers'
require_relative 'formatter/cli'
require_relative 'formatter/line_helpers'
require_relative 'formatter/validator'

module Kapusta
  class Formatter
    MAX_WIDTH = 80
    INDENT = 2
    STDIN_PATH = '-'
    BODY_ONLY_HEADS = %w[do finally].freeze
    SINGLE_PREFIX_BODY_HEADS = %w[
      while when unless for each icollect collect fcollect accumulate faccumulate module
    ].freeze
    CASE_HEADS = %w[case match].freeze
    private_constant :BODY_ONLY_HEADS, :SINGLE_PREFIX_BODY_HEADS, :CASE_HEADS
    include ASTHelpers
    include CLI
    include LineHelpers
    include Validator

    def self.format(source, path: nil)
      new([]).send(:format_source, source, path)
    end

    private

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
        flat_render_vec(form)
      when HashLit
        flat_render_hash(form)
      when List
        flat_render_list(form)
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

    def flat_render_vec(vec)
      return if contains_comments?(vec.items)
      return if multiline_in_source?(vec)

      flat_delimited_render(vec.items, '[', ']') { |item| flat_render(item) }
    end

    def flat_render_hash(hash)
      return if contains_comments?(hash.entries)
      return if multiline_in_source?(hash)

      flat_hash_render(hash.pairs)
    end

    def flat_render_list(list)
      return render_sigil(list) if list.sigil
      return if contains_comments?(list.items)
      return flat_render_hashfn(list) if hashfn_literal?(list)
      return if multiline_in_source?(list)
      return if let_with_multiple_bindings?(list)
      return if let_with_nested_binding_value?(list)

      flat_delimited_render(list.items, '(', ')') { |item| flat_render(item) }
    end

    def flat_render_hashfn(list)
      rendered = flat_render(semantic_items(list.items)[1])
      "##{rendered}" if rendered
    end

    def render_list(list, indent, top_level: false)
      return '()' if list.items.empty?
      return "##{render(semantic_items(list.items)[1], indent, top_level:)}" if hashfn_literal?(list)

      return render_generic_list(list, indent) unless list_head(list)

      name = head_name(list)
      raw_args = list_raw_rest(list)

      case name
      when *Compiler::Language::FUNCTION_DEFINITION_HEADS, 'macro'
        render_fn(name, list, indent, top_level:)
      when 'let' then render_let(list, indent)
      when *BODY_ONLY_HEADS then render_prefix_body_form(name, [], raw_args, indent)
      when 'try' then render_try(list, indent)
      when *SINGLE_PREFIX_BODY_HEADS then render_single_prefix_body_form(name, raw_args, indent)
      when 'class' then render_class(list, indent)
      when 'catch' then render_catch(list, indent)
      when 'if' then render_if(list, indent)
      when *CASE_HEADS then render_case_or_match(name, list, raw_args, indent)
      when *Compiler::Language::PIPELINE_HEADS then render_pipeline(name, raw_args, indent)
      else
        render_call(list, indent)
      end
    end

    def render_single_prefix_body_form(head, raw_args, indent)
      raw_prefix, raw_body = split_raw_items(raw_args, 1)
      render_prefix_body_form(head, raw_prefix, raw_body, indent)
    end

    def render_case_or_match(head, list, raw_args, indent)
      return render_sequential_head_form(head, raw_args, indent) if contains_comments?(raw_args)

      render_case(head, list_rest(list), indent)
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
        append_body_form(lines, form, indent, force_body_multiline:)
      end

      append_suffix(lines, ')')
    end

    def append_body_form(lines, form, indent, force_body_multiline: false)
      if blank_line?(form)
        lines << ''
        return
      end
      if comment?(form)
        lines << indent_block(render(form, indent + INDENT), INDENT)
        return
      end

      body = render(
        form,
        indent + INDENT,
        force_expand: force_body_multiline && force_multiline_body?(form)
      )
      lines << indent_block(body, INDENT)
    end

    def render_if(list, indent)
      args = list_rest(list)
      return render_sequential_head_form('if', list_raw_rest(list), indent) if contains_comments?(list_raw_rest(list))

      lines = []
      hanging = if_hanging

      if args.length == 3
        flat = flat_render(list)
        return flat if inline_three_arg_if?(args) && flat && fits?(flat, indent)

        append_if_form(lines, args[0], indent, '(if ')
        append_if_form(lines, args[1], indent, hanging)
        append_if_form(lines, args[2], indent, hanging)
        return append_suffix(lines, ')')
      end

      index = 0
      if args.length >= 2
        append_if_pair(lines, args[0], args[1], indent, '(if ')
        index = 2
      else
        lines << '(if'
      end

      while index < args.length
        remaining = args.length - index
        if remaining >= 2
          append_if_pair(lines, args[index], args[index + 1], indent, hanging)
          index += 2
        else
          append_if_form(lines, args[index], indent, hanging)
          index += 1
        end
      end

      append_suffix(lines, ')')
    end

    def append_if_pair(lines, condition, branch, indent, prefix)
      pair = render_pair(condition, branch, if_value_indent(indent))
      if pair
        lines << "#{prefix}#{pair}"
      else
        append_if_form(lines, condition, indent, prefix)
        append_if_form(lines, branch, indent, if_hanging)
      end
    end

    def append_if_form(lines, form, indent, prefix)
      lines << prefix_continuation(prefix, render(form, if_value_indent(indent)))
    end

    def if_value_indent(indent)
      indent + '(if '.length
    end

    def if_hanging
      ' ' * '(if '.length
    end

    def prefix_continuation(prefix, rendered)
      prefix_lines(prefix, rendered.lines(chomp: true)).join("\n")
    end

    def prefix_lines(prefix, lines)
      first_line, *rest = lines
      pad = ' ' * prefix.length
      ["#{prefix}#{first_line}", *rest.map { |line| line.empty? ? '' : "#{pad}#{line}" }]
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

      parsed.arm_pairs.each { |arm| append_case_arm(lines, arm, indent) }

      append_suffix(lines, ')')
    end

    def append_case_arm(lines, arm, indent)
      pattern, value = arm
      unless arm.length == 2
        lines << indent_block(render(pattern, indent + INDENT), INDENT)
        return
      end

      rendered_pair = render_pair(pattern, value, indent + INDENT)
      if rendered_pair
        lines << indent_block(rendered_pair, INDENT)
      else
        lines << indent_block(render(pattern, indent + INDENT), INDENT)
        lines << indent_block(render(value, indent + INDENT), INDENT)
      end
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

        flat_hash_render(form.pairs)
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

    def flat_hash_render(pairs)
      rendered = pairs.map { |pair| flat_hash_pair(pair) }
      return if rendered.any?(&:nil?)

      "{#{rendered.join(' ')}}"
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
        lines.concat(prefix_lines(prefix, render_multiline_vec_item(item, indent + 1).lines.map(&:chomp)))
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
        if hash_pair_shorthand?(entry)
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

    def flat_hash_pair(pair)
      key, value = pair
      return ": #{value.name}" if hash_pair_shorthand?(pair)

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

    def hash_pair_shorthand?(pair)
      pair.respond_to?(:shorthand?) && pair.shorthand?
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

    class Error < Kapusta::Error; end
  end
end
