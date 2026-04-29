# frozen_string_literal: true

require_relative '../compiler'

module Kapusta
  class LSP
    module Identifier
      DELIM_CHARS = '()[]{}";`,'

      module_function

      def valid_local?(name)
        return false if name.nil? || name.empty?
        return false if name.match?(/\s/)
        return false if name.match?(/[#{Regexp.escape(DELIM_CHARS)}]/o)
        return false if name.match?(/\A-?\d/)
        return false if name.include?('.')
        return false if Kapusta::Compiler::SPECIAL_FORMS.include?(name)

        true
      end

      def valid_constant_segment?(segment)
        !segment.nil? && segment.match?(/\A[A-Z]\w*\z/)
      end
    end
  end
end
