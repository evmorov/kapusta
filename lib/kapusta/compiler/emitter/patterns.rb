# frozen_string_literal: true

module Kapusta
  module Compiler
    module EmitterModules
      module Patterns
        private

        def emit_pattern_bind(pattern, value_code, env)
          if pattern.is_a?(Sym)
            return ['', env] if pattern.name == '_'

            ruby_name = define_local(env, pattern)
            return ["#{ruby_name} = #{value_code}", env]
          end

          native = try_emit_native_pattern_bind(pattern, value_code, env)
          return native if native

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

        def try_emit_native_pattern_bind(pattern, value_code, env)
          case pattern
          when Vec
            try_emit_native_vec_bind(pattern, value_code, env)
          when HashLit
            try_emit_native_hash_bind(pattern, value_code, env)
          end
        rescue PatternNotTranslatable
          nil
        end

        def try_emit_native_vec_bind(pattern, value_code, env)
          parts = []
          deferred = []
          current_env = env
          items = pattern.items
          i = 0
          while i < items.length
            if items[i].is_a?(Sym) && items[i].name == '&'
              sub = items[i + 1]
              raise PatternNotTranslatable unless sub.is_a?(Sym)

              parts << native_rest_target(sub, current_env)
              i += 2
            else
              code, current_env, follow_up = native_destructure_target(items[i], current_env, allow_follow_up: true)
              parts << code
              deferred << follow_up if follow_up
              i += 1
            end
          end
          if deferred.empty?
            ["#{parts.join(', ')} = #{value_code}", current_env]
          else
            arr_var = simple_expression?(value_code) ? value_code : temp('array')
            lines = []
            lines << "#{arr_var} = #{value_code}" unless arr_var == value_code
            lines << "#{parts.join(', ')} = #{arr_var}"
            deferred.each do |follow_up|
              sub_code, current_env = follow_up.call(current_env)
              lines << sub_code
            end
            [lines.join("\n"), current_env]
          end
        end

        def try_emit_native_hash_bind(pattern, value_code, env)
          pairs = pattern.pairs
          raise PatternNotTranslatable if pairs.empty?

          temp_var = simple_expression?(value_code) ? value_code : temp('hash')
          lines = []
          lines << "#{temp_var} = #{value_code}" unless temp_var == value_code
          current_env = env
          pairs.each do |key, sub|
            access = "#{temp_var}[#{key.inspect}]"
            if sub.is_a?(Sym)
              raise PatternNotTranslatable if sub.name == '_'

              bind_name = sub.name.start_with?('?') ? sub.name.delete_prefix('?') : sub.name
              ruby_name = define_local(current_env, bind_name)
              lines << "#{ruby_name} = #{access}"
            else
              sub_code, current_env = try_emit_native_pattern_bind(sub, access, current_env) ||
                                      raise(PatternNotTranslatable)
              lines << sub_code
            end
          end
          [lines.join("\n"), current_env]
        end

        def native_destructure_target(pattern, env, allow_follow_up: false)
          case pattern
          when Sym
            return ['_', env, nil] if pattern.name == '_'

            bind_name = pattern.name.start_with?('?') ? pattern.name.delete_prefix('?') : pattern.name
            ruby_name = define_local(env, bind_name)
            [ruby_name, env, nil]
          when Vec
            inner = []
            current = env
            deferred = []
            items = pattern.items
            i = 0
            while i < items.length
              if items[i].is_a?(Sym) && items[i].name == '&'
                inner << native_rest_target(items[i + 1], current)
                i += 2
              else
                code, current, follow_up = native_destructure_target(items[i], current)
                inner << code
                deferred << follow_up if follow_up
                i += 1
              end
            end
            raise PatternNotTranslatable unless deferred.empty?

            ["(#{inner.join(', ')})", current, nil]
          when HashLit
            raise PatternNotTranslatable unless allow_follow_up

            slot = temp('slot')
            follow_up = lambda do |outer_env|
              try_emit_native_hash_bind(pattern, slot, outer_env) || raise(PatternNotTranslatable)
            end
            [slot, env, follow_up]
          else
            raise PatternNotTranslatable
          end
        end

        def native_rest_target(sym, env)
          raise PatternNotTranslatable unless sym.is_a?(Sym)

          return '*' if sym.name == '_'

          bind_name = sym.name.start_with?('?') ? sym.name.delete_prefix('?') : sym.name
          "*#{define_local(env, bind_name)}"
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

        class PatternNotTranslatable < StandardError; end

        def native_pattern_plan(pattern, env, mode:, allow_pins:)
          state = { bound_names: {}, binding_names: [], guards: [] }
          ruby_pattern = compile_native_pattern(pattern, env, mode:, allow_pins:, state:)
          {
            pattern: ruby_pattern,
            guards: state[:guards],
            bindings: state[:binding_names]
          }
        rescue PatternNotTranslatable
          nil
        end

        def compile_native_pattern(pattern, env, mode:, allow_pins:, state:)
          case pattern
          when Sym then compile_native_symbol(pattern, env, mode:, state:)
          when Vec then compile_native_sequence(pattern.items, env, mode:, allow_pins:, state:)
          when HashLit then compile_native_hash(pattern, env, mode:, allow_pins:, state:)
          when List
            if pin_pattern?(pattern)
              compile_native_pin(pattern, env, mode:, allow_pins:)
            elsif or_pattern?(pattern)
              compile_native_or(pattern, env, mode:, allow_pins:, state:)
            else
              compile_native_sequence(pattern.items, env, mode:, allow_pins:, state:)
            end
          when nil then 'nil'
          when Symbol, String, Numeric, true, false then pattern.inspect
          else raise PatternNotTranslatable
          end
        end

        def compile_native_symbol(pattern, env, mode:, state:)
          name = pattern.name
          return '_' if name == '_'

          if nil_allowing_pattern_name?(name)
            bind_name = name.start_with?('?') ? name.delete_prefix('?') : name
            raise PatternNotTranslatable if state[:bound_names].key?(bind_name)

            state[:bound_names][bind_name] = true
            state[:binding_names] << bind_name
            sanitize_local(bind_name)
          else
            binding = mode == :match ? env.lookup_if_defined(name) : nil
            if state[:bound_names].key?(name)
              raise PatternNotTranslatable
            elsif binding
              "^(#{binding_value_code(binding)})"
            else
              state[:bound_names][name] = true
              state[:binding_names] << name
              ruby = sanitize_local(name)
              state[:guards] << "!#{ruby}.nil?"
              ruby
            end
          end
        end

        def compile_native_sequence(items, env, mode:, allow_pins:, state:)
          parts = []
          has_rest = false
          i = 0
          while i < items.length
            if rest_pattern_marker?(items, i)
              has_rest = true
              sub = items[i + 1]
              raise PatternNotTranslatable unless sub.is_a?(Sym)

              if sub.name == '_'
                parts << '*'
              else
                state[:bound_names][sub.name] = true
                state[:binding_names] << sub.name
                parts << "*#{sanitize_local(sub.name)}"
              end
              i += 2
            else
              parts << compile_native_pattern(items[i], env, mode:, allow_pins:, state:)
              i += 1
            end
          end
          parts << '*' unless has_rest
          "[#{parts.join(', ')}]"
        end

        def compile_native_hash(pattern, env, mode:, allow_pins:, state:)
          pairs = pattern.pairs.map do |key, value|
            raise PatternNotTranslatable unless key.is_a?(Symbol)

            "#{key}: #{compile_native_pattern(value, env, mode:, allow_pins:, state:)}"
          end
          "{#{pairs.join(', ')}}"
        end

        def compile_native_pin(pattern, env, mode:, allow_pins:)
          raise PatternNotTranslatable unless allow_pins && mode == :case

          name_sym = pattern.items[1]
          raise PatternNotTranslatable unless name_sym.is_a?(Sym)

          binding = env.lookup_if_defined(name_sym.name)
          raise PatternNotTranslatable unless binding

          "^(#{binding_value_code(binding)})"
        end

        def compile_native_or(pattern, env, mode:, allow_pins:, state:)
          initial_bound = state[:bound_names].dup
          initial_names = state[:binding_names].length
          initial_guards = state[:guards].length
          variants = pattern.items[1..].map do |subpattern|
            alt_state = {
              bound_names: initial_bound.dup,
              binding_names: state[:binding_names].dup,
              guards: state[:guards].dup
            }
            compiled = compile_native_pattern(subpattern, env, mode:, allow_pins:, state: alt_state)
            raise PatternNotTranslatable if alt_state[:binding_names].length > initial_names
            raise PatternNotTranslatable if alt_state[:guards].length > initial_guards

            compiled
          end
          "(#{variants.join(' | ')})"
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
              emit_error!('`where` is only valid as a case/match clause head')
            else
              emit_sequence_match_pattern(pattern.items, env, mode:, allow_pins:, state:)
            end
          when nil
            '[:lit, nil]'
          when Symbol, String, Numeric, true, false
            "[:lit, #{pattern.inspect}]"
          else
            emit_error!("bad pattern: #{pattern.inspect}")
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
          binding = prefer_pin && mode == :match ? env.lookup_if_defined(name) : nil
          if state[:bound_names].key?(name)
            "[:ref, #{name.inspect}]"
          elsif binding
            "[:pin, #{binding_value_code(binding)}]"
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
          emit_error!('pin patterns are only supported inside `case` guards') unless allow_pins && mode == :case

          name_sym = pattern.items[1]
          emit_error!("bad pin pattern: #{pattern.inspect}") unless name_sym.is_a?(Sym)

          binding = env.lookup_if_defined(name_sym.name)
          emit_error!("cannot pin undefined name: #{name_sym.name}") unless binding

          "[:pin, #{binding_value_code(binding)}]"
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
            emit_error!('all `or` patterns must bind the same names') if canonical_names.sort != alt_names.sort

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
            emit_error!("bad pattern: #{pattern.inspect}")
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
