# frozen_string_literal: true

module Kapusta
  module Compiler
    module EmitterModules
      module Collections
        include LuaCompat::Emission

        private

        def emit_icollect(args, env, current_scope)
          emit_error!(:icollect_no_iterator) unless args[0].is_a?(Vec) && args[0].items.length >= 2

          emit_iteration(args[0], env, current_scope, method: 'filter_map') do |iter_env|
            emit_sequence(args[1..], iter_env, current_scope, allow_method_definitions: false).first
          end
        end

        def emit_collect(args, env, current_scope)
          result_var = temp('result')
          values_form = simple_values_call(args[1]) if args.length == 2
          emit_iteration(args[0], env, current_scope,
                         method: 'each_with_object({})', extra_block_param: result_var) do |iter_env|
            if values_form
              emit_collect_values_step(result_var, values_form, iter_env, current_scope)
            else
              body = emit_sequence(args[1..], iter_env, current_scope, allow_method_definitions: false).first
              emit_hash_collection_step(result_var, body)
            end
          end
        end

        def simple_values_call(form)
          return unless form.is_a?(List) && form.items.length == 3

          head = form.head
          form if head.is_a?(Sym) && head.name == 'values'
        end

        def emit_collect_values_step(result_var, values_form, iter_env, current_scope)
          key_form = values_form.items[1]
          val_form = values_form.items[2]
          key_code = emit_expr(key_form, iter_env, current_scope)
          val_code = emit_expr(val_form, iter_env, current_scope)
          assignment = "#{result_var}[#{key_code}] = #{val_code}"
          guards = []
          guards << "#{key_code}.nil?" unless definitely_non_nil?(key_form)
          guards << "#{val_code}.nil?" unless definitely_non_nil?(val_form)
          return assignment if guards.empty?

          "#{assignment} unless #{guards.join(' || ')}"
        end

        def definitely_non_nil?(form)
          case form
          when Numeric, String, ::Symbol, TrueClass, FalseClass then true
          else false
          end
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
          emit_error!(:accumulate_no_iterator) if bindings.length < 4

          acc_name = bindings[0]
          init_code = emit_expr(bindings[1], env, current_scope)
          iter_items = bindings[2..]
          iter_expr = iter_items.last
          binding_pats = iter_items[0...-1]

          body_env = env.child
          acc_var = define_local(body_env, acc_name.name)

          inject_code = try_emit_inject(iter_expr, binding_pats, body_env, env, current_scope, acc_var,
                                        init_code, args[1..])
          return inject_code if inject_code

          iter_code = emit_iteration(Vec.new(iter_items), body_env, current_scope) do |iter_env|
            body_code, = emit_sequence(args[1..], iter_env, current_scope, allow_method_definitions: false)
            emit_sequence_value_assignment(acc_var, body_code)
          end
          [
            '(-> do',
            indent("#{acc_var} = #{init_code}"),
            indent(iter_code),
            indent(acc_var),
            'end).call'
          ].join("\n")
        end

        def try_emit_inject(iter_expr, binding_pats, body_env, env, current_scope, acc_var, init_code, body_forms)
          emit_lua_compat_inject(iter_expr, binding_pats, body_env, env, current_scope, acc_var,
                                 init_code, body_forms)
        end

        def inject_block(receiver, params, init_code, bind_code, body_code)
          inner = join_code(bind_code, body_code)
          ["#{receiver}.inject(#{init_code}) do |#{params}|", indent(inner), 'end'].join("\n")
        end

        def emit_faccumulate(args, env, current_scope)
          bindings = args[0].items
          emit_error!(:accumulate_no_iterator) if bindings.length < 5

          body_env = env.child
          acc_var = define_local(body_env, bindings[0].name)
          loop_var = define_local(body_env, bindings[2].name)

          init_code = emit_expr(bindings[1], env, current_scope)
          start_code = emit_expr(bindings[3], env, current_scope)
          finish_code = emit_expr(bindings[4], env, current_scope)
          step_code = bindings[5] ? emit_expr(bindings[5], env, current_scope) : nil
          body_code, = emit_sequence(args[1..], body_env, current_scope, allow_method_definitions: false)

          receiver =
            if step_code
              "#{parenthesize(start_code)}.step(#{finish_code}, #{step_code})"
            else
              "(#{start_code}..#{finish_code})"
            end
          inject_block(receiver, "#{acc_var}, #{loop_var}", init_code, '', body_code)
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

        def emit_iteration(bindings_vec, env, current_scope, method: 'each', extra_block_param: nil, &block)
          emit_error!(:each_no_binding) unless bindings_vec.is_a?(Vec)

          items = bindings_vec.items
          iter_expr = items.last
          binding_pats = items[0...-1]

          lua_iteration = emit_lua_compat_iteration(iter_expr, binding_pats, env, current_scope,
                                                    method:, extra_block_param:, &block)
          return lua_iteration if lua_iteration

          coll_code = emit_expr(iter_expr, env, current_scope)
          if binding_pats.length == 1
            body_env = env.child
            value_var, bind_code = bind_iteration_param(binding_pats[0], 'value', body_env)
            body_code = block.call(body_env)
            params = extra_block_param ? "#{value_var}, #{extra_block_param}" : value_var
            iteration_block("#{coll_code}.#{method} do |#{params}|", bind_code || '', body_code)
          else
            parts_var = temp('parts')
            body_env = env.child
            pairs = binding_pats.each_with_index.map { |pattern, i| [pattern, "#{parts_var}[#{i}]"] }
            bind_code, body_env = emit_iteration_bindings(pairs, body_env)
            body_code = block.call(body_env)
            params = extra_block_param ? "#{parts_var}, #{extra_block_param}" : "*#{parts_var}"
            iteration_block("#{coll_code}.#{method} do |#{params}|", bind_code, body_code)
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
