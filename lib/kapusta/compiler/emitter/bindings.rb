# frozen_string_literal: true

module Kapusta
  module Compiler
    module EmitterModules
      module Bindings
        private

        def emit_fn(args, env, current_scope)
          if args[0].is_a?(Vec)
            emit_lambda(args[0], args[1..], env, current_scope)
          else
            name_sym = args[0]
            pattern = args[1]
            body = args[2..]
            ruby_name = temp(sanitize_local(name_sym.name))
            fn_env = env.child
            fn_env.define(name_sym.name, ruby_name)
            <<~RUBY.chomp
              (-> do
                #{ruby_name} = nil
                #{ruby_name} = #{emit_lambda(pattern, body, fn_env, current_scope)}
                #{ruby_name}
              end).call
            RUBY
          end
        end

        def emit_lambda(pattern, body, env, current_scope)
          args_var = temp('args')
          body_env = env.child
          bindings_code, body_env = emit_pattern_bind(pattern, args_var, body_env)
          body_code, = emit_sequence(body, body_env, current_scope, allow_method_definitions: false)
          <<~RUBY.chomp
            ->(*#{args_var}) do
              #{bindings_code}
              #{body_code}
            end
          RUBY
        end

        def emit_named_fn_assignment(form, env, current_scope)
          name_sym = form.items[1]
          ruby_name = temp(sanitize_local(name_sym.name))
          env.define(name_sym.name, ruby_name)
          fn_env = env.child
          fn_env.define(name_sym.name, ruby_name)
          lambda_code = emit_lambda(form.items[2], form.items[3..], fn_env, current_scope)
          ["#{ruby_name} = nil\n#{ruby_name} = #{lambda_code}", env]
        end

        def emit_method_definition(form, env)
          name_sym = form.items[1]
          pattern = form.items[2]
          body = form.items[3..]
          method_env = env.child
          args_var = temp('args')
          bindings_code, body_env = emit_pattern_bind(pattern, args_var, method_env)
          body_code, = emit_sequence(body, body_env, :toplevel, allow_method_definitions: false)

          if name_sym.name.start_with?('self.')
            ruby_name = Kapusta.kebab_to_snake(name_sym.name.delete_prefix('self.')).to_sym.inspect
            <<~RUBY.chomp
              define_singleton_method(#{ruby_name}) do |*#{args_var}|
                #{bindings_code}
                #{body_code}
              end
            RUBY
          else
            ruby_name = Kapusta.kebab_to_snake(name_sym.name).to_sym.inspect
            <<~RUBY.chomp
              define_method(#{ruby_name}) do |*#{args_var}|
                #{bindings_code}
                #{body_code}
              end
            RUBY
          end
        end

        def emit_let(args, env, current_scope)
          bindings = args[0]
          body = args[1..]
          child_env = env.child
          binding_codes = []
          items = bindings.items
          i = 0
          while i < items.length
            pattern = items[i]
            value_code = emit_expr(items[i + 1], child_env, current_scope)
            bind_code, child_env = emit_pattern_bind(pattern, value_code, child_env)
            binding_codes << bind_code
            i += 2
          end
          body_code, = emit_sequence(body, child_env, current_scope, allow_method_definitions: false)
          <<~RUBY.chomp
            (-> do
              #{binding_codes.join("\n")}
              #{body_code}
            end).call
          RUBY
        end

        def emit_local_form(form, env, current_scope)
          target = form.items[1]
          value_code = emit_expr(form.items[2], env, current_scope)

          if target.is_a?(Sym)
            ruby_name = temp(sanitize_local(target.name))
            env.define(target.name, ruby_name)
            ["#{ruby_name} = #{value_code}\nnil", env]
          else
            bind_code, env = emit_pattern_bind(target, value_code, env)
            ["#{bind_code}\nnil", env]
          end
        end

        def emit_local_expr(args, env, current_scope)
          code, = emit_local_form(List.new([Sym.new('local'), *args]), env.child, current_scope)
          "(-> do\n#{indent(code)}\nend).call"
        end

        def emit_set_form(form, env, current_scope)
          target = form.items[1]
          value_code = emit_expr(form.items[2], env, current_scope)

          if target.is_a?(Sym) && !target.dotted?
            ruby_name =
              if env.defined?(target.name)
                env.lookup(target.name)
              else
                fresh = temp(sanitize_local(target.name))
                env.define(target.name, fresh)
                fresh
              end
            ["#{ruby_name} = #{value_code}", env]
          else
            [emit_set_target(target, value_code, env, current_scope), env]
          end
        end

        def emit_set_expr(args, env, current_scope)
          target = args[0]
          value_code = emit_expr(args[1], env, current_scope)
          emit_set_target(target, value_code, env, current_scope)
        end

        def emit_set_target(target, value_code, env, current_scope)
          case target
          when Sym
            if target.dotted?
              base_code, segments = multisym_base(target.segments, env)
              runtime_call(:set_method_path, base_code, segments.inspect, value_code)
            else
              "#{env.lookup(target.name)} = #{value_code}"
            end
          when List
            head = target.head
            if head.is_a?(Sym) && head.name == '.'
              object_code = emit_expr(target.items[1], env, current_scope)
              keys_code = "[#{target.items[2..].map { |item| emit_expr(item, env, current_scope) }.join(', ')}]"
              runtime_call(:set_path, object_code, keys_code, value_code)
            elsif head.is_a?(Sym) && head.name == 'ivar'
              runtime_call(:set_ivar, 'self', target.items[1].name.inspect, value_code)
            elsif head.is_a?(Sym) && head.name == 'cvar'
              runtime_call(:set_cvar, 'self', target.items[1].name.inspect, value_code)
            elsif head.is_a?(Sym) && head.name == 'gvar'
              runtime_call(:set_gvar, target.items[1].name.inspect, value_code)
            else
              raise Error, "bad set target: #{target.inspect}"
            end
          else
            raise Error, "bad set target: #{target.inspect}"
          end
        end
      end
    end
  end
end
