# frozen_string_literal: true

require_relative '../ast'
require_relative '../compiler'

module Kapusta
  class LSP
    class ScopeWalker
      Binding = Struct.new(:kind, :name, :line, :column, :end_column, :scope, :segments,
                           :sym, :in_module_or_class, :import_module, :import_key, keyword_init: true)
      Reference = Struct.new(:name, :line, :column, :end_column, :scope, :sym,
                             :target, keyword_init: true)
      Scope = Struct.new(:id, :parent, :bindings, :kind) do
        def lookup(name)
          bindings[name] || parent&.lookup(name)
        end
      end
      EndMarker = Struct.new(:line, :column, :end_column, :target, keyword_init: true)

      DISPATCHERS = {
        'macros' => :skip,
        **Compiler::Language::QUASI_HEADS.to_h { |head| [head, :skip] },
        'let' => :walk_let,
        **Compiler::Language::BINDING_HEADS.to_h { |head| [head, :walk_local_var] },
        'global' => :walk_global,
        'set' => :walk_set,
        **Compiler::Language::FUNCTION_DEFINITION_HEADS.to_h { |head| [head, :walk_fn] },
        'for' => :walk_for,
        'each' => :walk_each_like,
        'collect' => :walk_each_like,
        'icollect' => :walk_each_like,
        'fcollect' => :walk_for_like,
        'accumulate' => :walk_accumulate,
        'faccumulate' => :walk_faccumulate,
        'case' => :walk_case_match,
        'match' => :walk_case_match,
        'try' => :walk_try,
        'module' => :walk_module_class,
        'class' => :walk_module_class,
        'hashfn' => :walk_hashfn,
        'macro' => :walk_macro_def,
        'import-macros' => :walk_import_macros,
        'ivar' => :walk_sigil_form,
        'cvar' => :walk_sigil_form,
        'gvar' => :walk_sigil_form
      }.freeze

      attr_reader :bindings, :references, :root_scope, :end_markers

      def self.analyze(forms)
        walker = new
        walker.walk_top(forms)
        walker
      end

      def initialize
        @bindings = []
        @references = []
        @end_markers = []
        @scope_seq = 0
        @root_scope = make_scope(nil, :file)
        @gvar_scope = make_scope(nil, :gvars)
        @in_module_or_class = 0
        @sigil_scope_stack = [make_sigil_scopes]
      end

      def walk_top(forms)
        walk_form_run(forms, 0, @root_scope)
        resolve_late_references
      end

      def resolve_late_references
        @references.each do |r|
          next if r.target
          next unless r.scope

          target = r.scope.lookup(r.name)
          r.target = target if target
        end
      end

      def walk_form_run(forms, start, scope, header_target: nil)
        i = start
        while i < forms.length
          form = forms[i]
          if end_form?(form)
            record_end_marker(form, header_target) if header_target
            return i + 1
          end

          if Compiler::Language.bodyless_header?(form)
            i = walk_bodyless_header(form, forms, i + 1, scope)
            next
          end

          walk_form(form, scope)
          i += 1
        end
        i
      end

      def record_end_marker(form, target)
        head = form.head
        return unless head.is_a?(Sym) && head.respond_to?(:line) && head.line

        @end_markers << EndMarker.new(
          line: head.line,
          column: head.column,
          end_column: head.column + head.name.length,
          target:
        )
      end

      def end_form?(form)
        Compiler::Language.end_form?(form)
      end

      def binding_at(line, column)
        @bindings.each do |b|
          return b if b.line == line && column >= b.column && column <= b.end_column
        end
        nil
      end

      def reference_at(line, column)
        @references.each do |r|
          return r if r.line == line && column >= r.column && column <= r.end_column
        end
        nil
      end

      def sym_at(line, column)
        binding_at(line, column) || reference_at(line, column)
      end

      private

      def make_scope(parent, kind)
        @scope_seq += 1
        Scope.new(@scope_seq, parent, {}, kind)
      end

      def walk_bodyless_header(form, forms, body_start, scope)
        case form.head.name
        when 'module'
          parsed = Compiler::Language.parse_module_form(form)
          binding = parsed.name.is_a?(Sym) ? add_constant_binding(parsed.name, scope, :module) : nil
          inside_module_or_class do
            if parsed.body.length == 1 && Compiler::Language.bodyless_header?(parsed.body[0])
              walk_bodyless_header(parsed.body[0], forms, body_start, scope)
            else
              body_scope = make_scope(scope, :module)
              walk_form_run(forms, body_start, body_scope, header_target: binding)
            end
          end
        when 'class'
          parsed = Compiler::Language.parse_class_form(form)
          parsed.supers&.items&.each { |item| walk_form(item, scope) }
          binding = parsed.name.is_a?(Sym) ? add_constant_binding(parsed.name, scope, :class) : nil
          inside_class do
            body_scope = make_scope(scope, :class)
            walk_form_run(forms, body_start, body_scope, header_target: binding)
          end
        end
      end

      def inside_module_or_class
        @in_module_or_class += 1
        yield
      ensure
        @in_module_or_class -= 1
      end

      def inside_class
        inside_module_or_class do
          @sigil_scope_stack.push(make_sigil_scopes)
          begin
            yield
          ensure
            @sigil_scope_stack.pop
          end
        end
      end

      def make_sigil_scopes
        { ivar: make_scope(nil, :ivars), cvar: make_scope(nil, :cvars) }
      end

      def walk_form(form, scope)
        case form
        when List then walk_list(form, scope)
        when Vec then form.items.each { |item| walk_form(item, scope) }
        when HashLit then walk_hash(form, scope)
        when Sym then walk_reference(form, scope)
        when Quasiquote then walk_quasi(form.form, scope)
        when Unquote, UnquoteSplice then walk_form(form.form, scope)
        end
      end

      def walk_hash(hash, scope)
        hash.entries.each do |entry|
          next unless entry.is_a?(Array)

          _key, value = entry
          walk_form(value, scope)
        end
      end

      def walk_quasi(form, scope)
        case form
        when Unquote, UnquoteSplice then walk_form(form.form, scope)
        when List, Vec then form.items.each { |item| walk_quasi(item, scope) }
        when HashLit
          form.entries.each do |entry|
            next unless entry.is_a?(Array)

            _key, value = entry
            walk_quasi(value, scope)
          end
        end
      end

      def walk_list(list, scope)
        return if list.empty?

        head = list.head
        unless head.is_a?(Sym)
          list.items.each { |item| walk_form(item, scope) }
          return
        end

        dispatcher = DISPATCHERS[head.name]
        if dispatcher
          return if dispatcher == :skip

          return send(dispatcher, list, scope)
        end

        list.items.each { |item| walk_form(item, scope) }
      end

      def walk_let(list, scope)
        parsed = Compiler::Language.parse_let_form(list)
        return unless parsed.bindings.is_a?(Vec)

        let_scope = make_scope(scope, :let)
        parsed.binding_pairs.each do |name_pat, value|
          walk_form(value, let_scope) if value
          bind_pattern(name_pat, let_scope, :let)
        end
        parsed.body.each { |form| walk_form(form, let_scope) }
      end

      def walk_local_var(list, scope)
        parsed = Compiler::Language.parse_binding_form(list)
        return unless parsed

        walk_form(parsed.value, scope)
        bind_pattern(parsed.target, scope, parsed.mutable? ? :var : :local)
      end

      def walk_global(list, _scope)
        parsed = Compiler::Language.parse_global_form(list)
        walk_form(parsed.value, @root_scope) if parsed
      end

      def walk_hashfn(list, scope)
        Compiler::Language.parse_hashfn_form(list).body.each { |form| walk_form(form, scope) }
      end

      def walk_macro_def(list, scope)
        parsed = Compiler::Language.parse_macro_definition_form(list)
        return unless parsed.name.is_a?(Sym) && parsed.params.is_a?(Vec)

        add_binding(parsed.name, @root_scope, :macro)
        fn_scope = make_scope(scope, :fn)
        bind_param_vec(parsed.params, fn_scope)
        parsed.body.each { |form| walk_form(form, fn_scope) }
      end

      def walk_import_macros(list, scope)
        parsed = Compiler::Language.parse_import_macros_form(list)
        return unless parsed.destructure.is_a?(HashLit)
        return unless parsed.module_arg.is_a?(Symbol) || parsed.module_arg.is_a?(String)

        module_label = parsed.module_arg.to_s.tr('_', '-')
        parsed.destructure.pairs.each do |key, target|
          next unless target.is_a?(Sym) && key.is_a?(Symbol)

          add_import_macro_binding(target, scope, module_label, key)
        end
      end

      def add_import_macro_binding(sym, _scope, module_label, import_key)
        b = Binding.new(
          kind: :macro_import,
          name: sym.name,
          line: sym.line,
          column: sym.column,
          end_column: sym.column + sym.name.length,
          scope: @root_scope,
          segments: sym.dotted? ? sym.segments : nil,
          sym:,
          in_module_or_class: false,
          import_module: module_label,
          import_key:
        )
        @bindings << b
        @root_scope.bindings[sym.name] = b
        b
      end

      def walk_set(list, scope)
        parsed = Compiler::Language.parse_set_form(list)
        target = parsed.target
        walk_form(parsed.value, scope) if parsed.value
        if target.is_a?(List)
          walk_form(target, scope)
          return
        end
        return unless target.is_a?(Sym) && !target.dotted?

        existing = scope.lookup(target.name)
        if existing
          add_reference(target, scope, existing)
        else
          add_binding(target, scope, :set)
        end
      end

      def walk_sigil_form(list, _scope)
        parsed = Compiler::Language.parse_sigil_form(list)
        return unless parsed&.name.is_a?(Sym)

        target_scope = sigil_target_scope(parsed.kind)
        existing = target_scope.bindings[parsed.name.name]
        if existing
          add_reference(parsed.name, target_scope, existing)
        else
          add_binding(parsed.name, target_scope, parsed.kind)
        end
      end

      def sigil_target_scope(kind)
        case kind
        when :ivar, :cvar then @sigil_scope_stack.last.fetch(kind)
        when :gvar then @gvar_scope
        end
      end

      def walk_fn(list, scope)
        parsed = Compiler::Language.parse_function_form(list, heads: Compiler::Language::FUNCTION_DEFINITION_HEADS)
        unless parsed
          list.items[1..]&.each { |item| walk_form(item, scope) }
          return
        end

        fn_scope = make_scope(scope, :fn)
        if parsed.named?
          kind = if method_definition_context?
                   :method
                 else
                   (scope == @root_scope ? :toplevel_fn : :fn_local)
                 end
          binding = add_binding(parsed.name, scope, kind, lexical: true)
          fn_scope.bindings[parsed.name.name] = binding unless kind == :method
        end
        bind_param_vec(parsed.params, fn_scope)
        parsed.body.each { |form| walk_form(form, fn_scope) }
      end

      def method_definition_context?
        @in_module_or_class.positive?
      end

      def walk_for(list, scope)
        parsed = Compiler::Language.parse_counted_for_form(list)
        return unless parsed.bindings.is_a?(Vec)

        for_scope = make_scope(scope, :for)
        until_forms = []
        [parsed.start, parsed.finish].compact.each { |form| walk_form(form, scope) }
        parsed.each_extra do |kind, form|
          next unless form

          kind == :until ? until_forms << form : walk_form(form, scope)
        end
        bind_pattern(parsed.counter, for_scope, :for_counter) if parsed.counter
        until_forms.each { |form| walk_form(form, for_scope) }
        parsed.body.each { |form| walk_form(form, for_scope) }
      end

      def walk_for_like(list, scope) = walk_for(list, scope)

      def walk_each_like(list, scope)
        parsed = Compiler::Language.parse_iteration_form(list)
        bindings_vec = parsed.bindings
        return unless bindings_vec.is_a?(Vec)

        return if parsed.items.empty?

        each_scope = make_scope(scope, :each)
        walk_form(parsed.iter_expr, scope)
        parsed.binding_pats.each { |b| bind_pattern(b, each_scope, :each_var) }
        parsed.body.each { |form| walk_form(form, each_scope) }
      end

      def walk_accumulate(list, scope)
        parsed = Compiler::Language.parse_accumulate_form(list)
        return unless parsed.bindings.is_a?(Vec)

        return if parsed.items.length < 4

        acc_scope = make_scope(scope, :accumulate)
        walk_form(parsed.initial, scope)
        bind_pattern(parsed.acc_name, acc_scope, :accumulator)
        walk_form(parsed.iter_expr, scope)
        parsed.binding_pats.each { |b| bind_pattern(b, acc_scope, :each_var) }
        parsed.body.each { |form| walk_form(form, acc_scope) }
      end

      def walk_faccumulate(list, scope)
        parsed = Compiler::Language.parse_faccumulate_form(list)
        return unless parsed.bindings.is_a?(Vec)

        return if parsed.items.length < 5

        acc_scope = make_scope(scope, :faccumulate)
        walk_form(parsed.initial, scope)
        [parsed.start, parsed.finish, parsed.step].compact.each { |form| walk_form(form, scope) }
        bind_pattern(parsed.acc_name, acc_scope, :accumulator)
        bind_pattern(parsed.counter, acc_scope, :for_counter)
        parsed.body.each { |form| walk_form(form, acc_scope) }
      end

      def walk_case_match(list, scope)
        mode = Compiler::Language.list_head_name(list) == 'match' ? :match : :case
        parsed = Compiler::Language.parse_case_form(list)
        walk_form(parsed.subject, scope)
        parsed.arm_pairs.each do |pattern, body|
          arm_scope = make_scope(scope, :case_arm)
          walk_pattern(pattern, arm_scope, scope, mode)
          walk_form(body, arm_scope) if body
        end
      end

      def walk_try(list, scope)
        parsed = Compiler::Language.parse_try_form(list)
        walk_form(parsed.body, scope)
        parsed.clauses.each do |clause|
          case clause
          when Compiler::Language::CatchClause then walk_catch(clause, scope)
          when Compiler::Language::FinallyClause
            clause.body.each { |form| walk_form(form, scope) }
          end
        end
      end

      def walk_catch(clause, scope)
        walk_form(clause.klass, scope) if clause.klass
        catch_scope = make_scope(scope, :catch)
        bind_pattern(clause.bind_sym, catch_scope, :catch) if clause.bind_sym.is_a?(Sym)
        clause.body.each { |form| walk_form(form, catch_scope) }
      end

      def walk_module_class(list, scope)
        if (module_form = Compiler::Language.parse_module_form(list))
          kind = :module
          name_sym = module_form.name
          body = module_form.body
        else
          kind = :class
          parsed = Compiler::Language.parse_class_form(list)
          name_sym = parsed.name
          parsed.supers&.items&.each { |item| walk_form(item, scope) }
          body = parsed.body
        end

        add_constant_binding(name_sym, scope, kind) if name_sym.is_a?(Sym)

        body_scope = make_scope(scope, kind)
        if kind == :class
          inside_class { body.each { |form| walk_form(form, body_scope) } }
        else
          inside_module_or_class { body.each { |form| walk_form(form, body_scope) } }
        end
      end

      def walk_reference(sym, scope)
        return if hashfn_synthetic?(sym.name)
        return if sym.is_a?(MacroSym) || sym.is_a?(AutoGensym)

        target_name = sym.dotted? ? sym.segments.first : sym.name
        return if target_name.nil? || target_name.empty?

        target = scope.lookup(target_name)
        return if target.nil? && Compiler::Language.special_form?(sym.name)

        add_reference(sym, scope, target)
      end

      def hashfn_synthetic?(name)
        name == '$' || name == '$...' || name.match?(/\A\$\d\z/)
      end

      def bind_pattern(pattern, scope, kind)
        case pattern
        when Sym
          return if pattern.name == '_'

          add_binding(pattern, scope, kind)
        when Vec
          bind_vec_pattern(pattern, scope, kind)
        when HashLit
          bind_hash_pattern(pattern, scope, kind)
        end
      end

      def each_pattern_item(items)
        i = 0
        while i < items.length
          if items[i].is_a?(Sym) && items[i].name == '&'
            yield :rest, items[i + 1]
            i += 2
          else
            yield :item, items[i]
            i += 1
          end
        end
      end

      def bind_param_vec(vec, scope)
        each_pattern_item(vec.items) do |kind, item|
          if kind == :rest
            bind_pattern(item, scope, :fn_param) if item.is_a?(Sym) && item.name != '_'
          elsif !(item.is_a?(Sym) && ['...', '_'].include?(item.name))
            bind_pattern(item, scope, :fn_param)
          end
        end
      end

      def bind_vec_pattern(vec, scope, kind)
        each_pattern_item(vec.items) do |item_kind, item|
          bind_pattern(item, scope, kind) if item_kind == :item || item
        end
      end

      def bind_hash_pattern(hash, scope, kind)
        hash.pairs.each do |pair|
          bind_pattern(pair[1], scope, kind)
        end
      end

      def walk_pattern(pattern, scope, outer_scope, mode)
        case pattern
        when Sym then walk_pattern_symbol(pattern, scope, outer_scope, mode)
        when Vec then pattern.items.each { |item| walk_pattern_seq_item(item, scope, outer_scope, mode) }
        when HashLit then pattern.pairs.each { |pair| walk_pattern(pair[1], scope, outer_scope, mode) }
        when List then walk_pattern_list(pattern, scope, outer_scope, mode)
        end
      end

      def walk_pattern_symbol(sym, scope, outer_scope, mode)
        return if sym.name == '_'

        if mode == :match && (existing = outer_scope.lookup(sym.name))
          add_reference(sym, outer_scope, existing)
        else
          bind_pattern(sym, scope, :case_pattern)
        end
      end

      def walk_pattern_seq_item(item, scope, outer_scope, mode)
        return if item.is_a?(Sym) && item.name == '&'

        walk_pattern(item, scope, outer_scope, mode)
      end

      def walk_pattern_list(list, scope, outer_scope, mode)
        if (where = Compiler::Language.parse_where_pattern(list))
          walk_pattern(where.inner, scope, outer_scope, mode)
          where.guards.each { |guard| walk_form(guard, scope) }
        elsif (or_pattern = Compiler::Language.parse_or_pattern(list))
          or_pattern.alternatives.each { |alt| walk_pattern(alt, scope, outer_scope, mode) }
        elsif (pin = Compiler::Language.parse_pin_pattern(list))
          name_sym = pin.name
          if name_sym.is_a?(Sym) && (existing = outer_scope.lookup(name_sym.name))
            add_reference(name_sym, outer_scope, existing)
          end
        else
          list.items.each { |item| walk_pattern(item, scope, outer_scope, mode) }
        end
      end

      def add_binding(sym, scope, kind, lexical: true)
        return unless sym.is_a?(Sym)

        b = Binding.new(
          kind:,
          name: sym.name,
          line: sym.line,
          column: sym.column,
          end_column: sym.column + sym.name.length,
          scope:,
          segments: sym.dotted? ? sym.segments : nil,
          sym:,
          in_module_or_class: @in_module_or_class.positive?
        )
        @bindings << b
        scope.bindings[sym.name] = b if lexical
        b
      end

      def add_constant_binding(sym, scope, kind)
        b = Binding.new(
          kind:,
          name: sym.name,
          line: sym.line,
          column: sym.column,
          end_column: sym.column + sym.name.length,
          scope:,
          segments: sym.segments,
          sym:,
          in_module_or_class: @in_module_or_class.positive?
        )
        @bindings << b
        # Constants stay out of scope.bindings: they resolve workspace-wide, not lexically.
        b
      end

      def add_reference(sym, scope, target)
        @references << Reference.new(
          name: sym.name,
          line: sym.line,
          column: sym.column,
          end_column: sym.column + sym.name.length,
          scope:,
          sym:,
          target:
        )
      end
    end
  end
end
