# frozen_string_literal: true

require_relative 'macro_lowerer'

module Kapusta
  module Compiler
    class MacroImporter
      EXTENSIONS = %w[kapm kap fnlm fnl].freeze

      def self.module_label(module_arg)
        module_arg.is_a?(Symbol) ? module_arg.to_s.tr('_', '-') : module_arg.to_s
      end

      def initialize(path: nil, loading: nil, error_class: Kapusta::Error)
        @path = path
        @loading = loading || []
        @error_class = error_class
      end

      def load(module_arg, import_form)
        module_label = self.class.module_label(module_arg)
        absolute_path = resolve_macro_module(module_arg) ||
                        raise(import_error(:import_macros_module_not_found, import_form, module: module_label))

        raise import_error(:import_macros_cycle, import_form, module: module_label) if @loading.include?(absolute_path)

        load_macro_module(absolute_path, module_label, import_form)
      end

      private

      def resolve_macro_module(module_arg)
        snake_stem = module_arg.to_s
        kebab_stem = snake_stem.tr('_', '-')
        [kebab_stem, snake_stem].uniq.each do |stem|
          EXTENSIONS.each do |ext|
            candidate = File.expand_path("#{stem}.#{ext}", base_dir)
            return candidate if File.file?(candidate)
          end
        end
        nil
      end

      def base_dir
        return Dir.pwd unless @path && !@path.start_with?('(')

        File.dirname(File.expand_path(@path))
      end

      def load_macro_module(absolute_path, module_label, import_form)
        @loading.push(absolute_path)
        begin
          source = File.read(absolute_path)
          forms = Reader.read_all(source)
        rescue Kapusta::Error => e
          raise e.with_defaults(path: absolute_path)
        end
        unless forms.last.is_a?(HashLit)
          raise import_error(:import_macros_module_no_exports, import_form, module: module_label)
        end

        processed = forms.map { |form| MacroLowerer.lower_module_form(form, error_class: @error_class) }
        wrapper = List.new([List.new([Sym.new('fn'), Vec.new([]), *processed])])
        ruby = Compiler.compile_forms([wrapper], path: absolute_path)
        result = TOPLEVEL_BINDING.eval(ruby, absolute_path, 1)

        return result if result.is_a?(Hash)

        raise import_error(:import_macros_module_no_exports, import_form, module: module_label)
      ensure
        @loading.pop
      end

      def import_error(code, form, **args)
        line = form.respond_to?(:line) ? form.line : nil
        column = form.respond_to?(:column) ? form.column : nil
        @error_class.new(Kapusta::Errors.format(code, **args), path: @path, line:, column:)
      end
    end
  end
end
