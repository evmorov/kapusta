# frozen_string_literal: true

module Kapusta
  module Compiler
    module EmitterModules
      module Patterns
        private

        def emit_pattern_bind(pattern, value_code, env)
          if pattern.is_a?(Sym)
            return ['nil', env] if pattern.name == '_'

            ruby_name = define_local(env, pattern)
            ["#{ruby_name} = #{value_code}", env]
          else
            bindings_var = temp('bindings')
            current_env = env
            lines = [
              "#{bindings_var} = #{runtime_call(:destructure, emit_pattern(pattern), value_code)}"
            ]
            pattern_names(pattern).each do |name|
              ruby_name = define_local(current_env, name)
              lines << "#{ruby_name} = #{bindings_var}.fetch(#{name.inspect})"
            end
            [lines.join("\n"), current_env]
          end
        end

        def emit_bindings_from_match(binding_names, bindings_var, env)
          current_env = env
          lines = []
          binding_names.each do |name|
            ruby_name = define_local(current_env, name)
            lines << "#{ruby_name} = #{bindings_var}.fetch(#{name.inspect})"
          end
          [lines.join("\n"), current_env]
        end

        def pattern_match_plan(pattern, env, mode:, allow_pins:)
          state = { bound_names: {}, binding_names: [] }
          {
            pattern: emit_match_pattern(pattern, env, mode:, allow_pins:, state:),
            bindings: state[:binding_names]
          }
        end

        def emit_match_pattern(pattern, env, mode:, allow_pins:, state:)
          case pattern
          when Sym
            emit_symbol_match_pattern(pattern, env, mode:, state:)
          when Vec
            emit_sequence_match_pattern(pattern.items, env, mode:, allow_pins:, state:)
          when HashLit
            pairs = pattern.pairs.map do |key, value|
              "[#{key.inspect}, #{emit_match_pattern(value, env, mode:, allow_pins:, state:)}]"
            end
            "[:hash, [#{pairs.join(', ')}]]"
          when List
            if pin_pattern?(pattern)
              emit_pin_match_pattern(pattern, env, mode:, allow_pins:)
            elsif or_pattern?(pattern)
              emit_or_match_pattern(pattern, env, mode:, allow_pins:, state:)
            elsif where_pattern?(pattern)
              raise Error, '`where` is only valid as a case/match clause head'
            else
              emit_sequence_match_pattern(pattern.items, env, mode:, allow_pins:, state:)
            end
          when nil
            '[:lit, nil]'
          when Symbol, String, Numeric, true, false
            "[:lit, #{pattern.inspect}]"
          else
            raise Error, "bad pattern: #{pattern.inspect}"
          end
        end

        def emit_symbol_match_pattern(pattern, env, mode:, state:)
          name = pattern.name

          if name == '_'
            '[:wild]'
          elsif nil_allowing_pattern_name?(name)
            bind_name = name.start_with?('?') ? name.delete_prefix('?') : name
            emit_named_match_pattern(bind_name, env, mode:, state:, allow_nil: true, prefer_pin: false)
          else
            emit_named_match_pattern(name, env, mode:, state:, allow_nil: false, prefer_pin: true)
          end
        end

        def emit_named_match_pattern(name, env, mode:, state:, allow_nil:, prefer_pin:)
          if state[:bound_names].key?(name)
            "[:ref, #{name.inspect}]"
          elsif prefer_pin && mode == :match && env.defined?(name)
            "[:pin, #{binding_value_code(env.lookup(name))}]"
          else
            state[:bound_names][name] = true
            state[:binding_names] << name
            "[:bind, #{name.inspect}, #{allow_nil}]"
          end
        end

        def emit_sequence_match_pattern(items, env, mode:, allow_pins:, state:)
          parts = []
          i = 0
          while i < items.length
            if rest_pattern_marker?(items, i)
              parts << "[:rest, #{emit_match_pattern(items[i + 1], env, mode:, allow_pins:, state:)}]"
              i += 2
            else
              parts << emit_match_pattern(items[i], env, mode:, allow_pins:, state:)
              i += 1
            end
          end
          "[:vec, [#{parts.join(', ')}]]"
        end

        def emit_pin_match_pattern(pattern, env, mode:, allow_pins:)
          raise Error, 'pin patterns are only supported inside `case` guards' unless allow_pins && mode == :case

          name_sym = pattern.items[1]
          raise Error, "bad pin pattern: #{pattern.inspect}" unless name_sym.is_a?(Sym)
          raise Error, "cannot pin undefined name: #{name_sym.name}" unless env.defined?(name_sym.name)

          "[:pin, #{binding_value_code(env.lookup(name_sym.name))}]"
        end

        def emit_or_match_pattern(pattern, env, mode:, allow_pins:, state:)
          initial_names = state[:binding_names].length
          initial_bound = state[:bound_names].dup
          canonical_names = nil
          variants = pattern.items[1..].map do |subpattern|
            alt_state = {
              bound_names: initial_bound.dup,
              binding_names: state[:binding_names].dup
            }
            compiled = emit_match_pattern(subpattern, env, mode:, allow_pins:, state: alt_state)
            alt_names = alt_state[:binding_names][initial_names..]
            canonical_names ||= alt_names
            raise Error, 'all `or` patterns must bind the same names' if canonical_names.sort != alt_names.sort

            compiled
          end

          canonical_names.each do |name|
            state[:bound_names][name] = true
            state[:binding_names] << name
          end
          "[:or, [#{variants.join(', ')}]]"
        end

        def emit_pattern(pattern)
          case pattern
          when Sym
            pattern.name == '_' ? '[:sym, "_"]' : "[:sym, #{pattern.name.inspect}]"
          when Vec
            parts = []
            items = pattern.items
            i = 0
            while i < items.length
              if items[i].is_a?(Sym) && items[i].name == '&'
                parts << "[:rest, #{emit_pattern(items[i + 1])}]"
                i += 2
              else
                parts << emit_pattern(items[i])
                i += 1
              end
            end
            "[:vec, [#{parts.join(', ')}]]"
          when HashLit
            pairs = pattern.pairs.map { |key, value| "[#{key.inspect}, #{emit_pattern(value)}]" }
            "[:hash, [#{pairs.join(', ')}]]"
          when nil
            '[:nil]'
          when Symbol, String, Numeric, true, false
            "[:lit, #{pattern.inspect}]"
          else
            raise Error, "bad pattern: #{pattern.inspect}"
          end
        end

        def pattern_names(pattern)
          case pattern
          when Sym
            pattern.name == '_' ? [] : [pattern.name]
          when Vec
            names = []
            items = pattern.items
            i = 0
            while i < items.length
              if items[i].is_a?(Sym) && items[i].name == '&'
                names.concat(pattern_names(items[i + 1]))
                i += 2
              else
                names.concat(pattern_names(items[i]))
                i += 1
              end
            end
            names
          when HashLit
            pattern.pairs.flat_map { |_key, value| pattern_names(value) }
          when List
            where_pattern?(pattern) ? pattern_names(pattern.items[1]) : []
          else
            []
          end
        end

        def where_pattern?(pattern)
          pattern.is_a?(List) && pattern.head.is_a?(Sym) && pattern.head.name == 'where'
        end

        def pin_pattern?(pattern)
          pattern.is_a?(List) &&
            pattern.items.length == 2 &&
            pattern.head.is_a?(Sym) &&
            pattern.head.name == '='
        end

        def or_pattern?(pattern)
          pattern.is_a?(List) && pattern.head.is_a?(Sym) && pattern.head.name == 'or'
        end

        def nil_allowing_pattern_name?(name)
          name.length > 1 && (name.start_with?('?') || name.start_with?('_'))
        end

        def rest_pattern_marker?(items, index)
          items[index].is_a?(Sym) && items[index].name == '&'
        end
      end
    end
  end
end
