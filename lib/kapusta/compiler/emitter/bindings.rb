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
            fn_env = env.child
            ruby_name = define_local(fn_env, name_sym.name)
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
          return emit_simple_lambda(pattern, body, env, current_scope) if simple_parameter_pattern?(pattern)

          args_var = temp('args')
          body_env = env.child
          bindings_code, body_env = emit_pattern_bind(pattern, args_var, body_env)
          body_code, = emit_sequence(body, body_env, current_scope, allow_method_definitions: false)
          block_locals = pattern_names(pattern).map { |name| body_env.lookup(name) }.uniq
          block_locals_clause = block_locals.empty? ? '' : "; #{block_locals.join(', ')}"
          [
            "->(*#{args_var}#{block_locals_clause}) do",
            indent(join_code(bindings_code, body_code)),
            'end'
          ].join("\n")
        end

        def emit_simple_lambda(pattern, body, env, current_scope)
          params, body_code = build_simple_block_parts(pattern, body, env, current_scope)
          header = params.empty? ? 'proc do' : "proc do |#{params.join(', ')}|"
          [
            header,
            indent(body_code),
            'end'
          ].join("\n")
        end

        def build_simple_block_parts(pattern, body, env, current_scope)
          body_env = env.child
          params = pattern.items.map { |sym| define_local(body_env, sym.name, shadow: true) }
          body_code, = emit_sequence(body, body_env, current_scope, allow_method_definitions: false)
          [params, body_code]
        end

        def simple_parameter_pattern?(pattern)
          pattern.is_a?(Vec) && pattern.items.all? { |item| item.is_a?(Sym) && !item.dotted? && item.name != '&' }
        end

        def emit_definition_form(form, env, current_scope)
          return [emit_method_definition(form, env), env] unless current_scope == :toplevel

          emit_toplevel_method_definition(form, env)
        end

        def emit_toplevel_method_definition(form, env)
          name_sym = form.items[1]
          pattern = form.items[2]
          body = form.items[3..]
          return [nil, env] if name_sym.dotted?
          return [nil, env] unless simple_parameter_pattern?(pattern)

          ruby_name = direct_method_definition_name(name_sym)
          return [nil, env] unless ruby_name
          return [nil, env] if captures_outer_binding?(body, env, pattern_names(pattern))

          env.define(name_sym.name, Env::MethodBinding.new(ruby_name))
          definition = emit_direct_method_definition(name_sym, pattern, body, env)
          if needs_toplevel_method_bridge?(ruby_name)
            definition = join_code(definition, emit_toplevel_method_bridge(ruby_name))
          end
          [definition, env]
        end

        def emit_named_fn_assignment(form, env, current_scope)
          name_sym = form.items[1]
          ruby_name = define_local(env, name_sym.name)
          fn_env = env.child
          fn_env.define(name_sym.name, ruby_name)
          lambda_code = emit_lambda(form.items[2], form.items[3..], fn_env, current_scope)
          ["#{ruby_name} = nil\n#{ruby_name} = #{lambda_code}", env]
        end

        def emit_method_definition(form, env)
          name_sym = form.items[1]
          pattern = form.items[2]
          body = form.items[3..]
          direct_definition = emit_direct_method_definition(name_sym, pattern, body, env)
          return direct_definition if direct_definition

          block_header, body_code = emit_method_body(pattern, body, env)

          if name_sym.name.start_with?('self.')
            ruby_name = Kapusta.kebab_to_snake(name_sym.name.delete_prefix('self.')).to_sym.inspect
            [
              "define_singleton_method(#{ruby_name}) #{block_header}",
              indent(body_code),
              'end'
            ].join("\n")
          else
            ruby_name = Kapusta.kebab_to_snake(name_sym.name).to_sym.inspect
            [
              "define_method(#{ruby_name}) #{block_header}",
              indent(body_code),
              'end'
            ].join("\n")
          end
        end

        def emit_direct_method_definition(name_sym, pattern, body, env)
          return unless simple_parameter_pattern?(pattern)

          ruby_name = direct_method_definition_name(name_sym)
          return unless ruby_name
          return if captures_outer_binding?(body, env, pattern_names(pattern))

          body_env = env.child
          params = pattern.items.map { |sym| define_local(body_env, sym.name, shadow: true) }
          body_code, = emit_sequence(body, body_env, :toplevel, allow_method_definitions: false)
          header = params.empty? ? "def #{ruby_name}" : "def #{ruby_name}(#{params.join(', ')})"
          [
            header,
            indent(body_code),
            'end'
          ].join("\n")
        end

        def direct_method_definition_name(name_sym)
          source_name = name_sym.name
          if source_name.start_with?('self.')
            method_name = Kapusta.kebab_to_snake(source_name.delete_prefix('self.'))
            return unless direct_method_name?(method_name)

            "self.#{method_name}"
          else
            method_name = Kapusta.kebab_to_snake(source_name)
            return unless direct_method_name?(method_name)

            method_name
          end
        end

        def needs_toplevel_method_bridge?(ruby_name)
          %w[context describe example it specify].include?(ruby_name)
        end

        def emit_toplevel_method_bridge(ruby_name)
          method_name = ruby_name.to_sym.inspect
          "define_singleton_method(#{method_name}, Object.instance_method(#{method_name}).bind(self))"
        end

        def emit_method_body(pattern, body, env)
          return emit_simple_method_body(pattern, body, env) if simple_parameter_pattern?(pattern)

          args_var = temp('args')
          method_env = env.child
          bindings_code, body_env = emit_pattern_bind(pattern, args_var, method_env)
          body_code, = emit_sequence(body, body_env, :toplevel, allow_method_definitions: false)
          block_locals = pattern_names(pattern).map { |name| body_env.lookup(name) }.uniq
          block_locals_clause = block_locals.empty? ? '' : "; #{block_locals.join(', ')}"
          ["do |*#{args_var}#{block_locals_clause}|", join_code(bindings_code, body_code)]
        end

        def emit_simple_method_body(pattern, body, env)
          params, body_code = build_simple_block_parts(pattern, body, env, :toplevel)
          [params.empty? ? 'do' : "do |#{params.join(', ')}|", body_code]
        end

        def captures_outer_binding?(forms, env, local_names)
          forms.any? { |form| form_captures_outer_binding?(form, env, local_names) }
        end

        def form_captures_outer_binding?(form, env, local_names)
          case form
          when Sym
            sym_captures_outer_binding?(form, env, local_names)
          when Vec, List
            form.items.any? { |item| form_captures_outer_binding?(item, env, local_names) }
          when HashLit
            form.pairs.any? do |key, value|
              form_captures_outer_binding?(key, env, local_names) ||
                form_captures_outer_binding?(value, env, local_names)
            end
          else
            false
          end
        end

        def sym_captures_outer_binding?(sym, env, local_names)
          name = sym.dotted? ? sym.segments.first : sym.name
          return false if local_names.include?(name)

          binding = env.lookup_if_defined(name)
          return false if binding.nil?

          !method_binding?(binding)
        end

        def emit_let(args, env, current_scope)
          binding_code, body_code = emit_let_parts(args, env, current_scope, result: true)
          <<~RUBY.chomp
            (-> do
              #{indent(join_code(binding_code, body_code))}
            end).call
          RUBY
        end

        def emit_let_statement(args, env, current_scope)
          binding_code, body_code = emit_let_parts(args, env, current_scope, result: false)
          join_code(binding_code, body_code)
        end

        def emit_let_parts(args, env, current_scope, result:)
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
          body_code, = emit_sequence(body, child_env, current_scope,
                                     allow_method_definitions: false,
                                     result:)
          [binding_codes.join("\n"), body_code]
        end

        def join_code(*chunks)
          chunks.reject(&:empty?).join("\n")
        end

        def emit_local_form(form, env, current_scope)
          target = form.items[1]
          value_code = emit_expr(form.items[2], env, current_scope)

          if target.is_a?(Sym)
            ruby_name = define_local(env, target.name)
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
            binding = env.lookup_if_defined(target.name)
            ruby_name =
              if binding
                emit_error!("cannot set method binding: #{target.name}") if method_binding?(binding)

                binding
              else
                define_local(env, target.name)
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
              binding = env.lookup(target.name)
              emit_error!("cannot set method binding: #{target.name}") if method_binding?(binding)

              "#{binding} = #{value_code}"
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
              ruby_name = global_name(target.items[1].name)
              if direct_global_name?(ruby_name)
                "$#{ruby_name} = #{value_code}"
              else
                runtime_call(:set_gvar, target.items[1].name.inspect, value_code)
              end
            else
              emit_error!("bad set target: #{target.inspect}")
            end
          else
            emit_error!("bad set target: #{target.inspect}")
          end
        end
      end
    end
  end
end
