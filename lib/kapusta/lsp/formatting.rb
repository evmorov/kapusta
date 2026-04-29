# frozen_string_literal: true

require_relative '../formatter'

module Kapusta
  class LSP
    module Formatting
      module_function

      def text_edits(text, path)
        formatted = Kapusta::Formatter.format(text, path:)
        return [] if formatted == text

        [{ range: full_range(text), newText: formatted }]
      rescue Kapusta::Error
        []
      end

      def full_range(text)
        lines = text.split("\n", -1)
        end_line = [lines.length - 1, 0].max
        end_character = lines.last ? lines.last.length : 0
        {
          start: { line: 0, character: 0 },
          end: { line: end_line, character: end_character }
        }
      end
    end
  end
end
