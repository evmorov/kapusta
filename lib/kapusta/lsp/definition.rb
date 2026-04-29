# frozen_string_literal: true

require_relative 'rename'

module Kapusta
  class LSP
    module Definition
      module_function

      def find(uri, text, line_zero, character, workspace_index:)
        target = Rename.locate(text, line_zero, character)
        return unless target

        case target.kind
        when :local, :toplevel_fn, :constant
          location_for_binding(uri, target.binding) if target.binding
        when :macro
          locations_for_macro(uri, target.binding, workspace_index)
        when :free_toplevel
          locations_for_toplevel(target.name, workspace_index)
        when :free_constant
          locations_for_constant(target.segment_prefix, workspace_index)
        end
      end

      def locations_for_macro(uri, binding, workspace_index)
        return unless binding

        case binding.kind
        when :macro
          location_for_binding(uri, binding)
        when :macro_import
          def_uri, def_binding = workspace_index.find_macro_definition(
            uri, binding.import_module, binding.import_key
          )
          location_for_binding(def_uri, def_binding) if def_uri && def_binding
        end
      end

      def location_for_binding(uri, binding)
        { uri:, range: binding_range(binding) }
      end

      def locations_for_toplevel(name, workspace_index)
        defs = workspace_index.toplevel_fn_definitions(name)
        return if defs.empty?

        defs.map { |uri, b| { uri:, range: binding_range(b) } }
      end

      def locations_for_constant(prefix, workspace_index)
        defs = workspace_index.constant_definitions_with_prefix(prefix)
        return if defs.empty?

        defs.map { |uri, b| { uri:, range: binding_range(b) } }
      end

      def binding_range(binding)
        line = binding.line - 1
        {
          start: { line:, character: binding.column - 1 },
          end: { line:, character: binding.end_column - 1 }
        }
      end
    end
  end
end
