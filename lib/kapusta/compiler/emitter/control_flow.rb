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

        def emit_case(args, env, current_scope, mode)
          value_var = temp('case_value')
          body = build_case_clauses(value_var, args[1..], env, current_scope, mode)
          <<~RUBY.chomp
            (-> do
              #{value_var} = #{emit_expr(args[0], env, current_scope)}
              #{body}
            end).call
          RUBY
        end

        def build_case_clauses(value_var, clauses, env, current_scope, mode)
          return 'nil' if clauses.empty?

          pattern = clauses[0]
          body = clauses[1]
          else_code = build_case_clauses(value_var, clauses[2..], env, current_scope, mode)
          emit_case_clause(value_var, pattern, body, else_code, env, current_scope, mode)
        end

        def emit_case_clause(value_var, pattern, body, else_code, env, current_scope, mode)
          if where_pattern?(pattern)
            emit_guarded_case_clause(value_var, pattern, body, else_code, env, current_scope, mode)
          else
            emit_simple_case_clause(value_var, pattern, body, else_code, env, current_scope, mode)
          end
        end

        def emit_simple_case_clause(value_var, pattern, body, else_code, env, current_scope, mode)
          match_var = temp('match')
          bindings_var = temp('bindings')
          plan = pattern_match_plan(pattern, env, mode:, allow_pins: false)
          arm_env = env.child
          assign_code, arm_env = emit_bindings_from_match(plan[:bindings], bindings_var, arm_env)
          body_code = emit_expr(body, arm_env, current_scope)
          <<~RUBY.chomp
            #{match_var} = #{runtime_call(:match_pattern, plan[:pattern], value_var)}
            if #{match_var}[0]
              #{bindings_var} = #{match_var}[1]
              #{assign_code}
              #{body_code}
            else
              #{indent(else_code)}
            end
          RUBY
        end

        def emit_guarded_case_clause(value_var, pattern, body, else_code, env, current_scope, mode)
          inner = pattern.items[1]
          guards = pattern.items[2..]
          match_var = temp('match')
          bindings_var = temp('bindings')
          plan = pattern_match_plan(inner, env, mode:, allow_pins: mode == :case)
          arm_env = env.child
          assign_code, arm_env = emit_bindings_from_match(plan[:bindings], bindings_var, arm_env)
          guard_code = emit_case_guards(guards, arm_env, current_scope)
          body_code = emit_expr(body, arm_env, current_scope)
          <<~RUBY.chomp
            #{match_var} = #{runtime_call(:match_pattern, plan[:pattern], value_var)}
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

        def emit_case_guards(guards, env, current_scope)
          return 'true' if guards.empty?

          guards.map { |guard| parenthesize(emit_expr(guard, env, current_scope)) }.join(' && ')
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
          parsed = parse_counted_for_bindings(args[0].items, env, current_scope)
          body_code, = emit_sequence(args[1..], parsed[:loop_env], current_scope, allow_method_definitions: false)
          loop_code = emit_counted_loop(**parsed, current_scope:, body_code:)
          <<~RUBY.chomp
            (-> do
              #{indent(loop_code)}
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
