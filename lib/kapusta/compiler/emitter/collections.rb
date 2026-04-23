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
            <<~RUBY.chomp
              __kap_value = begin
              #{indent(body)}
              end
              #{result_var} << __kap_value unless __kap_value.nil?
            RUBY
          end
          <<~RUBY.chomp
            (-> do
              #{result_var} = []
              #{iter_code}
              #{result_var}
            end).call
          RUBY
        end

        def emit_collect(args, env, current_scope)
          result_var = temp('result')
          iter_code = emit_iteration(args[0], env, current_scope) do |iter_env|
            body = emit_sequence(args[1..], iter_env, current_scope, allow_method_definitions: false).first
            <<~RUBY.chomp
              __kap_pair = begin
              #{indent(body)}
              end
              if __kap_pair.is_a?(Array) && __kap_pair.length == 2 && !__kap_pair[0].nil? && !__kap_pair[1].nil?
                #{result_var}[__kap_pair[0]] = __kap_pair[1]
              end
            RUBY
          end
          <<~RUBY.chomp
            (-> do
              #{result_var} = {}
              #{iter_code}
              #{result_var}
            end).call
          RUBY
        end

        def emit_fcollect(args, env, current_scope)
          result_var = temp('result')
          bindings = args[0].items
          ruby_name = temp(sanitize_local(bindings[0].name))
          loop_env = env.child
          loop_env.define(bindings[0].name, ruby_name)
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
          body_code, = emit_sequence(args[1..], loop_env, current_scope, allow_method_definitions: false)
          until_code = until_form ? "break if #{emit_expr(until_form, loop_env, current_scope)}" : nil
          finish_var = temp('finish')
          step_var = temp('step')
          cmp_var = temp('cmp')
          <<~RUBY.chomp
            (-> do
              #{result_var} = []
              #{ruby_name} = #{start_code}
              #{finish_var} = #{finish_code}
              #{step_var} = #{step_code}
              #{cmp_var} = #{step_var} >= 0 ? :<= : :>=
              while #{ruby_name}.public_send(#{cmp_var}, #{finish_var})
                #{until_code}
                __kap_value = begin
                #{indent(body_code)}
                end
                #{result_var} << __kap_value unless __kap_value.nil?
                #{ruby_name} += #{step_var}
              end
              #{result_var}
            end).call
          RUBY
        end

        def emit_accumulate(args, env, current_scope)
          bindings = args[0].items
          acc_name = bindings[0]
          acc_var = temp(sanitize_local(acc_name.name))
          iter_bindings = Vec.new(bindings[2..])
          loop_env = env.child
          loop_env.define(acc_name.name, acc_var)
          iter_code = emit_iteration(iter_bindings, loop_env, current_scope) do |iter_env|
            iter_env.define(acc_name.name, acc_var)
            emit_sequence(args[1..], iter_env, current_scope, allow_method_definitions: false).first.then do |body|
              "#{acc_var} = begin\n#{indent(body)}\nend"
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
          acc_var = temp(sanitize_local(acc_name.name))
          loop_name = bindings[2]
          loop_var = temp(sanitize_local(loop_name.name))
          loop_env = env.child
          loop_env.define(acc_name.name, acc_var)
          loop_env.define(loop_name.name, loop_var)
          start_code = emit_expr(bindings[3], env, current_scope)
          finish_code = emit_expr(bindings[4], env, current_scope)
          step_code = bindings[5] ? emit_expr(bindings[5], env, current_scope) : '1'
          body_code, = emit_sequence(args[1..], loop_env, current_scope, allow_method_definitions: false)
          finish_var = temp('finish')
          step_var = temp('step')
          cmp_var = temp('cmp')
          <<~RUBY.chomp
            (-> do
              #{acc_var} = #{emit_expr(bindings[1], env, current_scope)}
              #{loop_var} = #{start_code}
              #{finish_var} = #{finish_code}
              #{step_var} = #{step_code}
              #{cmp_var} = #{step_var} >= 0 ? :<= : :>=
              while #{loop_var}.public_send(#{cmp_var}, #{finish_var})
                #{acc_var} = begin
                #{indent(body_code)}
                end
                #{loop_var} += #{step_var}
              end
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
              return <<~RUBY.chomp
                #{emit_expr(iter_expr.items[1], env, current_scope)}.each_with_index do |#{value_var}, #{index_var}|
                  #{bind_code}
                  #{body_code}
                end
              RUBY
            when 'pairs'
              key_var = temp('key')
              value_var = temp('value')
              body_env = env.child
              bind_code, body_env = emit_iteration_bindings([[binding_pats[0], key_var], [binding_pats[1], value_var]],
                                                            body_env)
              body_code = yield(body_env)
              return <<~RUBY.chomp
                #{emit_expr(iter_expr.items[1], env, current_scope)}.each do |#{key_var}, #{value_var}|
                  #{bind_code}
                  #{body_code}
                end
              RUBY
            end
          end

          coll_code = emit_expr(iter_expr, env, current_scope)
          if binding_pats.length == 1
            value_var = temp('value')
            body_env = env.child
            bind_code, body_env = emit_iteration_bindings([[binding_pats[0], value_var]], body_env)
            body_code = yield(body_env)
            <<~RUBY.chomp
              #{coll_code}.each do |#{value_var}|
                #{bind_code}
                #{body_code}
              end
            RUBY
          else
            parts_var = temp('parts')
            body_env = env.child
            pairs = binding_pats.each_with_index.map { |pattern, i| [pattern, "#{parts_var}[#{i}]"] }
            bind_code, body_env = emit_iteration_bindings(pairs, body_env)
            body_code = yield(body_env)
            <<~RUBY.chomp
              #{coll_code}.each do |*#{parts_var}|
                #{bind_code}
                #{body_code}
              end
            RUBY
          end
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
      end
    end
  end
end
