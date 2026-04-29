# frozen_string_literal: true

require_relative '../ast'
require_relative '../compiler'

module Kapusta
  class LSP
    class ScopeWalker
      Binding = Struct.new(:kind, :name, :line, :column, :end_column, :scope, :segments,
                           :sym, :in_module_or_class, keyword_init: true)
      Reference = Struct.new(:name, :line, :column, :end_column, :scope, :sym,
                             :target, keyword_init: true)
      Scope = Struct.new(:id, :parent, :bindings, :kind) do
        def lookup(name)
          bindings[name] || parent&.lookup(name)
        end
      end

      SKIPPED_HEADS = %w[macro macros import-macros ivar cvar gvar quasi-sym quasi-list
                         quasi-list-tail quasi-vec quasi-vec-tail quasi-hash quasi-gensym].freeze

      DISPATCHERS = {
        'let' => :walk_let,
        'local' => :walk_local_var,
        'var' => :walk_local_var,
        'global' => :walk_global,
        'set' => :walk_set,
        'fn' => :walk_fn,
        'lambda' => :walk_fn,
        'λ' => :walk_fn,
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
        'hashfn' => :walk_hashfn
      }.freeze

      attr_reader :bindings, :references, :root_scope

      def self.analyze(forms)
        walker = new
        walker.walk_top(forms)
        walker
      end

      def initialize
        @bindings = []
        @references = []
        @scope_seq = 0
        @root_scope = make_scope(nil, :file)
        @in_module_or_class = 0
      end

      def walk_top(forms)
        i = 0
        while i < forms.length
          form = forms[i]
          if bodyless_header?(form)
            walk_bodyless_header(form, forms[(i + 1)..] || [], @root_scope)
            break
          end

          walk_form(form, @root_scope)
          i += 1
        end
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

      def bodyless_header?(form)
        return false unless form.is_a?(List) && !form.empty? && form.head.is_a?(Sym)

        case form.head.name
        when 'module'
          body = form.items[2..] || []
          body.empty? || (body.length == 1 && bodyless_header?(body[0]))
        when 'class'
          _name_sym, _supers, body = split_class_args(form.items[1..] || [])
          body.empty?
        else
          false
        end
      end

      def walk_bodyless_header(form, remaining_forms, scope)
        case form.head.name
        when 'module'
          name_sym = form.items[1]
          add_constant_binding(name_sym, scope, :module) if name_sym.is_a?(Sym)
          body = form.items[2..] || []
          inside_module_or_class do
            if body.length == 1 && bodyless_header?(body[0])
              walk_bodyless_header(body[0], remaining_forms, scope)
            else
              remaining_forms.each { |item| walk_form(item, scope) }
            end
          end
        when 'class'
          name_sym, supers, = split_class_args(form.items[1..] || [])
          supers&.items&.each { |item| walk_form(item, scope) }
          add_constant_binding(name_sym, scope, :class) if name_sym.is_a?(Sym)
          inside_module_or_class do
            remaining_forms.each { |item| walk_form(item, scope) }
          end
        end
      end

      def split_class_args(args)
        name_sym = args[0]
        if args[1].is_a?(Vec)
          [name_sym, args[1], args[2..] || []]
        else
          [name_sym, nil, args[1..] || []]
        end
      end

      def inside_module_or_class
        @in_module_or_class += 1
        yield
      ensure
        @in_module_or_class -= 1
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

        return if SKIPPED_HEADS.include?(head.name)

        dispatcher = DISPATCHERS[head.name]
        return send(dispatcher, list, scope) if dispatcher

        list.items.each { |item| walk_form(item, scope) }
      end

      def walk_let(list, scope)
        bindings_vec = list.items[1]
        body = list.items[2..]
        return unless bindings_vec.is_a?(Vec)

        let_scope = make_scope(scope, :let)
        items = bindings_vec.items
        i = 0
        while i < items.length
          name_pat = items[i]
          value = items[i + 1]
          walk_form(value, let_scope) if value
          bind_pattern(name_pat, let_scope, :let)
          i += 2
        end
        body&.each { |form| walk_form(form, let_scope) }
      end

      def walk_local_var(list, scope)
        kind = list.head.name == 'var' ? :var : :local
        target = list.items[1]
        value = list.items[2]
        walk_form(value, scope) if value
        bind_pattern(target, scope, kind)
      end

      def walk_global(list, _scope)
        # Globals are not renamable; skip the binder name and walk only the value.
        value = list.items[2]
        walk_form(value, @root_scope) if value
      end

      def walk_hashfn(list, scope)
        list.items[1..]&.each { |form| walk_form(form, scope) }
      end

      def walk_set(list, scope)
        target = list.items[1]
        value = list.items[2]
        walk_form(value, scope) if value
        return unless target.is_a?(Sym) && !target.dotted?

        existing = scope.lookup(target.name)
        if existing
          add_reference(target, scope, existing)
        else
          add_binding(target, scope, :set)
        end
      end

      def walk_fn(list, scope)
        items = list.items
        if items[1].is_a?(Vec)
          params = items[1]
          body = items[2..]
          fn_scope = make_scope(scope, :fn)
          bind_param_vec(params, fn_scope)
          body.each { |form| walk_form(form, fn_scope) }
        elsif items[1].is_a?(Sym) && items[2].is_a?(Vec)
          name_sym = items[1]
          params = items[2]
          body = items[3..]
          kind = if method_definition_context?
                   :method
                 else
                   (scope == @root_scope ? :toplevel_fn : :fn_local)
                 end
          fn_scope = make_scope(scope, :fn)
          binding = add_binding(name_sym, scope, kind, lexical: kind != :method)
          fn_scope.bindings[name_sym.name] = binding unless kind == :method
          bind_param_vec(params, fn_scope)
          body.each { |form| walk_form(form, fn_scope) }
        else
          items[1..]&.each { |item| walk_form(item, scope) }
        end
      end

      def method_definition_context?
        @in_module_or_class.positive?
      end

      def walk_for(list, scope)
        bindings_vec = list.items[1]
        body = list.items[2..]
        return unless bindings_vec.is_a?(Vec)

        for_scope = make_scope(scope, :for)
        counter = bindings_vec.items[0]
        bindings_vec.items[1..]&.each { |form| walk_form(form, scope) }
        bind_pattern(counter, for_scope, :for_counter) if counter
        body&.each { |form| walk_form(form, for_scope) }
      end

      def walk_for_like(list, scope) = walk_for(list, scope)

      def walk_each_like(list, scope)
        bindings_vec = list.items[1]
        body = list.items[2..]
        return unless bindings_vec.is_a?(Vec)

        items = bindings_vec.items
        return if items.empty?

        each_scope = make_scope(scope, :each)
        iter_expr = items.last
        binders = items[0..-2]
        walk_form(iter_expr, scope)
        binders.each { |b| bind_pattern(b, each_scope, :each_var) }
        body&.each { |form| walk_form(form, each_scope) }
      end

      def walk_accumulate(list, scope)
        bindings_vec = list.items[1]
        body = list.items[2..]
        return unless bindings_vec.is_a?(Vec)

        items = bindings_vec.items
        return if items.length < 4

        acc_scope = make_scope(scope, :accumulate)
        acc_name = items[0]
        acc_init = items[1]
        iter_var = items[2]
        iter_expr = items[3]
        walk_form(acc_init, scope)
        bind_pattern(acc_name, acc_scope, :accumulator)
        walk_form(iter_expr, scope)
        bind_pattern(iter_var, acc_scope, :each_var)
        body&.each { |form| walk_form(form, acc_scope) }
      end

      def walk_faccumulate(list, scope)
        bindings_vec = list.items[1]
        body = list.items[2..]
        return unless bindings_vec.is_a?(Vec)

        items = bindings_vec.items
        return if items.length < 5

        acc_scope = make_scope(scope, :faccumulate)
        acc_name = items[0]
        acc_init = items[1]
        counter = items[2]
        walk_form(acc_init, scope)
        items[3..]&.each { |form| walk_form(form, scope) }
        bind_pattern(acc_name, acc_scope, :accumulator)
        bind_pattern(counter, acc_scope, :for_counter)
        body&.each { |form| walk_form(form, acc_scope) }
      end

      def walk_case_match(list, scope)
        mode = list.head.name == 'match' ? :match : :case
        subject = list.items[1]
        arms = list.items[2..] || []
        walk_form(subject, scope)
        arms.each_slice(2) do |pattern, body|
          arm_scope = make_scope(scope, :case_arm)
          walk_pattern(pattern, arm_scope, scope, mode)
          walk_form(body, arm_scope) if body
        end
      end

      def walk_try(list, scope)
        body = list.items[1]
        clauses = list.items[2..] || []
        walk_form(body, scope)
        clauses.each do |clause|
          next unless clause.is_a?(List)

          head = clause.head
          next unless head.is_a?(Sym)

          if head.name == 'catch'
            walk_catch(clause, scope)
          elsif head.name == 'finally'
            clause.items[1..]&.each { |form| walk_form(form, scope) }
          end
        end
      end

      def walk_catch(clause, scope)
        rest = clause.items[1..]
        if rest[0].is_a?(Sym) && (rest[0].name.match?(/\A[A-Z]/) || rest[0].dotted?)
          klass = rest[0]
          bind_sym = rest[1]
          body = rest[2..]
          walk_form(klass, scope)
        else
          bind_sym = rest[0]
          body = rest[1..]
        end
        catch_scope = make_scope(scope, :catch)
        bind_pattern(bind_sym, catch_scope, :catch) if bind_sym.is_a?(Sym)
        body&.each { |form| walk_form(form, catch_scope) }
      end

      def walk_module_class(list, scope)
        kind = list.head.name == 'module' ? :module : :class
        name_sym = list.items[1]
        body_start = 2
        if kind == :class && list.items[2].is_a?(Vec)
          list.items[2].items.each { |item| walk_form(item, scope) }
          body_start = 3
        end

        add_constant_binding(name_sym, scope, kind) if name_sym.is_a?(Sym)

        inside_module_or_class do
          list.items[body_start..]&.each { |form| walk_form(form, scope) }
        end
      end

      def walk_reference(sym, scope)
        return if hashfn_synthetic?(sym.name)
        return if sym.is_a?(MacroSym) || sym.is_a?(AutoGensym)
        return if Compiler::SPECIAL_FORMS.include?(sym.name)

        target_name = sym.dotted? ? sym.segments.first : sym.name
        return if target_name.nil? || target_name.empty?

        target = scope.lookup(target_name)
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

      def bind_param_vec(vec, scope)
        items = vec.items
        i = 0
        while i < items.length
          item = items[i]
          if item.is_a?(Sym) && item.name == '&'
            rest = items[i + 1]
            bind_pattern(rest, scope, :fn_param) if rest.is_a?(Sym) && rest.name != '_'
            i += 2
          elsif item.is_a?(Sym) && ['...', '_'].include?(item.name)
            i += 1
          else
            bind_pattern(item, scope, :fn_param)
            i += 1
          end
        end
      end

      def bind_vec_pattern(vec, scope, kind)
        items = vec.items
        i = 0
        while i < items.length
          item = items[i]
          if item.is_a?(Sym) && item.name == '&'
            rest = items[i + 1]
            bind_pattern(rest, scope, kind) if rest
            i += 2
          else
            bind_pattern(item, scope, kind)
            i += 1
          end
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
        head = list.head
        if head.is_a?(Sym) && head.name == 'where'
          inner = list.items[1]
          guards = list.items[2..]
          walk_pattern(inner, scope, outer_scope, mode)
          guards&.each { |g| walk_form(g, scope) }
        elsif head.is_a?(Sym) && head.name == 'or'
          list.items[1..]&.each { |alt| walk_pattern(alt, scope, outer_scope, mode) }
        elsif head.is_a?(Sym) && head.name == '=' && list.items.length == 2
          name_sym = list.items[1]
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
