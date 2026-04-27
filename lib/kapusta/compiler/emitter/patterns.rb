# frozen_string_literal: true

module Kapusta
  module Compiler
    module EmitterModules
      module Patterns
        private

        def emit_pattern_bind(pattern, value_code, env)
          if pattern.is_a?(Sym)
            return ['', env] if pattern.name == '_'

            validate_binding_symbol!(pattern)
            ruby_name = define_local(env, pattern)
            return ["#{ruby_name} = #{value_code}", env]
          end

          native = try_emit_native_pattern_bind(pattern, value_code, env)
          return native if native

          emit_error!("destructure pattern this compiler cannot translate: #{pattern.inspect}")
        end

        def validate_binding_symbol!(sym)
          name = sym.name
          if Compiler::SPECIAL_FORMS.include?(name)
            emit_error!("local #{name} was overshadowed by a special form or macro")
          end
          return unless sym.is_a?(MacroSym)

          emit_error!("macro tried to bind #{name} without gensym")
        end

        def validate_destructure_pattern!(pattern)
          items = pattern.items
          items.each_with_index do |item, idx|
            emit_error!('unable to bind table ...') if item.is_a?(Sym) && item.name == '...'
            next unless item.is_a?(Sym) && item.name == '&'

            emit_error!('expected rest argument before last parameter') if idx + 2 < items.length
            emit_error!('expected rest argument before last parameter') if idx + 1 >= items.length
          end
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
          validate_destructure_pattern!(pattern)
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

              ruby_name = define_local(current_env, sub.name)
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

            ruby_name = define_local(env, pattern.name)
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

          "*#{define_local(env, sym.name)}"
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
            raise PatternNotTranslatable if state[:bound_names].key?(name)

            state[:bound_names][name] = true
            state[:binding_names] << name
            sanitize_local(name)
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
