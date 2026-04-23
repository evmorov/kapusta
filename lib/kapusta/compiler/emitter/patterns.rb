# frozen_string_literal: true

module Kapusta
  module Compiler
    module EmitterModules
      module Patterns
        private

        def emit_pattern_bind(pattern, value_code, env)
          if pattern.is_a?(Sym)
            return ['nil', env] if pattern.name == '_'

            ruby_name = temp(sanitize_local(pattern.name))
            env.define(pattern.name, ruby_name)
            ["#{ruby_name} = #{value_code}", env]
          else
            bindings_var = temp('bindings')
            current_env = env
            lines = [
              "#{bindings_var} = #{runtime_call(:destructure, emit_pattern(pattern), value_code)}"
            ]
            pattern_names(pattern).each do |name|
              ruby_name = temp(sanitize_local(name))
              current_env.define(name, ruby_name)
              lines << "#{ruby_name} = #{bindings_var}.fetch(#{name.inspect})"
            end
            [lines.join("\n"), current_env]
          end
        end

        def emit_bindings_from_match(pattern, bindings_var, env)
          current_env = env
          lines = []
          pattern_names(pattern).each do |name|
            ruby_name = temp(sanitize_local(name))
            current_env.define(name, ruby_name)
            lines << "#{ruby_name} = #{bindings_var}.fetch(#{name.inspect})"
          end
          [lines.join("\n"), current_env]
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
      end
    end
  end
end
