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
          lines = ["if #{cond}", indent(truthy)]
          append_else_lines(lines, args[2..], env, current_scope)
          lines << 'end'
          lines.join("\n")
        end

        def append_else_lines(lines, args, env, current_scope)
          return if args.empty?

          if args.length == 1 && if_form?(args[0])
            append_elsif_lines(lines, args[0].rest, env, current_scope)
          elsif args.length >= 2
            append_elsif_lines(lines, args, env, current_scope)
          else
            lines << 'else'
            lines << indent(emit_expr(args[0], env, current_scope))
          end
        end

        def append_elsif_lines(lines, args, env, current_scope)
          return append_else_lines(lines, args, env, current_scope) if args.length < 2

          lines << "elsif #{emit_expr(args[0], env, current_scope)}"
          lines << indent(emit_expr(args[1], env, current_scope))
          append_else_lines(lines, args[2..], env, current_scope)
        end

        def if_form?(form)
          form.is_a?(List) && form.head.is_a?(Sym) && form.head.name == 'if'
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
          arm_body = [assign_code, body_code].reject(&:empty?).join("\n")
          <<~RUBY.chomp
            #{match_var} = #{runtime_call(:match_pattern, plan[:pattern], value_var)}
            if #{match_var}[0]
              #{bindings_var} = #{match_var}[1]
              #{arm_body}
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
          bindings_line = assign_code.empty? ? '' : "\n  #{assign_code}"
          <<~RUBY.chomp
            #{match_var} = #{runtime_call(:match_pattern, plan[:pattern], value_var)}
            if #{match_var}[0]
              #{bindings_var} = #{match_var}[1]#{bindings_line}
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
          <<~RUBY.chomp
            (-> do
              #{indent(emit_while_statement(args, env, current_scope))}
              nil
            end).call
          RUBY
        end

        def emit_for(args, env, current_scope)
          loop_code = emit_for_statement(args, env, current_scope)
          <<~RUBY.chomp
            (-> do
              #{indent(loop_code)}
              nil
            end).call
          RUBY
        end

        def emit_each(args, env, current_scope)
          iter_code = emit_each_statement(args, env, current_scope)
          <<~RUBY.chomp
            (-> do
              #{iter_code}
              nil
            end).call
          RUBY
        end

        def emit_while_statement(args, env, current_scope)
          body_code, = emit_sequence(args[1..], env, current_scope,
                                     allow_method_definitions: false,
                                     result: false)
          [
            "while #{emit_expr(args[0], env, current_scope)}",
            indent(body_code),
            'end'
          ].join("\n")
        end

        def emit_for_statement(args, env, current_scope)
          parsed = parse_counted_for_bindings(args[0].items, env, current_scope)
          body_code, = emit_sequence(args[1..], parsed[:loop_env], current_scope,
                                     allow_method_definitions: false,
                                     result: false)
          emit_counted_loop(**parsed, current_scope:, body_code:)
        end

        def emit_each_statement(args, env, current_scope)
          emit_iteration(args[0], env, current_scope) do |iter_env|
            emit_sequence(args[1..], iter_env, current_scope,
                          allow_method_definitions: false,
                          result: false).first
          end
        end
      end
    end
  end
end
