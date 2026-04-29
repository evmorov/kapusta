# frozen_string_literal: true

module Kapusta
  class LSP
    module Diagnostics
      SEVERITY_ERROR = 1

      module_function

      def collect(text, path)
        Kapusta.compile(text, path: path || '(buffer)')
        []
      rescue Kapusta::Error => e
        [diagnostic_from(e, text)]
      end

      def diagnostic_from(error, text)
        line = [(error.line || 1) - 1, 0].max
        column = [(error.column || 1) - 1, 0].max

        {
          range: {
            start: { line:, character: column },
            end: { line:, character: column + token_length(text, line, column) }
          },
          severity: SEVERITY_ERROR,
          source: 'kapusta-ls',
          message: error.reason
        }
      end

      def token_length(text, line, column)
        source_line = text.lines[line]
        return 1 unless source_line

        tail = source_line[column..] || ''
        match = tail.match(/\A[^\s()\[\]{}";`,]+/)
        match && match[0].length.positive? ? match[0].length : 1
      end
    end
  end
end
