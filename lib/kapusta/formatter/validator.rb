# frozen_string_literal: true

module Kapusta
  class Formatter
    module Validator
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
    end
  end
end
