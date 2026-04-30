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
          emit_error!(:if_no_body) if args.length < 2

          cond = emit_expr(args[0], env, current_scope)
          truthy = emit_if_branch(args[1], env, current_scope)
          return "#{truthy} if #{cond}" if args.length == 2 && !truthy.include?("\n") && !cond.include?("\n")

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
            lines << indent(emit_if_branch(args[0], env, current_scope))
          end
        end

        def append_elsif_lines(lines, args, env, current_scope)
          return append_else_lines(lines, args, env, current_scope) if args.length < 2

          lines << "elsif #{emit_expr(args[0], env, current_scope)}"
          lines << indent(emit_if_branch(args[1], env, current_scope))
          append_else_lines(lines, args[2..], env, current_scope)
        end

        def emit_if_branch(form, env, current_scope)
          return emit_expr(form, env, current_scope) unless do_form?(form)

          emit_sequence(form.rest, env, current_scope,
                        allow_method_definitions: false,
                        result: true).first
        end

        def if_form?(form)
          form.is_a?(List) && form.head.is_a?(Sym) && form.head.name == 'if'
        end

        def emit_case(args, env, current_scope, mode)
          emit_error!(:case_no_subject) if args.empty?

          clauses = args[1..]
          emit_error!(:case_no_patterns) if clauses.empty?
          emit_error!(:case_odd_patterns) if clauses.length.odd?

          value_code = emit_expr(args[0], env, current_scope)
          if simple_case_subject?(args[0]) && simple_expression?(value_code)
            body = emit_case_body(value_code, clauses, env, current_scope, mode)
            emit_error!(:case_unsupported) unless body
            return body
          end

          value_var = temp('case_value')
          body = emit_case_body(value_var, clauses, env, current_scope, mode)
          emit_error!(:case_unsupported) unless body
          [
            '(-> do',
            indent("#{value_var} = #{value_code}"),
            indent(body),
            'end).call'
          ].join("\n")
        end

        def emit_case_body(value_var, clauses, env, current_scope, mode)
          return try_emit_compat_case(value_var, clauses, env, current_scope, mode) if mruby_target?

          try_emit_native_case(value_var, clauses, env, current_scope, mode) ||
            try_emit_compat_case(value_var, clauses, env, current_scope, mode)
        end

        def simple_case_subject?(form)
          case form
          when Sym then !form.dotted?
          when Numeric, String, Symbol, true, false, nil then true
          else false
          end
        end

        def try_emit_native_case(value_var, clauses, env, current_scope, mode)
          arms = []
          i = 0
          while i < clauses.length
            pattern = clauses[i]
            body = clauses[i + 1]
            inner, where_guards = if where_pattern?(pattern)
                                    [pattern.items[1], pattern.items[2..]]
                                  else
                                    [pattern, []]
                                  end
            sub_patterns = or_pattern?(inner) ? inner.items[1..] : [inner]
            sub_arms = sub_patterns.map do |sub|
              try_native_arm(sub, body, where_guards, env, current_scope, mode)
            end
            return if sub_arms.any?(&:nil?)

            arms.concat(sub_arms)
            i += 2
          end
          arms << ['else', indent('nil')].join("\n") unless wildcard_last?(clauses)
          ["case #{value_var}", *arms, 'end'].join("\n")
        end

        def try_native_arm(pattern, body, where_guards, env, current_scope, mode)
          allow_pins = !where_guards.empty? && mode == :case
          plan = native_pattern_plan(pattern, env, mode:, allow_pins:)
          return unless plan

          arm_env = env.child
          plan[:bindings].each { |name| arm_env.define(name, sanitize_local(name)) }
          guard_codes = plan[:guards] +
                        where_guards.map { |g| emit_expr(g, arm_env, current_scope) }
          guard_clause = guard_codes.empty? ? '' : " if #{guard_codes.join(' && ')}"
          body_code = emit_expr(body, arm_env, current_scope)
          ["in #{plan[:pattern]}#{guard_clause}", indent(body_code)].join("\n")
        end

        def try_emit_compat_case(value_var, clauses, env, current_scope, mode)
          arms = []
          i = 0
          while i < clauses.length
            pattern = clauses[i]
            body = clauses[i + 1]
            inner, where_guards = if where_pattern?(pattern)
                                    [pattern.items[1], pattern.items[2..]]
                                  else
                                    [pattern, []]
                                  end
            sub_patterns = or_pattern?(inner) ? inner.items[1..] : [inner]
            sub_arms = sub_patterns.map do |sub|
              try_compat_arm(sub, body, where_guards, value_var, env, current_scope, mode)
            end
            return if sub_arms.any?(&:nil?)

            arms.concat(sub_arms)
            i += 2
          end
          emit_compat_case_lines(arms, wildcard_last?(clauses))
        end

        def wildcard_last?(clauses)
          last_pattern = clauses[-2]
          last_pattern.is_a?(Sym) && last_pattern.name == '_'
        end

        def try_compat_arm(pattern, body, where_guards, value_var, env, current_scope, mode)
          allow_pins = !where_guards.empty? && mode == :case
          arm_env = env.child
          plan = compat_pattern_plan(pattern, value_var, env, arm_env, mode:, allow_pins:)
          return unless plan

          where_guard_codes = where_guards.map { |g| emit_expr(g, arm_env, current_scope) }
          if where_guard_codes.empty?
            guard_codes = plan[:conditions]
            prelude     = plan[:prelude]
          else
            prelude_guards = plan[:prelude].map { |line| "begin #{line}; true end" }
            guard_codes = plan[:conditions] + prelude_guards + where_guard_codes
            prelude     = []
          end
          body_code = emit_expr(body, arm_env, current_scope)
          [guard_codes, prelude, body_code]
        end

        def emit_compat_case_lines(arms, wildcard_last)
          unconditional_arm = arms.any? { |conditions, _prelude, _body_code| conditions.empty? }
          lines = ['case']
          arms.each_with_index do |(conditions, prelude, body_code), idx|
            lines << if wildcard_last && idx == arms.length - 1
                       'else'
                     else
                       emit_compat_condition_header(conditions)
                     end
            lines << indent([*prelude, body_code].join("\n"))
          end
          unless wildcard_last || unconditional_arm
            lines << 'else'
            lines << indent('nil')
          end
          lines << 'end'
          lines.join("\n")
        end

        def emit_compat_condition_header(conditions)
          return 'when true' if conditions.empty?

          "when #{conditions.join(' && ')}"
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
