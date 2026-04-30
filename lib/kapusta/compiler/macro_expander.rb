# frozen_string_literal: true

require_relative 'macro_gensym'
require_relative 'macro_lowerer'
require_relative 'macro_importer'

module Kapusta
  module Compiler
    class MacroExpander
      class Error < Kapusta::Error; end

      class << self
        def fresh_gensym(prefix)
          MacroGensym.fresh_gensym(prefix)
        end

        def fresh_local_gensym(prefix)
          MacroGensym.fresh_local_gensym(prefix)
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
        when Vec then Kapusta.copy_position(Vec.new(form.items.map { |item| expand(item) }), form)
        when HashLit
          Kapusta.copy_position(
            HashLit.new(form.entries.map do |entry|
              entry.is_a?(Array) ? [expand(entry[0]), expand(entry[1])] : entry
            end),
            form
          )
        else
          form
        end
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
            return Kapusta.copy_position(expand(result), list)
          end
        end

        Kapusta.copy_position(List.new(list.items.map { |item| expand(item) }), list)
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

        module_label = MacroImporter.module_label(module_arg)
        exports = macro_importer.load(module_arg, form)
        if destructure.is_a?(HashLit)
          register_imported_macros(destructure, exports, module_label, form)
        else
          register_whole_module(destructure, exports)
        end
      end

      def macro_importer
        @macro_importer ||= MacroImporter.new(path: @path, loading: @loading, error_class: Error)
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
        macro_path = @path || "(macro #{name})"
        MacroLowerer.compile(params:, body:, path: macro_path, error_class: Error)
      end

      def invoke_macro(key, args)
        proc_obj = @macros[key]
        proc_obj.call(*args)
      end
    end
  end
end
