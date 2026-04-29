# frozen_string_literal: true

require_relative 'macro_gensym'

module Kapusta
  module Compiler
    class MacroLowerer
      FN_HEADS = %w[fn lambda λ].freeze

      def self.compile(params:, body:, path:, error_class:)
        callable = new(error_class:).callable_form(params, body)
        ruby = Compiler.compile_forms([callable], path:)
        TOPLEVEL_BINDING.eval(ruby, path, 1)
      end

      def self.lower_module_form(form, error_class:)
        new(error_class:).lower_module_form(form)
      end

      def initialize(error_class:)
        @error_class = error_class
        @gensyms = {}
      end

      def callable_form(params, body)
        List.new([Sym.new('fn'), params, *lowered_body_with_gensyms(body)])
      end

      def lower_module_form(form)
        return lower_fn_form(form) if fn_form?(form)

        lower(form)
      end

      def lower(form)
        case form
        when Quasiquote then copy_position(lower_quasi(form.form), form)
        when Unquote, UnquoteSplice
          raise @error_class, Kapusta::Errors.format(:unquote_outside_quasiquote)
        when AutoGensym
          raise @error_class, Kapusta::Errors.format(:auto_gensym_outside_quasiquote, name: form.name)
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

      private

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

        head_items = name_sym ? [form.head, name_sym, params] : [form.head, params]
        List.new(head_items + lowered_body_with_gensyms(body))
      end

      def lowered_body_with_gensyms(body)
        lowered_body = body.map { |item| lower(item) }
        wrap_gensyms(collected_gensyms, lowered_body)
      end

      def collected_gensyms
        @gensyms.map { |prefix, sym| [sym, prefix] }
      end

      def wrap_gensyms(gensyms, body)
        return body if gensyms.empty?

        bindings = gensyms.flat_map { |sym, prefix| [sym, List.new([Sym.new('quasi-gensym'), prefix])] }
        wrapped = body.length == 1 ? body[0] : List.new([Sym.new('do'), *body])
        [List.new([Sym.new('let'), Vec.new(bindings), wrapped])]
      end

      def fn_form?(form)
        form.is_a?(List) && form.head.is_a?(Sym) && FN_HEADS.include?(form.head.name)
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
          raise @error_class, Kapusta::Errors.format(:unquote_splice_outside_list)
        when Quasiquote
          raise @error_class, Kapusta::Errors.format(:nested_quasiquote)
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
        @gensyms[prefix] ||= MacroGensym.fresh_local_gensym(prefix)
      end
    end
  end
end
