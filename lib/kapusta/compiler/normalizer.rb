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
          cond = items[1]
          body = wrap_do(items[2..])
          List.new([Sym.new('if'), cond, body, nil])
        when 'unless'
          cond = items[1]
          body = wrap_do(items[2..])
          List.new([Sym.new('if'), cond, nil, body])
        when 'tset'
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

        forms[1..].reduce(value) do |memo, form|
          threaded =
            if form.is_a?(List)
              if position == :first
                List.new([form.items[0], memo, *form.items[1..]])
              else
                List.new([*form.items, memo])
              end
            else
              List.new([form, memo])
            end

          if short
            List.new([Sym.new('if'), List.new([Sym.new('='), memo, nil]), nil, threaded])
          else
            threaded
          end
        end
      end

      def doto(forms)
        value = forms.first
        temp = Sym.new('__doto__')
        body = forms[1..].map do |form|
          if form.is_a?(List)
            List.new([form.items[0], temp, *form.items[1..]])
          else
            List.new([form, temp])
          end
        end
        List.new([Sym.new('let'), Vec.new([temp, value]), *body, temp])
      end
    end
  end
end
