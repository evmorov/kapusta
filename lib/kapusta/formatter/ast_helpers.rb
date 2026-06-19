# frozen_string_literal: true

module Kapusta
  class Formatter
    module ASTHelpers
      private

      def comment?(form)
        form.is_a?(Comment)
      end

      def blank_line?(form)
        form.is_a?(BlankLine)
      end

      def non_semantic?(form)
        comment?(form) || blank_line?(form)
      end

      def contains_comments?(items)
        items.any? { |item| non_semantic?(item) }
      end

      def semantic_items(items)
        items.reject { |item| non_semantic?(item) }
      end

      def list_head(list)
        semantic_items(list.items).first
      end

      def head_name(list)
        head = list_head(list)
        head.name if head.is_a?(Sym)
      end

      def list_rest(list)
        semantic_items(list.items).drop(1)
      end

      def list_raw_rest(list)
        index = list.items.index { |item| !non_semantic?(item) }
        return list.items if index.nil?

        list.items[(index + 1)..] || []
      end

      def split_raw_items(items, semantic_count)
        split_index = 0
        seen = 0

        while split_index < items.length && seen < semantic_count
          seen += 1 unless non_semantic?(items[split_index])
          split_index += 1
        end

        [items.take(split_index), items.drop(split_index)]
      end

      def multiline_in_source?(form)
        form.respond_to?(:multiline_source) && form.multiline_source
      end

      def contains_collection?(form)
        case form
        when List then semantic_items(form.items).any? { |item| collection?(item) }
        when Vec then form.items.any? { |item| collection?(item) }
        when HashLit then form.pairs.any? { |k, v| collection?(k) || collection?(v) }
        else false
        end
      end

      def collection?(form)
        form.is_a?(List) || form.is_a?(Vec) || form.is_a?(HashLit)
      end
    end
  end
end
