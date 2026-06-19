# frozen_string_literal: true

module Kapusta
  class Formatter
    module LineHelpers
      private

      def fits?(text, indent)
        fits_within?(text, indent, MAX_WIDTH)
      end

      def inline_arg_fits?(text, indent)
        fits_within?(text, indent, MAX_WIDTH - 1)
      end

      def fits_within?(text, indent, width)
        !text.include?("\n") && indent + text.length <= width
      end

      def single_line?(text)
        !text.include?("\n")
      end

      def indent_block(text, amount)
        prefix = ' ' * amount
        text.lines.map { |line| line.strip.empty? ? blank_line_for(line) : "#{prefix}#{line}" }.join
      end

      def blank_line_for(line)
        line.end_with?("\n") ? "\n" : ''
      end

      def append_suffix(lines, suffix)
        updated = lines.dup
        if updated[-1].lstrip.start_with?(';')
          updated << suffix
        else
          updated[-1] = "#{updated[-1]}#{suffix}"
        end
        updated.join("\n")
      end
    end
  end
end
