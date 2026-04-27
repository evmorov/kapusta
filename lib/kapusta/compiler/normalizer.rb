# frozen_string_literal: true

module Kapusta
  module Compiler
    class Normalizer
      def normalize_all(forms)
        forms.map { |form| normalize(form) }
      end

      def normalize(form)
        case form
        when List then normalize_list(form)
        when Vec then Vec.new(form.items.map { |item| normalize(item) })
        when HashLit
          HashLit.new(form.pairs.map { |key, value| [normalize_hash_key(key), normalize(value)] })
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
        return List.new(items) unless head.is_a?(Sym)

        case head.name
        when 'when'
          raise Compiler::Error, "#{head.name}: expected body" if items[2..].empty?

          cond = items[1]
          body = wrap_do(items[2..])
          List.new([Sym.new('if'), cond, body])
        when 'unless'
          raise Compiler::Error, "#{head.name}: expected body" if items[2..].empty?

          cond = items[1]
          body = wrap_do(items[2..])
          List.new([Sym.new('if'), List.new([Sym.new('not'), cond]), body])
        when 'tset'
          raise Compiler::Error, 'tset: expected table, key, and value arguments' if items.length < 4

          List.new([Sym.new('set'), List.new([Sym.new('.'), items[1], items[2]]), items[3]])
        when 'pcall'
          fn = items[1]
          args = items[2..]
          List.new([
                     Sym.new('try'),
                     List.new([Sym.new('values'), true, List.new([fn, *args])]),
                     List.new([Sym.new('catch'), Sym.new('StandardError'), Sym.new('e'),
                               List.new([Sym.new('values'), false, Sym.new('e')])])
                   ])
        when 'xpcall'
          fn = items[1]
          handler = items[2]
          args = items[3..]
          List.new([
                     Sym.new('try'),
                     List.new([Sym.new('values'), true, List.new([fn, *args])]),
                     List.new([Sym.new('catch'), Sym.new('StandardError'), Sym.new('e'),
                               List.new([Sym.new('values'), false, List.new([handler, Sym.new('e')])])])
                   ])
        when '->', '->>', '-?>', '-?>>'
          normalize(thread(items[1..], head.name))
        when 'doto'
          normalize(doto(items[1..]))
        else
          List.new(items)
        end
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
        forms[1..].reduce(forms.first) do |memo, form|
          temp = thread_temp
          List.new([
                     Sym.new('let'),
                     Vec.new([temp, memo]),
                     List.new([
                                Sym.new('if'),
                                List.new([Sym.new('='), temp, nil]),
                                nil,
                                thread_step(temp, form, position)
                              ])
                   ])
        end
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
