# frozen_string_literal: true

require_relative '../reader'
require_relative '../compiler'
require_relative 'scope_walker'
require_relative 'identifier'

module Kapusta
  class LSP
    module Rename
      RESPONSE_REQUEST_FAILED = -32_803

      Target = Struct.new(:kind, :sym, :name, :segment_index, :segment_prefix,
                          :seg_start, :seg_end, :binding, :walker, keyword_init: true)

      module_function

      def prepare(text, line_zero, character)
        target = locate(text, line_zero, character)
        return unless target

        {
          range: lsp_range(target.sym.line, target.seg_start, target.seg_end),
          placeholder: placeholder_for(target)
        }
      end

      def perform(uri, text, line_zero, character, new_name, workspace_index: nil)
        target = locate(text, line_zero, character)
        return error('rename not available at this position') unless target

        case target.kind
        when :local
          rename_local(uri, target, new_name)
        when :toplevel_fn, :free_toplevel
          return error('cross-file rename requires a workspace') unless workspace_index

          rename_toplevel(target, new_name, workspace_index)
        when :constant, :free_constant
          return error('cross-file rename requires a workspace') unless workspace_index

          rename_constant(target, new_name, workspace_index)
        when :macro
          return error('cross-file rename requires a workspace') unless workspace_index

          rename_macro(uri, target, new_name, workspace_index)
        else
          error("rename not supported for #{target.kind}")
        end
      end

      def locate(text, line_zero, character)
        forms = parse(text)
        return unless forms

        walker = ScopeWalker.analyze(forms)
        line = line_zero + 1
        col = character + 1

        sym = sym_at_cursor(walker, line, col)
        return unless sym
        return if synthetic?(sym)

        seg = segment_at_column(sym, col)
        return unless seg && seg[:index] != :on_dot

        binding = walker.bindings.find { |b| b.sym.equal?(sym) }
        reference = walker.references.find { |r| r.sym.equal?(sym) }

        classify(walker, sym, binding, reference, seg)
      end

      def parse(text)
        Reader.read_all(text)
      rescue Kapusta::Error
        nil
      end

      def sym_at_cursor(walker, line, col)
        candidates = []
        walker.bindings.each do |b|
          candidates << b.sym if b.line == line && col >= b.column && col <= b.end_column
        end
        walker.references.each do |r|
          candidates << r.sym if r.line == line && col >= r.column && col <= r.end_column
        end
        candidates.first
      end

      def synthetic?(sym)
        return true if sym.is_a?(MacroSym) || sym.is_a?(AutoGensym)

        name = sym.name
        name == '_' || name == '&' || name == '...' ||
          name == '$' || name == '$...' || name.match?(/\A\$\d\z/)
      end

      def segment_at_column(sym, col)
        unless sym.dotted?
          start_col = sym.column
          end_col = sym.column + sym.name.length
          return unless col.between?(start_col, end_col)

          return { index: 0, start: start_col, end: end_col }
        end

        pos = sym.column
        segments = sym.segments
        segments.each_with_index do |seg, k|
          seg_start = pos
          seg_end = pos + seg.length
          return { index: k, start: seg_start, end: seg_end } if col >= seg_start && col < seg_end

          if k < segments.length - 1
            return { index: :on_dot, start: seg_end, end: seg_end + 1 } if col == seg_end
          elsif col == seg_end
            return { index: k, start: seg_start, end: seg_end }
          end
          pos = seg_end + 1
        end
        nil
      end

      def classify(walker, sym, binding, reference, seg)
        if sym.dotted? && seg[:index].positive?
          segment_text = sym.segments[seg[:index]]
          return if segment_text.match?(/\A[a-z]/)
        end

        if binding
          return if binding.kind == :method

          return constant_target(walker, binding, seg) if %i[module class].include?(binding.kind)

          return local_target(walker, binding, seg)
        end

        if reference
          target = reference.target
          if target
            return if target.kind == :method
            return constant_target(walker, target, seg, sym:) if %i[module class].include?(target.kind)

            return local_target(walker, target, seg, sym:)
          end
        end

        first_seg = sym.dotted? ? sym.segments.first : sym.name
        if first_seg.match?(/\A[A-Z]/)
          Target.new(
            kind: :free_constant, sym:, name: sym.name,
            segment_index: seg[:index], segment_prefix: (sym.dotted? ? sym.segments[0..seg[:index]] : [sym.name]),
            seg_start: seg[:start], seg_end: seg[:end], walker:
          )
        else
          Target.new(
            kind: :free_toplevel, sym:, name: sym.name,
            segment_index: seg[:index], seg_start: seg[:start], seg_end: seg[:end], walker:
          )
        end
      end

      def local_target(walker, binding, seg, sym: nil)
        kind = case binding.kind
               when :toplevel_fn then :toplevel_fn
               when :macro, :macro_import then :macro
               else :local
               end
        Target.new(
          kind:,
          sym: sym || binding.sym,
          name: binding.name,
          segment_index: seg[:index],
          seg_start: seg[:start],
          seg_end: seg[:end],
          binding:,
          walker:
        )
      end

      def constant_target(walker, binding, seg, sym: nil)
        the_sym = sym || binding.sym
        prefix = the_sym.dotted? ? the_sym.segments[0..seg[:index]] : [the_sym.name]
        Target.new(
          kind: :constant,
          sym: the_sym,
          name: binding.name,
          segment_index: seg[:index],
          segment_prefix: prefix,
          seg_start: seg[:start],
          seg_end: seg[:end],
          binding:,
          walker:
        )
      end

      def placeholder_for(target)
        return target.segment_prefix.last if target.segment_prefix

        target.name
      end

      def lsp_range(line, start_col, end_col)
        {
          start: { line: line - 1, character: start_col - 1 },
          end: { line: line - 1, character: end_col - 1 }
        }
      end

      def rename_local(uri, target, new_name)
        return error("invalid identifier: #{new_name}") unless Identifier.valid_local?(new_name)
        return error('cannot resolve binding') unless target.binding

        walker = target.walker
        binding = target.binding
        scope = binding.scope

        edits_targets = collect_local_targets(walker, binding)
        if conflict_local?(scope, new_name, edits_targets, walker, binding)
          return error("rename conflict: '#{new_name}' is already in scope")
        end

        edits = edits_targets.map { |t| text_edit_first_segment(t, new_name) }
        { changes: { uri => edits } }
      end

      def collect_local_targets(walker, binding)
        scope = binding.scope
        results = []
        walker.bindings.each do |b|
          results << b if b.name == binding.name && b.scope.equal?(scope)
        end
        walker.references.each do |r|
          results << r if r.target.equal?(binding)
        end
        results
      end

      def conflict_local?(scope, new_name, targets, _walker, binding)
        return true if scope.bindings[new_name] && !scope.bindings[new_name].equal?(binding)

        targets.any? do |t|
          next false unless t.is_a?(ScopeWalker::Reference)

          shadowed_in_chain?(t.scope, new_name, scope)
        end
      end

      def shadowed_in_chain?(ref_scope, new_name, target_scope)
        s = ref_scope
        while s && !s.equal?(target_scope)
          return true if s.bindings.key?(new_name)

          s = s.parent
        end
        false
      end

      def rename_toplevel(target, new_name, workspace_index)
        return error("invalid identifier: #{new_name}") unless Identifier.valid_local?(new_name)

        per_uri = workspace_index.toplevel_fn_occurrences(target.name)
        return error('no occurrences found') if per_uri.empty?

        if workspace_index.toplevel_definition?(new_name, except_name: target.name)
          return error("rename conflict: '#{new_name}' is already defined in the workspace")
        end

        changes = per_uri.transform_values do |occs|
          occs.map { |o| text_edit_first_segment(o, new_name) }
        end
        { changes: }
      end

      def rename_macro(uri, target, new_name, workspace_index)
        return error("invalid identifier: #{new_name}") unless Identifier.valid_local?(new_name)
        return error('cannot resolve binding') unless target.binding

        def_uri, def_binding = locate_macro_definition(uri, target.binding, workspace_index)
        return error('macro definition not found') unless def_uri && def_binding

        if workspace_index.macro_definition_anywhere?(new_name, except_uri: def_uri) ||
           macro_defined_in_file?(workspace_index.entry(def_uri), new_name, except: def_binding)
          return error("rename conflict: macro '#{new_name}' is already defined in the workspace")
        end

        changes = collect_macro_changes(def_uri, def_binding, new_name, workspace_index)
        return error('no occurrences found') if changes.empty?

        { changes: }
      end

      def locate_macro_definition(uri, binding, workspace_index)
        case binding.kind
        when :macro
          entry = workspace_index.entry(uri)
          return unless entry

          indexed = entry.walker.bindings.find { |b| b.kind == :macro && b.name == binding.name }
          indexed ? [uri, indexed] : nil
        when :macro_import
          workspace_index.find_macro_definition(uri, binding.import_module, binding.import_key)
        end
      end

      def macro_defined_in_file?(entry, name, except:)
        return false unless entry

        entry.walker.bindings.any? do |b|
          b.kind == :macro && b.name == name && !b.equal?(except)
        end
      end

      def collect_macro_changes(def_uri, def_binding, new_name, workspace_index)
        changes = {}

        def_entry = workspace_index.entry(def_uri)
        if def_entry
          targets = def_entry.walker.bindings.select { |b| b.equal?(def_binding) }
          targets += def_entry.walker.references.select do |r|
            r.target.equal?(def_binding) || (r.target.nil? && r.name == def_binding.name)
          end
          changes[def_uri] = targets.map { |t| text_edit_first_segment(t, new_name) } unless targets.empty?
        end

        workspace_index.each_entry do |uri, entry|
          next if uri == def_uri

          imports = entry.walker.bindings.select do |b|
            next false unless b.kind == :macro_import
            next false unless b.import_key.to_s.tr('_', '-') == def_binding.name

            workspace_index.import_resolves_to?(uri, b.import_module, def_uri)
          end
          next if imports.empty?

          refs = entry.walker.references.select do |r|
            imports.any? { |imp| imp.equal?(r.target) }
          end
          changes[uri] = (imports + refs).map { |t| text_edit_first_segment(t, new_name) }
        end

        changes
      end

      def rename_constant(target, new_name, workspace_index)
        unless Identifier.valid_constant_segment?(new_name)
          return error("class and module names must start with an uppercase letter (got #{new_name.inspect})")
        end

        prefix = target.segment_prefix
        seg_index = target.segment_index
        per_uri = workspace_index.constant_occurrences(prefix)
        return error('no occurrences found') if per_uri.empty?

        new_prefix = prefix.dup
        new_prefix[seg_index] = new_name
        if workspace_index.constant_definition_with_prefix?(new_prefix, except_prefix: prefix)
          return error("rename conflict: constant '#{new_prefix.join('.')}' is already defined")
        end

        changes = {}
        per_uri.each do |uri, occs|
          changes[uri] = occs.map do |occ|
            seg_start, seg_end = segment_range(occ.sym, seg_index)
            {
              range: {
                start: { line: occ.line - 1, character: seg_start - 1 },
                end: { line: occ.line - 1, character: seg_end - 1 }
              },
              newText: new_name
            }
          end
        end
        { changes: }
      end

      def segment_range(sym, segment_index)
        return [sym.column, sym.column + sym.name.length] unless sym.dotted?

        segments = sym.segments
        prior = segments[0...segment_index].sum { |s| s.length + 1 }
        start_col = sym.column + prior
        [start_col, start_col + segments[segment_index].length]
      end

      def text_edit_full(occurrence, new_name)
        line = occurrence.line - 1
        start_col = occurrence.column - 1
        end_col = occurrence.end_column - 1
        {
          range: {
            start: { line:, character: start_col },
            end: { line:, character: end_col }
          },
          newText: new_name
        }
      end

      def text_edit_first_segment(occurrence, new_name)
        sym = occurrence.sym
        return text_edit_full(occurrence, new_name) unless sym.is_a?(Sym) && sym.dotted?

        seg_start, seg_end = segment_range(sym, 0)
        {
          range: {
            start: { line: occurrence.line - 1, character: seg_start - 1 },
            end: { line: occurrence.line - 1, character: seg_end - 1 }
          },
          newText: new_name
        }
      end

      def error(message)
        { error: { code: RESPONSE_REQUEST_FAILED, message: } }
      end
    end
  end
end
