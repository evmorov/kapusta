# frozen_string_literal: true

module Kapusta
  module Compiler
    class Normalizer
      include LuaCompat::Normalization

      def normalize_all(forms)
        forms.map { |form| normalize(form) }
      end

      def normalize(form)
        case form
        when List then normalize_list(form)
        when Vec then inherit_position(Vec.new(form.items.map { |item| normalize(item) }), form)
        when HashLit
          inherit_position(
            HashLit.new(form.pairs.map { |key, value| [normalize_hash_key(key), normalize(value)] }),
            form
          )
        else
          form
        end
      end

      private

      def normalize_hash_key(key)
        case key
        when List, Vec, HashLit then normalize(key)
        else key
        end
      end

      def normalize_list(list)
        return list if list.empty?

        head = list.head
        items = list.items.map { |item| normalize(item) }
        return inherit_position(List.new(items), list) unless head.is_a?(Sym)

        case head.name
        when 'defn'
          name_sym = items[1]
          raise compiler_error(:fn_no_params, list) unless name_sym.is_a?(Sym)

          self_name = inherit_position(Sym.new("self.#{name_sym.name}"), name_sym)
          inherit_position(List.new([inherit_position(Sym.new('fn'), head), self_name, *items[2..]]), list)
        when 'when'
          raise compiler_error(:when_no_body, list, form: head.name) if items[2..].empty?

          cond = items[1]
          body = wrap_do(items[2..])
          inherit_position(List.new([Sym.new('if'), cond, body]), list)
        when 'unless'
          raise compiler_error(:when_no_body, list, form: head.name) if items[2..].empty?

          cond = items[1]
          body = wrap_do(items[2..])
          inherit_position(List.new([Sym.new('if'), List.new([Sym.new('not'), cond]), body]), list)
        when 'tset'
          raise compiler_error(:tset_no_value, list) if items.length < 4

          inherit_position(
            List.new([Sym.new('set'), List.new([Sym.new('.'), items[1], items[2]]), items[3]]),
            list
          )
        when *LuaCompat::SPECIAL_FORMS
          normalize_lua_compat_form(head.name, items)
        when '->', '->>', '-?>', '-?>>'
          inherit_position(normalize(thread(items[1..], head.name)), list)
        when 'doto'
          inherit_position(normalize(doto(items[1..])), list)
        else
          inherit_position(List.new(items), list)
        end
      end

      def inherit_position(target, source)
        return target unless target.respond_to?(:line=) && source.respond_to?(:line)

        target.line ||= source.line
        target.column ||= source.column
        target
      end

      def compiler_error(code, form, **args)
        line = form.respond_to?(:line) ? form.line : nil
        column = form.respond_to?(:column) ? form.column : nil
        Compiler::Error.new(Kapusta::Errors.format(code, **args), line:, column:)
      end

      def wrap_do(forms)
        return if forms.empty?
        return forms.first if forms.length == 1

        List.new([Sym.new('do'), *forms])
      end

      def thread(forms, kind)
        value = forms.first
        short = %w[-?> -?>>].include?(kind)
        position = %w[-> -?>].include?(kind) ? :first : :last

        return thread_short(forms, position) if short

        forms[1..].reduce(value) do |memo, form|
          thread_step(memo, form, position)
        end
      end

      def thread_short(forms, position)
        steps = forms[1..]
        return forms.first if steps.empty?

        prev_temp = thread_temp
        binding_items = [prev_temp, forms.first]
        body = nil
        last_index = steps.length - 1
        steps.each_with_index do |form, i|
          guarded = List.new([
                               Sym.new('if'),
                               List.new([Sym.new('='), prev_temp, nil]),
                               nil,
                               thread_step(prev_temp, form, position)
                             ])
          if i == last_index
            body = guarded
          else
            temp = thread_temp
            binding_items.push(temp, guarded)
            prev_temp = temp
          end
        end
        List.new([Sym.new('let'), Vec.new(binding_items), body])
      end

      def thread_step(memo, form, position)
        if form.is_a?(List)
          if position == :first
            List.new([form.items[0], memo, *form.items[1..]])
          else
            List.new([*form.items, memo])
          end
        else
          List.new([form, memo])
        end
      end

      def thread_temp
        gensym('thread')
      end

      def doto(forms)
        value = forms.first
        temp = gensym('doto')
        body = forms[1..].map do |form|
          if form.is_a?(List)
            List.new([form.items[0], temp, *form.items[1..]])
          else
            List.new([form, temp])
          end
        end
        List.new([Sym.new('let'), Vec.new([temp, value]), *body, temp])
      end

      def gensym(prefix)
        @gensym_index = (@gensym_index || 0) + 1
        GeneratedSym.new("#{prefix}_#{@gensym_index}", @gensym_index)
      end
    end
  end
end
