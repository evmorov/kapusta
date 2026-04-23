# frozen_string_literal: true

module Kapusta
  module Compiler
    module EmitterModules
      module ControlFlow
        private

        def emit_if(args, env, current_scope)
          build_if(args, env, current_scope)
        end

        def build_if(args, env, current_scope)
          return 'nil' if args.empty?
          return emit_expr(args[0], env, current_scope) if args.length == 1

          cond = emit_expr(args[0], env, current_scope)
          truthy = emit_expr(args[1], env, current_scope)
          falsy = build_if(args[2..], env, current_scope)
          <<~RUBY.chomp
            if #{cond}
              #{truthy}
            else
              #{indent(falsy)}
            end
          RUBY
        end

        def emit_case(args, env, current_scope)
          value_var = temp('case_value')
          body = build_case_clauses(value_var, args[1..], env, current_scope)
          <<~RUBY.chomp
            (-> do
              #{value_var} = #{emit_expr(args[0], env, current_scope)}
              #{body}
            end).call
          RUBY
        end

        def build_case_clauses(value_var, clauses, env, current_scope)
          return 'nil' if clauses.empty?

          pattern = clauses[0]
          body = clauses[1]
          else_code = build_case_clauses(value_var, clauses[2..], env, current_scope)
          emit_case_clause(value_var, pattern, body, else_code, env, current_scope)
        end

        def emit_case_clause(value_var, pattern, body, else_code, env, current_scope)
          if where_pattern?(pattern)
            emit_guarded_case_clause(value_var, pattern, body, else_code, env, current_scope)
          else
            emit_simple_case_clause(value_var, pattern, body, else_code, env, current_scope)
          end
        end

        def emit_simple_case_clause(value_var, pattern, body, else_code, env, current_scope)
          match_var = temp('match')
          bindings_var = temp('bindings')
          arm_env = env.child
          assign_code, arm_env = emit_bindings_from_match(pattern, bindings_var, arm_env)
          body_code = emit_expr(body, arm_env, current_scope)
          <<~RUBY.chomp
            #{match_var} = #{runtime_call(:match_pattern, emit_pattern(pattern), value_var)}
            if #{match_var}[0]
              #{bindings_var} = #{match_var}[1]
              #{assign_code}
              #{body_code}
            else
              #{indent(else_code)}
            end
          RUBY
        end

        def emit_guarded_case_clause(value_var, pattern, body, else_code, env, current_scope)
          inner = pattern.items[1]
          guard = pattern.items[2]
          match_var = temp('match')
          bindings_var = temp('bindings')
          arm_env = env.child
          assign_code, arm_env = emit_bindings_from_match(inner, bindings_var, arm_env)
          guard_code = emit_expr(guard, arm_env, current_scope)
          body_code = emit_expr(body, arm_env, current_scope)
          <<~RUBY.chomp
            #{match_var} = #{runtime_call(:match_pattern, emit_pattern(inner), value_var)}
            if #{match_var}[0]
              #{bindings_var} = #{match_var}[1]
              #{assign_code}
              if #{guard_code}
                #{body_code}
              else
                #{indent(else_code, 2)}
              end
            else
              #{indent(else_code)}
            end
          RUBY
        end

        def emit_while(args, env, current_scope)
          body_code, = emit_sequence(args[1..], env, current_scope, allow_method_definitions: false)
          <<~RUBY.chomp
            (-> do
              while #{emit_expr(args[0], env, current_scope)}
                #{indent(body_code)}
              end
              nil
            end).call
          RUBY
        end

        def emit_for(args, env, current_scope)
          bindings = args[0].items
          name = bindings[0]
          start_code = emit_expr(bindings[1], env, current_scope)
          finish_code = emit_expr(bindings[2], env, current_scope)
          step_code = '1'
          until_form = nil
          i = 3
          while i < bindings.length
            if bindings[i].is_a?(Sym) && bindings[i].name == '&until'
              until_form = bindings[i + 1]
              i += 2
            else
              step_code = emit_expr(bindings[i], env, current_scope)
              i += 1
            end
          end

          loop_env = env.child
          ruby_name = temp(sanitize_local(name.name))
          loop_env.define(name.name, ruby_name)
          body_code, = emit_sequence(args[1..], loop_env, current_scope, allow_method_definitions: false)
          until_code = until_form ? "break if #{emit_expr(until_form, loop_env, current_scope)}" : nil
          cmp_var = temp('cmp')
          step_var = temp('step')
          finish_var = temp('finish')
          <<~RUBY.chomp
            (-> do
              #{ruby_name} = #{start_code}
              #{finish_var} = #{finish_code}
              #{step_var} = #{step_code}
              #{cmp_var} = #{step_var} >= 0 ? :<= : :>=
              while #{ruby_name}.public_send(#{cmp_var}, #{finish_var})
                #{until_code}
                #{indent(body_code)}
                #{ruby_name} += #{step_var}
              end
              nil
            end).call
          RUBY
        end

        def emit_each(args, env, current_scope)
          iter_code = emit_iteration(args[0], env, current_scope) do |iter_env|
            emit_sequence(args[1..], iter_env, current_scope, allow_method_definitions: false).first
          end
          <<~RUBY.chomp
            (-> do
              #{iter_code}
              nil
            end).call
          RUBY
        end
      end
    end
  end
end
