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
          <<~RUBY.chomp
            (-> do
              #{acc_var} = #{emit_expr(bindings[1], env, current_scope)}
              #{iter_code}
              #{acc_var}
            end).call
          RUBY
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
          <<~RUBY.chomp
            (-> do
              #{acc_var} = #{emit_expr(bindings[1], env, current_scope)}
              #{indent(loop_code)}
              #{acc_var}
            end).call
          RUBY
        end

        def emit_hashfn(args, env, current_scope)
          args_var = temp('args')
          hash_env = env.child
          hash_env.define('$', "#{args_var}[0]")
          (1..9).each do |index|
            hash_env.define("$#{index}", "#{args_var}[#{index - 1}]")
          end
          hash_env.define('$...', args_var)
          body_code = emit_expr(args[0], hash_env, current_scope)
          <<~RUBY.chomp
            ->(*#{args_var}) do
              #{body_code}
            end
          RUBY
        end

        def emit_iteration(bindings_vec, env, current_scope)
          items = bindings_vec.items
          iter_expr = items.last
          binding_pats = items[0...-1]

          if iter_expr.is_a?(List) && iter_expr.head.is_a?(Sym)
            case iter_expr.head.name
            when 'ipairs'
              value_var = temp('value')
              index_var = temp('index')
              body_env = env.child
              bind_code, body_env = emit_iteration_bindings(
                [[binding_pats[0], index_var], [binding_pats[1], value_var]], body_env
              )
              body_code = yield(body_env)
              header = "#{emit_expr(iter_expr.items[1], env, current_scope)}" \
                       ".each_with_index do |#{value_var}, #{index_var}|"
              return iteration_block(header, bind_code, body_code)
            when 'pairs'
              key_var = temp('key')
              value_var = temp('value')
              body_env = env.child
              bind_code, body_env = emit_iteration_bindings([[binding_pats[0], key_var], [binding_pats[1], value_var]],
                                                            body_env)
              body_code = yield(body_env)
              header = "#{emit_expr(iter_expr.items[1], env, current_scope)}.each do |#{key_var}, #{value_var}|"
              return iteration_block(header, bind_code, body_code)
            end
          end

          coll_code = emit_expr(iter_expr, env, current_scope)
          if binding_pats.length == 1
            value_var = temp('value')
            body_env = env.child
            bind_code, body_env = emit_iteration_bindings([[binding_pats[0], value_var]], body_env)
            body_code = yield(body_env)
            iteration_block("#{coll_code}.each do |#{value_var}|", bind_code, body_code)
          else
            parts_var = temp('parts')
            body_env = env.child
            pairs = binding_pats.each_with_index.map { |pattern, i| [pattern, "#{parts_var}[#{i}]"] }
            bind_code, body_env = emit_iteration_bindings(pairs, body_env)
            body_code = yield(body_env)
            iteration_block("#{coll_code}.each do |*#{parts_var}|", bind_code, body_code)
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
          end.compact
          [codes.join("\n"), current_env]
        end

        def emit_collection_result(result_var, initial_code, iter_code)
          <<~RUBY.chomp
            (-> do
              #{result_var} = #{initial_code}
              #{indent(iter_code)}
              #{result_var}
            end).call
          RUBY
        end

        def emit_array_collection_step(result_var, body_code)
          value_var = temp('value')
          <<~RUBY.chomp
            #{emit_sequence_value_assignment(value_var, body_code)}
            #{result_var} << #{value_var} unless #{value_var}.nil?
          RUBY
        end

        def emit_hash_collection_step(result_var, body_code)
          pair_var = temp('pair')
          <<~RUBY.chomp
            #{emit_sequence_value_assignment(pair_var, body_code)}
            if #{pair_var}.is_a?(Array) && #{pair_var}.length == 2 && !#{pair_var}[0].nil? && !#{pair_var}[1].nil?
              #{result_var}[#{pair_var}[0]] = #{pair_var}[1]
            end
          RUBY
        end

        def emit_sequence_value_assignment(target_var, body_code)
          <<~RUBY.chomp
            #{target_var} = begin
            #{indent(body_code)}
            end
          RUBY
        end
      end
    end
  end
end
