# frozen_string_literal: true

module Kapusta
  module Compiler
    module EmitterModules
      module Collections
        private

        def emit_icollect(args, env, current_scope)
          result_var = temp('result')
          iter_code = emit_iteration(args[0], env, current_scope) do |iter_env|
            body = emit_sequence(args[1..], iter_env, current_scope, allow_method_definitions: false).first
            emit_array_collection_step(result_var, body)
          end
          emit_collection_result(result_var, '[]', iter_code)
        end

        def emit_collect(args, env, current_scope)
          result_var = temp('result')
          iter_code = emit_iteration(args[0], env, current_scope) do |iter_env|
            body = emit_sequence(args[1..], iter_env, current_scope, allow_method_definitions: false).first
            emit_hash_collection_step(result_var, body)
          end
          emit_collection_result(result_var, '{}', iter_code)
        end

        def emit_fcollect(args, env, current_scope)
          result_var = temp('result')
          parsed = parse_counted_for_bindings(args[0].items, env, current_scope)
          body_code, = emit_sequence(args[1..], parsed[:loop_env], current_scope, allow_method_definitions: false)
          collecting_body = emit_array_collection_step(result_var, body_code)
          loop_code = emit_counted_loop(**parsed, current_scope:, body_code: collecting_body)
          emit_collection_result(result_var, '[]', loop_code)
        end

        def emit_accumulate(args, env, current_scope)
          bindings = args[0].items
          acc_name = bindings[0]
          iter_bindings = Vec.new(bindings[2..])
          loop_env = env.child
          acc_var = define_local(loop_env, acc_name.name)
          iter_code = emit_iteration(iter_bindings, loop_env, current_scope) do |iter_env|
            iter_env.define(acc_name.name, acc_var)
            emit_sequence(args[1..], iter_env, current_scope, allow_method_definitions: false).first.then do |body|
              emit_sequence_value_assignment(acc_var, body)
            end
          end
          [
            '(-> do',
            indent("#{acc_var} = #{emit_expr(bindings[1], env, current_scope)}"),
            indent(iter_code),
            indent(acc_var),
            'end).call'
          ].join("\n")
        end

        def emit_faccumulate(args, env, current_scope)
          bindings = args[0].items
          acc_name = bindings[0]
          loop_name = bindings[2]
          loop_env = env.child
          acc_var = define_local(loop_env, acc_name.name)
          loop_var = define_local(loop_env, loop_name.name)
          body_code, = emit_sequence(args[1..], loop_env, current_scope, allow_method_definitions: false)
          accumulating_body = emit_sequence_value_assignment(acc_var, body_code)
          loop_code = emit_counted_loop(
            ruby_name: loop_var,
            start_code: emit_expr(bindings[3], env, current_scope),
            finish_code: emit_expr(bindings[4], env, current_scope),
            step_code: bindings[5] ? emit_expr(bindings[5], env, current_scope) : '1',
            until_form: nil,
            loop_env:,
            current_scope:,
            body_code: accumulating_body
          )
          [
            '(-> do',
            indent("#{acc_var} = #{emit_expr(bindings[1], env, current_scope)}"),
            indent(loop_code),
            indent(acc_var),
            'end).call'
          ].join("\n")
        end

        def emit_hashfn(args, env, current_scope)
          if needs_explicit_args?(args[0])
            args_var = temp('args')
            hash_env = env.child
            hash_env.define('$', "#{args_var}[0]")
            (1..9).each { |i| hash_env.define("$#{i}", "#{args_var}[#{i - 1}]") }
            hash_env.define('$...', args_var)
            body_code = emit_expr(args[0], hash_env, current_scope)
            ["->(*#{args_var}) do", indent(body_code), 'end'].join("\n")
          else
            hash_env = env.child
            hash_env.define('$', '_1')
            (1..9).each { |i| hash_env.define("$#{i}", "_#{i}") }
            body_code = emit_expr(args[0], hash_env, current_scope)
            ['proc do', indent(body_code), 'end'].join("\n")
          end
        end

        def needs_explicit_args?(form)
          case form
          when Sym then form.name == '$...'
          when List, Vec then form.items.any? { |item| needs_explicit_args?(item) }
          when HashLit
            form.entries.any? do |entry|
              entry.is_a?(Array) ? entry.any? { |item| needs_explicit_args?(item) } : needs_explicit_args?(entry)
            end
          else false
          end
        end

        def emit_iteration(bindings_vec, env, current_scope)
          items = bindings_vec.items
          iter_expr = items.last
          binding_pats = items[0...-1]

          if iter_expr.is_a?(List) && iter_expr.head.is_a?(Sym)
            case iter_expr.head.name
            when 'ipairs'
              body_env = env.child
              value_var, value_bind = bind_iteration_param(binding_pats[1], 'value', body_env)
              coll_code = emit_expr(iter_expr.items[1], env, current_scope)
              if ignored_pattern?(binding_pats[0])
                bind_code = value_bind || ''
                body_code = yield(body_env)
                return iteration_block("#{coll_code}.each do |#{value_var}|", bind_code, body_code)
              end
              index_var, index_bind = bind_iteration_param(binding_pats[0], 'index', body_env)
              bind_code = [index_bind, value_bind].compact.join("\n")
              body_code = yield(body_env)
              header = "#{coll_code}.each_with_index do |#{value_var}, #{index_var}|"
              return iteration_block(header, bind_code, body_code)
            when 'pairs'
              body_env = env.child
              key_var, key_bind = bind_iteration_param(binding_pats[0], 'key', body_env)
              value_var, value_bind = bind_iteration_param(binding_pats[1], 'value', body_env)
              bind_code = [key_bind, value_bind].compact.join("\n")
              body_code = yield(body_env)
              header = "#{emit_expr(iter_expr.items[1], env, current_scope)}.each do |#{key_var}, #{value_var}|"
              return iteration_block(header, bind_code, body_code)
            end
          end

          coll_code = emit_expr(iter_expr, env, current_scope)
          if binding_pats.length == 1
            body_env = env.child
            value_var, bind_code = bind_iteration_param(binding_pats[0], 'value', body_env)
            body_code = yield(body_env)
            iteration_block("#{coll_code}.each do |#{value_var}|", bind_code || '', body_code)
          else
            parts_var = temp('parts')
            body_env = env.child
            pairs = binding_pats.each_with_index.map { |pattern, i| [pattern, "#{parts_var}[#{i}]"] }
            bind_code, body_env = emit_iteration_bindings(pairs, body_env)
            body_code = yield(body_env)
            iteration_block("#{coll_code}.each do |*#{parts_var}|", bind_code, body_code)
          end
        end

        def ignored_pattern?(pattern)
          pattern.is_a?(Sym) && !pattern.dotted? && pattern.name == '_'
        end

        def bind_iteration_param(pattern, fallback_name, env)
          if pattern.is_a?(Sym) && !pattern.dotted?
            ruby_name = pattern.name == '_' ? '_' : define_local(env, pattern.name)
            [ruby_name, nil]
          else
            tmp = temp(fallback_name)
            bind_code, _new_env = emit_iteration_bindings([[pattern, tmp]], env)
            [tmp, bind_code.empty? ? nil : bind_code]
          end
        end

        def iteration_block(header, bind_code, body_code)
          [header, indent(join_code(bind_code, body_code)), 'end'].join("\n")
        end

        def emit_iteration_bindings(pairs, env)
          current_env = env
          codes = pairs.compact.map do |pattern, value_code|
            next nil unless pattern

            code, current_env = emit_pattern_bind(pattern, value_code, current_env)
            code
          end.compact.reject(&:empty?)
          [codes.join("\n"), current_env]
        end

        def emit_collection_result(result_var, initial_code, iter_code)
          [
            '(-> do',
            indent("#{result_var} = #{initial_code}"),
            indent(iter_code),
            indent(result_var),
            'end).call'
          ].join("\n")
        end

        def emit_array_collection_step(result_var, body_code)
          value_var = temp('value')
          [
            emit_sequence_value_assignment(value_var, body_code),
            "#{result_var} << #{value_var} unless #{value_var}.nil?"
          ].join("\n")
        end

        def emit_hash_collection_step(result_var, body_code)
          pair_var = temp('pair')
          [
            emit_sequence_value_assignment(pair_var, body_code),
            "if #{pair_var}.is_a?(Array) && #{pair_var}.length == 2 && " \
            "!#{pair_var}[0].nil? && !#{pair_var}[1].nil?",
            indent("#{result_var}[#{pair_var}[0]] = #{pair_var}[1]"),
            'end'
          ].join("\n")
        end

        def emit_sequence_value_assignment(target_var, body_code)
          return emit_assignment(target_var, body_code) unless body_code.include?("\n")

          ["#{target_var} = begin", indent(body_code), 'end'].join("\n")
        end
      end
    end
  end
end
