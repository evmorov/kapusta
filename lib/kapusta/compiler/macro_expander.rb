# frozen_string_literal: true

module Kapusta
  module Compiler
    class MacroExpander
      class Error < Kapusta::Error; end

      @gensym_counter = 0

      class << self
        def fresh_gensym(prefix)
          @gensym_counter += 1
          GeneratedSym.new("#{prefix}_g#{@gensym_counter}", @gensym_counter)
        end

        def fresh_local_gensym(prefix)
          @gensym_counter += 1
          GeneratedSym.new("#{prefix}_local_#{@gensym_counter}", @gensym_counter)
        end
      end

      def initialize(path: nil, loading: nil)
        @macros = {}
        @path = path
        @loading = loading || []
      end

      def expand_all(forms)
        forms.flat_map { |form| expand_top(form) }
      end

      private

      def expand_top(form)
        if form.is_a?(List) && form.head.is_a?(Sym)
          case form.head.name
          when 'macro'
            register_macro_form(form.rest)
            return []
          when 'macros'
            register_macros_form(form.rest)
            return []
          when 'import-macros'
            handle_import_macros(form)
            return []
          end
        end
        [expand(form)]
      end

      def macro_error(code, form, **args)
        line = form.respond_to?(:line) ? form.line : nil
        column = form.respond_to?(:column) ? form.column : nil
        Error.new(Kapusta::Errors.format(code, **args), path: @path, line:, column:)
      end

      def expand(form)
        case form
        when List then expand_list(form)
        when Vec then copy_position(Vec.new(form.items.map { |item| expand(item) }), form)
        when HashLit
          copy_position(
            HashLit.new(form.entries.map do |entry|
              entry.is_a?(Array) ? [expand(entry[0]), expand(entry[1])] : entry
            end),
            form
          )
        else
          form
        end
      end

      def copy_position(target, source)
        return target unless target.respond_to?(:line=) && source.respond_to?(:line)

        target.line ||= source.line
        target.column ||= source.column
        target
      end

      def expand_list(list)
        return list if list.empty?

        head = list.head
        if head.is_a?(Sym) && !head.is_a?(AutoGensym)
          name = head.name
          case name
          when 'macro'
            register_macro_form(list.rest)
            return List.new([Sym.new('do')])
          when 'macros'
            register_macros_form(list.rest)
            return List.new([Sym.new('do')])
          when 'import-macros'
            handle_import_macros(list)
            return List.new([Sym.new('do')])
          end

          key = lookup_key(name)
          if @macros.key?(key)
            args = list.rest
            result = invoke_macro(key, args)
            return copy_position(expand(result), list)
          end
        end

        copy_position(List.new(list.items.map { |item| expand(item) }), list)
      end

      def lookup_key(name)
        Kapusta.kebab_to_snake(name).to_sym
      end

      def register_macro_form(args)
        name_sym, params, *body = args
        raise macro_error(:macro_name_must_be_symbol, name_sym) unless name_sym.is_a?(Sym)
        raise macro_error(:macro_params_must_be_vector, params) unless params.is_a?(Vec)

        register(name_sym.name, params, body)
      end

      def register_macros_form(args)
        hash_lit = args[0]
        raise macro_error(:macros_expects_hash, hash_lit) unless hash_lit.is_a?(HashLit)

        hash_lit.pairs.each do |key, value|
          raise macro_error(:macros_entry_must_be_fn, value, form: value.inspect) unless fn_form?(value)

          name = key.to_s
          params = value.items[1]
          body = value.items[2..]
          raise macro_error(:macros_entry_params_must_be_vector, params) unless params.is_a?(Vec)

          register(name, params, body)
        end
      end

      def fn_form?(value)
        value.is_a?(List) && value.head.is_a?(Sym) && %w[fn lambda λ].include?(value.head.name)
      end

      def handle_import_macros(form)
        args = form.rest
        destructure = args[0]
        module_arg = args[1]
        unless destructure.is_a?(HashLit) || destructure.is_a?(Sym)
          raise macro_error(:import_macros_destructure_invalid, form)
        end
        unless module_arg.is_a?(Symbol) || module_arg.is_a?(String)
          raise macro_error(:import_macros_module_invalid, form)
        end

        module_label = module_arg.is_a?(Symbol) ? module_arg.to_s.tr('_', '-') : module_arg.to_s
        absolute_path = resolve_macro_module(module_arg) ||
                        raise(macro_error(:import_macros_module_not_found, form, module: module_label))

        raise macro_error(:import_macros_cycle, form, module: module_label) if @loading.include?(absolute_path)

        exports = load_macro_module(absolute_path, module_label, form)
        if destructure.is_a?(HashLit)
          register_imported_macros(destructure, exports, module_label, form)
        else
          register_whole_module(destructure, exports)
        end
      end

      def resolve_macro_module(module_arg)
        snake_stem = module_arg.to_s
        kebab_stem = snake_stem.tr('_', '-')
        base = @path && !@path.start_with?('(') ? File.dirname(File.expand_path(@path)) : Dir.pwd
        [kebab_stem, snake_stem].uniq.each do |stem|
          %w[kapm kap fnlm fnl].each do |ext|
            candidate = File.expand_path("#{stem}.#{ext}", base)
            return candidate if File.file?(candidate)
          end
        end
        nil
      end

      def load_macro_module(absolute_path, module_label, form)
        @loading.push(absolute_path)
        begin
          source = File.read(absolute_path)
          forms = Reader.read_all(source)
        rescue Kapusta::Error => e
          raise e.with_defaults(path: absolute_path)
        end
        raise macro_error(:import_macros_module_no_exports, form, module: module_label) unless forms.last.is_a?(HashLit)

        processed = forms.map { |f| process_module_form(f) }
        wrapper = List.new([List.new([Sym.new('fn'), Vec.new([]), *processed])])
        ruby = Compiler.compile_forms([wrapper], path: absolute_path)
        result = TOPLEVEL_BINDING.eval(ruby, absolute_path, 1)

        raise macro_error(:import_macros_module_no_exports, form, module: module_label) unless result.is_a?(Hash)

        result
      ensure
        @loading.pop
      end

      def process_module_form(form)
        return lower_fn_form(form) if fn_form_with_body?(form)

        Lowering.new.lower(form)
      end

      def fn_form_with_body?(form)
        form.is_a?(List) && form.head.is_a?(Sym) && %w[fn lambda λ].include?(form.head.name)
      end

      def lower_fn_form(form)
        items = form.items
        if items[1].is_a?(Sym) && items[2].is_a?(Vec)
          name_sym = items[1]
          params = items[2]
          body = items[3..] || []
        elsif items[1].is_a?(Vec)
          name_sym = nil
          params = items[1]
          body = items[2..] || []
        else
          return form
        end

        lowering = Lowering.new
        lowered_body = body.map { |f| lowering.lower(f) }
        gensyms = lowering.collected_gensyms
        inner = wrap_gensyms(gensyms, lowered_body)
        head_items = name_sym ? [form.head, name_sym, params] : [form.head, params]
        List.new(head_items + inner)
      end

      def wrap_gensyms(gensyms, body)
        return body if gensyms.empty?

        bindings = gensyms.flat_map { |sym, prefix| [sym, List.new([Sym.new('quasi-gensym'), prefix])] }
        wrapped = body.length == 1 ? body[0] : List.new([Sym.new('do'), *body])
        [List.new([Sym.new('let'), Vec.new(bindings), wrapped])]
      end

      def register_imported_macros(destructure, exports, module_label, form)
        destructure.pairs.each do |key, target|
          raise macro_error(:import_macros_destructure_invalid, form) unless target.is_a?(Sym)

          proc_obj = exports[key] ||
                     raise(macro_error(:import_macros_macro_not_found, form,
                                       macro: key.to_s.tr('_', '-'), module: module_label))
          @macros[lookup_key(target.name)] = proc_obj
        end
      end

      def register_whole_module(bind_sym, exports)
        exports.each do |export_key, proc_obj|
          macro_name = "#{bind_sym.name}.#{export_key.to_s.tr('_', '-')}"
          @macros[lookup_key(macro_name)] = proc_obj
        end
      end

      def register(source_name, params, body)
        proc_obj = compile_macro(source_name, params, body)
        @macros[lookup_key(source_name)] = proc_obj
      end

      def compile_macro(name, params, body)
        lowering = Lowering.new
        lowered_body = body.map { |form| lowering.lower(form) }
        gensym_locals = lowering.collected_gensyms

        wrapped =
          if gensym_locals.empty?
            List.new([Sym.new('fn'), params, *lowered_body])
          else
            let_bindings = gensym_locals.flat_map do |gensym_sym, prefix|
              [gensym_sym, List.new([Sym.new('quasi-gensym'), prefix])]
            end
            inner = lowered_body.length == 1 ? lowered_body.first : List.new([Sym.new('do'), *lowered_body])
            List.new([Sym.new('fn'), params, List.new([Sym.new('let'), Vec.new(let_bindings), inner])])
          end

        macro_path = @path || "(macro #{name})"
        ruby = Compiler.compile_forms([wrapped], path: macro_path)
        TOPLEVEL_BINDING.eval(ruby, macro_path, 1)
      end

      def invoke_macro(key, args)
        proc_obj = @macros[key]
        proc_obj.call(*args)
      end

      class Lowering
        def initialize
          @gensyms = {}
        end

        def collected_gensyms
          @gensyms.map { |prefix, sym| [sym, prefix] }
        end

        def lower(form)
          case form
          when Quasiquote then copy_position(lower_quasi(form.form), form)
          when Unquote, UnquoteSplice
            raise Error, Kapusta::Errors.format(:unquote_outside_quasiquote)
          when AutoGensym
            raise Error, Kapusta::Errors.format(:auto_gensym_outside_quasiquote, name: form.name)
          when List then copy_position(List.new(form.items.map { |item| lower(item) }), form)
          when Vec then copy_position(Vec.new(form.items.map { |item| lower(item) }), form)
          when HashLit
            copy_position(
              HashLit.new(form.entries.map do |entry|
                entry.is_a?(Array) ? [lower(entry[0]), lower(entry[1])] : entry
              end),
              form
            )
          else
            form
          end
        end

        def copy_position(target, source)
          return target unless target.respond_to?(:line=) && source.respond_to?(:line)

          target.line ||= source.line
          target.column ||= source.column
          target
        end

        def lower_quasi(form)
          case form
          when AutoGensym then gensym_local_for(form.name)
          when Sym then List.new([Sym.new('quasi-sym'), form.name])
          when List then lower_quasi_list(form)
          when Vec then lower_quasi_vec(form)
          when HashLit then lower_quasi_hash(form)
          when Unquote then lower(form.form)
          when UnquoteSplice
            raise Error, Kapusta::Errors.format(:unquote_splice_outside_list)
          when Quasiquote
            raise Error, Kapusta::Errors.format(:nested_quasiquote)
          else
            form
          end
        end

        def lower_quasi_list(list)
          items = list.items
          return List.new([Sym.new('quasi-list')]) if items.empty?

          if (tail_expr = splice_tail(items))
            head_items = items[0...-1].map { |item| lower_quasi(item) }
            return List.new([Sym.new('quasi-list-tail'), Vec.new(head_items), tail_expr])
          end

          lowered_items = items.map { |item| lower_quasi_item(item) }
          List.new([Sym.new('quasi-list'), *lowered_items])
        end

        def lower_quasi_vec(vec)
          items = vec.items
          if (tail_expr = splice_tail(items))
            head_items = items[0...-1].map { |item| lower_quasi(item) }
            return List.new([Sym.new('quasi-vec-tail'), Vec.new(head_items), tail_expr])
          end

          lowered_items = items.map { |item| lower_quasi_item(item) }
          List.new([Sym.new('quasi-vec'), *lowered_items])
        end

        def lower_quasi_hash(hash)
          parts = []
          hash.entries.each do |entry|
            next unless entry.is_a?(Array)

            key, value = entry
            parts << lower_quasi(key) << lower_quasi(value)
          end
          List.new([Sym.new('quasi-hash'), *parts])
        end

        def lower_quasi_item(item)
          if item.is_a?(Unquote) && unpack_call?(item.form)
            inner = lower(item.form.items[1])
            List.new([Sym.new('.'), inner, 0])
          else
            lower_quasi(item)
          end
        end

        def splice_tail(items)
          last = items.last
          return unless last
          return lower(last.form) if last.is_a?(UnquoteSplice)
          return lower(last.form.items[1]) if last.is_a?(Unquote) && unpack_call?(last.form)

          nil
        end

        def unpack_call?(form)
          form.is_a?(List) && form.head.is_a?(Sym) && form.head.name == 'unpack'
        end

        def gensym_local_for(prefix)
          @gensyms[prefix] ||= MacroExpander.fresh_local_gensym(prefix)
        end
      end
    end
  end
end
