# frozen_string_literal: true

module Kapusta
  module Compiler
    module Language
      FunctionForm = Struct.new(:head, :name, :params, :body, :prefix_length, keyword_init: true) do
        def named? = !name.nil?

        def anonymous? = name.nil?
      end
      ModuleForm = Struct.new(:name, :body, :prefix_length, keyword_init: true)
      ClassForm = Struct.new(:name, :supers, :body, :prefix_length, keyword_init: true)
      TryForm = Struct.new(:body, :clauses, keyword_init: true)
      CatchClause = Struct.new(:klass, :bind_sym, :body, keyword_init: true)
      FinallyClause = Struct.new(:body, keyword_init: true)
      BindingForm = Struct.new(:head, :target, :value, keyword_init: true) do
        def mutable? = head == 'var'
      end
      GlobalForm = Struct.new(:name, :value, keyword_init: true)
      SetForm = Struct.new(:target, :value, keyword_init: true)
      DotTarget = Struct.new(:object, :keys, keyword_init: true)
      TsetForm = Struct.new(:table, :key, :value, keyword_init: true)
      ConditionalBodyForm = Struct.new(:condition, :body, keyword_init: true) do
        def body? = !body.empty?
      end
      ValuesForm = Struct.new(:key, :value, keyword_init: true)
      LuaIteratorForm = Struct.new(:head, :collection, keyword_init: true) do
        def name = head.name
      end
      LuaPcallForm = Struct.new(:callable, :args, keyword_init: true)
      LuaXpcallForm = Struct.new(:callable, :handler, :args, keyword_init: true)
      SigilForm = Struct.new(:head, :name, keyword_init: true) do
        def kind = head.to_sym
      end
      MacroDefinitionForm = Struct.new(:name, :params, :body, keyword_init: true)
      ImportMacrosForm = Struct.new(:destructure, :module_arg, keyword_init: true)
      LetForm = Struct.new(:bindings, :body, keyword_init: true) do
        def binding_pairs
          return [] unless bindings.is_a?(Vec)

          bindings.items.each_slice(2).map { |pattern, value| [pattern, value] }
        end
      end
      CaseForm = Struct.new(:subject, :clauses, keyword_init: true) do
        def arm_pairs
          clauses.each_slice(2).to_a
        end

        def complete_arms
          arm_pairs.select { |pair| pair.length == 2 }
        end
      end
      WherePattern = Struct.new(:inner, :guards, keyword_init: true)
      OrPattern = Struct.new(:alternatives, keyword_init: true)
      PinPattern = Struct.new(:name, keyword_init: true)
      UnpackCall = Struct.new(:value, keyword_init: true)
      HashFnForm = Struct.new(:body, keyword_init: true)
      IterationForm = Struct.new(:bindings, :body, keyword_init: true) do
        def items = bindings.is_a?(Vec) ? bindings.items : []

        def iter_expr = items.last

        def binding_pats = items[0...-1] || []
      end
      AccumulateForm = Struct.new(:bindings, :body, keyword_init: true) do
        def items = bindings.is_a?(Vec) ? bindings.items : []

        def acc_name = items[0]

        def initial = items[1]

        def iter_items = items[2..] || []

        def iter_expr = iter_items.last

        def binding_pats = iter_items[0...-1] || []
      end
      FaccumulateForm = Struct.new(:bindings, :body, keyword_init: true) do
        def items = bindings.is_a?(Vec) ? bindings.items : []

        def acc_name = items[0]

        def initial = items[1]

        def counter = items[2]

        def start = items[3]

        def finish = items[4]

        def step = items[5]
      end
      CountedForForm = Struct.new(:bindings, :body, keyword_init: true) do
        def items = bindings.is_a?(Vec) ? bindings.items : []

        def counter = items[0]

        def start = items[1]

        def finish = items[2]

        def extras = items[3..] || []

        def each_extra
          i = 0
          while i < extras.length
            item = extras[i]
            if item.is_a?(Sym) && item.name == '&until'
              yield :until, extras[i + 1]
              i += 2
            else
              yield :step, item
              i += 1
            end
          end
        end
      end

      FUNCTION_HEADS = %w[fn lambda λ].freeze
      FUNCTION_DEFINITION_HEADS = (FUNCTION_HEADS + %w[defn]).freeze
      MACRO_FUNCTION_HEADS = (FUNCTION_HEADS + %w[macro]).freeze
      BINDING_HEADS = %w[local var].freeze
      HEADER_HEADS = %w[class module].freeze
      HEADER_SCOPES = %i[module class].freeze
      DEFINITION_SCOPES = ([:toplevel] + HEADER_SCOPES).freeze
      THREAD_HEADS = %w[-> ->> -?> -?>>].freeze
      PIPELINE_HEADS = (THREAD_HEADS + %w[doto]).freeze
      SHORT_PIPELINE_HEADS = %w[-?> -?>>].freeze
      THREAD_FIRST_HEADS = %w[-> -?>].freeze
      SEQUENCE_STATEMENT_HEADS = %w[let while for each case match].freeze
      MULTILINE_BODY_HEADS = %w[
        if case match let try catch finally do for -> ->> -?> -?>> doto
        fn lambda λ macro
      ].freeze
      FLAT_BODY_HEADS = %w[
        fn lambda λ macro when unless for each icollect collect fcollect
        accumulate faccumulate
      ].freeze
      NEVER_FLAT_HEADS = %w[let case match try catch finally do -> ->> -?> -?>> doto].freeze
      QUASI_HEADS = %w[
        quasi-sym quasi-list quasi-list-tail quasi-vec quasi-vec-tail
        quasi-hash quasi-gensym
      ].freeze
      CORE_SPECIAL_FORMS = %w[
        fn defn lambda λ let local var global set if when unless case match
        while for each do values
        -> ->> -?> -?>> doto
        icollect collect fcollect accumulate faccumulate
        hashfn
        . ?: :
        ..
        length
        require
        module class end
        try catch finally
        raise
        ivar cvar gvar
        ruby
        tset
        and or not
        = not= < <= > >=
        + - * / %
        print
        macro macros import-macros
        quasi-sym quasi-list quasi-list-tail quasi-vec quasi-vec-tail quasi-hash quasi-gensym
      ].freeze
      SPECIAL_FORMS = (CORE_SPECIAL_FORMS + LuaCompat::SPECIAL_FORMS).freeze

      module_function

      def list_head(form)
        return unless form.is_a?(List) && !form.empty?

        form.head
      end

      def list_head_name(form)
        head = list_head(form)
        head.name if head.is_a?(Sym)
      end

      def list_head?(form, *names)
        name = list_head_name(form)
        !name.nil? && names.flatten.include?(name)
      end

      def end_form?(form) = list_head?(form, 'end')

      def do_form?(form) = list_head?(form, 'do')

      def defn_form?(form) = list_head?(form, 'defn')

      def header_form?(form)
        name = list_head_name(form)
        !name.nil? && header_head?(name)
      end

      def sequence_statement_form?(form)
        name = list_head_name(form)
        !name.nil? && sequence_statement_head?(name)
      end

      def binding_form?(form)
        name = list_head_name(form)
        !name.nil? && binding_head?(name)
      end

      def special_form?(name) = SPECIAL_FORMS.include?(name)

      def function_head?(name) = FUNCTION_HEADS.include?(name)

      def function_definition_head?(name) = FUNCTION_DEFINITION_HEADS.include?(name)

      def macro_function_head?(name) = MACRO_FUNCTION_HEADS.include?(name)

      def binding_head?(name) = BINDING_HEADS.include?(name)

      def header_head?(name) = HEADER_HEADS.include?(name)

      def header_scope?(scope) = HEADER_SCOPES.include?(scope)

      def definition_scope?(scope) = DEFINITION_SCOPES.include?(scope)

      def pipeline_head?(name) = PIPELINE_HEADS.include?(name)

      def short_pipeline_head?(name) = SHORT_PIPELINE_HEADS.include?(name)

      def thread_first_head?(name) = THREAD_FIRST_HEADS.include?(name)

      def sequence_statement_head?(name) = SEQUENCE_STATEMENT_HEADS.include?(name)

      def multiline_body_head?(name) = MULTILINE_BODY_HEADS.include?(name)

      def flat_body_head?(name) = FLAT_BODY_HEADS.include?(name)

      def never_flat_head?(name) = NEVER_FLAT_HEADS.include?(name)

      def quasi_head?(name) = QUASI_HEADS.include?(name)

      def bodyless_header?(form)
        return false unless header_form?(form)

        case form.head.name
        when 'module'
          parsed = parse_module_form(form)
          parsed.body.empty? || (parsed.body.length == 1 && bodyless_header?(parsed.body[0]))
        when 'class'
          parse_class_form(form).body.empty?
        else
          false
        end
      end

      def function_form?(form, heads: FUNCTION_HEADS)
        !parse_function_form(form, heads:).nil?
      end

      def parse_function_form(form, heads: FUNCTION_HEADS)
        return unless list_head?(form, heads)

        parse_function_args(form.rest, head: form.head)
      end

      def parse_function_args(args, head: nil)
        if args[0].is_a?(Vec)
          FunctionForm.new(head:, name: nil, params: args[0], body: args[1..] || [], prefix_length: 1)
        elsif args[0].is_a?(Sym) && args[1].is_a?(Vec)
          FunctionForm.new(head:, name: args[0], params: args[1], body: args[2..] || [], prefix_length: 2)
        end
      end

      def parse_class_form(form)
        return unless list_head?(form, 'class')

        parse_class_args(form.rest)
      end

      def parse_module_form(form)
        return unless list_head?(form, 'module')

        parse_module_args(form.rest)
      end

      def parse_module_args(args)
        ModuleForm.new(name: args[0], body: args[1..] || [], prefix_length: 1)
      end

      def parse_class_args(args)
        if args[1].is_a?(Vec)
          ClassForm.new(name: args[0], supers: args[1], body: args[2..] || [], prefix_length: 2)
        else
          ClassForm.new(name: args[0], supers: nil, body: args[1..] || [], prefix_length: 1)
        end
      end

      def parse_try_args(args)
        TryForm.new(body: args[0], clauses: (args[1..] || []).filter_map { |clause| parse_try_clause(clause) })
      end

      def parse_try_clause(clause)
        return unless list_head_name(clause)

        case clause.head.name
        when 'catch' then parse_catch_clause(clause.rest)
        when 'finally' then FinallyClause.new(body: clause.rest)
        end
      end

      def parse_catch_clause(args)
        if exception_class_form?(args[0])
          CatchClause.new(klass: args[0], bind_sym: args[1], body: args[2..] || [])
        else
          CatchClause.new(klass: nil, bind_sym: args[0], body: args[1..] || [])
        end
      end

      def exception_class_form?(form)
        form.is_a?(Sym) && (form.name.match?(/\A[A-Z]/) || form.dotted?)
      end

      def parse_binding_form(form)
        return unless binding_form?(form)

        parse_binding_args(form.head.name, form.rest)
      end

      def parse_binding_args(head, args)
        return unless args.length == 2

        BindingForm.new(head:, target: args[0], value: args[1])
      end

      def parse_global_args(args)
        return unless args.length == 2

        GlobalForm.new(name: args[0], value: args[1])
      end

      def parse_global_form(form)
        return unless list_head?(form, 'global')

        parse_global_args(form.rest)
      end

      def parse_set_form(form)
        return unless list_head?(form, 'set')

        parse_set_args(form.rest)
      end

      def parse_set_args(args)
        SetForm.new(target: args[0], value: args[1])
      end

      def parse_dot_target(form)
        return unless list_head?(form, ':')

        DotTarget.new(object: form.items[1], keys: form.items[2..] || [])
      end

      def parse_tset_args(args)
        return unless args.length >= 3

        TsetForm.new(table: args[0], key: args[1], value: args[2])
      end

      def parse_conditional_body_args(args)
        ConditionalBodyForm.new(condition: args[0], body: args[1..] || [])
      end

      def parse_values_form(form)
        return unless list_head?(form, 'values') && form.items.length == 3

        ValuesForm.new(key: form.items[1], value: form.items[2])
      end

      def parse_lua_iterator_form(form)
        head = list_head(form)
        return unless head.is_a?(Sym) && LuaCompat.iterator_form?(head.name)

        LuaIteratorForm.new(head:, collection: form.items[1])
      end

      def parse_lua_pcall_args(args)
        LuaPcallForm.new(callable: args[0], args: args[1..] || [])
      end

      def parse_lua_xpcall_args(args)
        LuaXpcallForm.new(callable: args[0], handler: args[1], args: args[2..] || [])
      end

      def parse_sigil_form(form)
        head = list_head_name(form)
        return unless head

        parse_sigil_args(head, form.rest)
      end

      def parse_sigil_args(head, args)
        return unless %w[ivar cvar gvar].include?(head)

        SigilForm.new(head:, name: args[0])
      end

      def parse_hashfn_form(form)
        return unless list_head?(form, 'hashfn')

        HashFnForm.new(body: form.rest)
      end

      def parse_macro_definition_args(args)
        MacroDefinitionForm.new(name: args[0], params: args[1], body: args[2..] || [])
      end

      def parse_macro_definition_form(form)
        return unless list_head?(form, 'macro')

        parse_macro_definition_args(form.rest)
      end

      def parse_import_macros_args(args)
        ImportMacrosForm.new(destructure: args[0], module_arg: args[1])
      end

      def parse_import_macros_form(form)
        return unless list_head?(form, 'import-macros')

        parse_import_macros_args(form.rest)
      end

      def parse_let_args(args)
        LetForm.new(bindings: args[0], body: args[1..] || [])
      end

      def parse_let_form(form)
        return unless list_head?(form, 'let')

        parse_let_args(form.rest)
      end

      def parse_case_args(args)
        CaseForm.new(subject: args[0], clauses: args[1..] || [])
      end

      def parse_case_form(form)
        return unless list_head?(form, %w[case match])

        parse_case_args(form.rest)
      end

      def parse_try_form(form)
        return unless list_head?(form, 'try')

        parse_try_args(form.rest)
      end

      def parse_where_pattern(pattern)
        return unless list_head?(pattern, 'where')

        WherePattern.new(inner: pattern.items[1], guards: pattern.items[2..] || [])
      end

      def parse_or_pattern(pattern)
        return unless list_head?(pattern, 'or')

        OrPattern.new(alternatives: pattern.items[1..] || [])
      end

      def parse_pin_pattern(pattern)
        return unless list_head?(pattern, '=') && pattern.items.length == 2

        PinPattern.new(name: pattern.items[1])
      end

      def parse_unpack_call(form)
        return unless list_head?(form, 'unpack')

        UnpackCall.new(value: form.items[1])
      end

      def parse_iteration_args(args)
        IterationForm.new(bindings: args[0], body: args[1..] || [])
      end

      def parse_iteration_form(form)
        return unless list_head?(form, %w[each collect icollect])

        parse_iteration_args(form.rest)
      end

      def parse_accumulate_args(args)
        AccumulateForm.new(bindings: args[0], body: args[1..] || [])
      end

      def parse_accumulate_form(form)
        return unless list_head?(form, 'accumulate')

        parse_accumulate_args(form.rest)
      end

      def parse_faccumulate_args(args)
        FaccumulateForm.new(bindings: args[0], body: args[1..] || [])
      end

      def parse_faccumulate_form(form)
        return unless list_head?(form, 'faccumulate')

        parse_faccumulate_args(form.rest)
      end

      def parse_counted_for_args(args)
        CountedForForm.new(bindings: args[0], body: args[1..] || [])
      end

      def parse_counted_for_form(form)
        return unless list_head?(form, %w[for fcollect])

        parse_counted_for_args(form.rest)
      end
    end
  end
end
