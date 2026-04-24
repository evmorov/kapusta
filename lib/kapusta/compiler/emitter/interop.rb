# frozen_string_literal: true

module Kapusta
  module Compiler
    module EmitterModules
      module Interop
        private

        def emit_lookup(args, env, current_scope)
          object_code = emit_expr(args[0], env, current_scope)
          keys = args[1..].map { |arg| emit_expr(arg, env, current_scope) }.join(', ')
          runtime_call(:get_path, object_code, "[#{keys}]")
        end

        def emit_safe_lookup(args, env, current_scope)
          object_code = emit_expr(args[0], env, current_scope)
          keys = args[1..].map { |arg| emit_expr(arg, env, current_scope) }.join(', ')
          runtime_call(:qget_path, object_code, "[#{keys}]")
        end

        def emit_colon(args, env, current_scope)
          receiver = emit_expr(args[0], env, current_scope)
          method_name = emit_method_name(args[1], env, current_scope)
          positional, kwargs, block = split_call_args(args[2..], env, current_scope)
          runtime_call(:send_call, receiver, method_name, positional, kwargs, block)
        end

        def emit_require(arg, env, current_scope)
          path_code =
            case arg
            when Sym then arg.name.inspect
            when Symbol then arg.to_s.inspect
            when String then arg.inspect
            else "(#{emit_expr(arg, env, current_scope)}).to_s"
            end
          if kapusta_require?(arg)
            return [
              'unless defined?(Kapusta)',
              indent('require "kapusta"'),
              'end',
              "Kapusta.require(#{path_code}, relative_to: #{@path.inspect})"
            ].join("\n")
          end

          "require #{path_code}"
        end

        def kapusta_require?(arg)
          path =
            case arg
            when Sym then arg.name
            when Symbol then arg.to_s
            when String then arg
            end
          return false unless path

          path.end_with?('.kap') || path.start_with?('./', '../') || File.absolute_path?(path)
        end

        def emit_module_expr(args, env)
          body = emit_sequence(args[1..], env, :module, allow_method_definitions: true, result: false).first
          emit_module_wrapper(args[0], body)
        end

        def emit_class_expr(args, env)
          name_sym, supers, body_forms = split_class_args(args)
          body = emit_sequence(body_forms, env, :class, allow_method_definitions: true, result: false).first
          emit_class_wrapper(name_sym, supers, env,
                             body)
        end

        def emit_module_wrapper(name_sym, body)
          mod_var = temp('module')
          [
            '(-> do',
            indent("#{mod_var} = #{runtime_call(:ensure_module, 'self', name_sym.name.inspect)}"),
            indent("#{mod_var}.module_eval do"),
            indent(body, 2),
            indent('end'),
            indent(mod_var),
            'end).call'
          ].join("\n")
        end

        def emit_direct_module_header(name_sym, body)
          const_name = simple_constant_name(name_sym)
          return unless const_name

          [
            "module #{const_name}",
            indent(body),
            'end',
            const_name
          ].join("\n")
        end

        def emit_class_wrapper(name_sym, supers, env, body)
          klass_var = temp('class')
          super_code =
            if supers.is_a?(Vec) && !supers.items.empty?
              emit_expr(supers.items.first, env, :toplevel)
            else
              'Object'
            end
          [
            '(-> do',
            indent("#{klass_var} = #{runtime_call(:ensure_class, 'self', name_sym.name.inspect, super_code)}"),
            indent("#{klass_var}.class_eval do"),
            indent(body, 2),
            indent('end'),
            indent(klass_var),
            'end).call'
          ].join("\n")
        end

        def emit_direct_class_header(name_sym, supers, body)
          const_name = simple_constant_name(name_sym)
          return unless const_name && supers.nil?

          [
            "class #{const_name}",
            indent(body),
            'end',
            const_name
          ].join("\n")
        end

        def simple_constant_name(name_sym)
          return unless name_sym.is_a?(Sym) && name_sym.name.match?(/\A[A-Z]\w*\z/)

          name_sym.name
        end

        def emit_try(args, env, current_scope)
          catches = []
          finally_bodies = []
          args[1..].each do |clause|
            head = clause.head
            if head.is_a?(Sym) && head.name == 'catch'
              rest = clause.items[1..]
              if rest[0].is_a?(Sym) && (rest[0].name.match?(/\A[A-Z]/) || rest[0].dotted?)
                klass_form = rest[0]
                bind_sym = rest[1]
                body = rest[2..]
              else
                klass_form = nil
                bind_sym = rest[0]
                body = rest[1..]
              end
              catches << [klass_form, bind_sym, body]
            elsif head.is_a?(Sym) && head.name == 'finally'
              finally_bodies << clause.items[1..]
            end
          end

          lines = ['begin', indent(emit_expr(args[0], env, current_scope))]
          catches.each do |klass_form, bind_sym, body|
            rescue_env = env.child
            rescue_name = define_local(rescue_env, bind_sym.name)
            body_code, = emit_sequence(body, rescue_env, current_scope, allow_method_definitions: false)
            rescue_line =
              if klass_form
                "rescue #{emit_expr(klass_form, env, current_scope)} => #{rescue_name}"
              else
                "rescue StandardError => #{rescue_name}"
              end
            lines << rescue_line
            lines << indent(body_code)
          end
          unless finally_bodies.empty?
            ensure_code = finally_bodies.map do |body|
              emit_sequence(body, env, current_scope, allow_method_definitions: false).first
            end.join("\n")
            lines << 'ensure'
            lines << indent(ensure_code)
          end
          lines << 'end'
          lines.join("\n")
        end

        def emit_raise(args, env, current_scope)
          return 'Kernel.raise' if args.empty?

          "Kernel.raise(#{args.map { |arg| emit_expr(arg, env, current_scope) }.join(', ')})"
        end

        def emit_and(args, env, current_scope)
          return 'true' if args.empty?

          args.map { |arg| parenthesize(emit_expr(arg, env, current_scope)) }.join(' && ')
        end

        def emit_or(args, env, current_scope)
          return 'nil' if args.empty?

          args.map { |arg| parenthesize(emit_expr(arg, env, current_scope)) }.join(' || ')
        end

        def emit_compare(args, env, current_scope, operator)
          values = args.map { |arg| emit_expr(arg, env, current_scope) }
          return 'true' if values.length <= 1

          (0...(values.length - 1)).map do |i|
            "#{parenthesize(values[i])} #{operator} #{parenthesize(values[i + 1])}"
          end.join(' && ')
        end

        def emit_reduce(args, env, current_scope, empty_value, operator)
          return empty_value if args.empty?

          args.map { |arg| parenthesize(emit_expr(arg, env, current_scope)) }.join(" #{operator} ")
        end

        def emit_minus(args, env, current_scope)
          values = args.map { |arg| emit_expr(arg, env, current_scope) }
          return '0' if values.empty?
          return "(-#{values[0]})" if values.length == 1

          values.map { |value| parenthesize(value) }.join(' - ')
        end

        def emit_div(args, env, current_scope)
          values = args.map { |arg| emit_expr(arg, env, current_scope) }
          return "(1.0 / #{parenthesize(values[0])})" if values.length == 1

          values.map { |value| parenthesize(value) }.join(' / ')
        end

        def emit_callable_call(callee_code, args, env, current_scope)
          positional, kwargs, block = split_call_args(args, env, current_scope)
          return emit_direct_callable_call(callee_code, positional) unless kwargs || block

          runtime_call(:call, callee_code, "[#{positional.join(', ')}]", kwargs, block)
        end

        def emit_bound_call(binding, args, env, current_scope)
          return emit_self_method_binding_call(binding, args, env, current_scope) if method_binding?(binding)

          emit_callable_call(binding, args, env, current_scope)
        end

        def emit_self_method_binding_call(binding, args, env, current_scope)
          positional = args.map { |arg| emit_expr(arg, env, current_scope) }
          emit_direct_self_method_call(binding.ruby_name, positional)
        end

        def emit_direct_self_method_call(method_name, positional)
          args = positional.join(', ')
          args.empty? ? "#{method_name}()" : "#{method_name}(#{args})"
        end

        def emit_direct_callable_call(callee_code, positional)
          rendered_args = positional.join(', ')
          suffix = rendered_args.empty? ? '.call' : ".call(#{rendered_args})"
          "#{parenthesize(callee_code)}#{suffix}"
        end

        def emit_multisym_call(head, args, env, current_scope)
          base_code, segments = multisym_base(head.segments, env)
          if segments.empty?
            emit_callable_call(base_code, args, env, current_scope)
          else
            receiver =
              if segments.length == 1
                base_code
              else
                runtime_call(:method_path_value, base_code, segments[0...-1].inspect)
              end
            method_name = Kapusta.kebab_to_snake(segments.last).to_sym.inspect
            positional, kwargs, block = split_call_args(args, env, current_scope)
            if segments.length == 1 && !kwargs && !block && direct_method_name?(segments.last)
              return emit_direct_method_call(receiver, Kapusta.kebab_to_snake(segments.last), positional)
            end

            runtime_call(:send_call, receiver, method_name, positional, kwargs, block)
          end
        end

        def emit_direct_method_call(receiver, method_name, positional)
          args = positional.join(', ')
          rendered_receiver = simple_expression?(receiver) ? receiver : parenthesize(receiver)
          suffix = args.empty? ? method_name : "#{method_name}(#{args})"
          "#{rendered_receiver}.#{suffix}"
        end

        def emit_self_call(name, args, env, current_scope)
          positional, kwargs, block = split_call_args(args, env, current_scope)
          method_name = Kapusta.kebab_to_snake(name).to_sym.inspect
          runtime_call(:invoke_self, 'self', method_name, positional, kwargs, block)
        end

        def split_call_args(args, env, current_scope)
          block = nil
          remaining = args
          if !remaining.empty? && block_form?(remaining.last)
            block = emit_expr(remaining.last, env, current_scope)
            remaining = remaining[0...-1]
          end

          if !remaining.empty? && remaining.last.is_a?(HashLit) && remaining.last.all_sym_keys?
            kwargs = emit_expr(remaining.last, env, current_scope)
            positional = remaining[0...-1].map { |arg| emit_expr(arg, env, current_scope) }
          else
            kwargs = nil
            positional = remaining.map { |arg| emit_expr(arg, env, current_scope) }
          end
          [positional, kwargs, block]
        end

        def emit_method_name(form, env, current_scope)
          if form.is_a?(Symbol)
            form.inspect
          elsif form.is_a?(String)
            form.to_sym.inspect
          else
            value = emit_expr(form, env, current_scope)
            "(#{value}.is_a?(Symbol) ? #{value} : #{value}.to_s.to_sym)"
          end
        end

        def emit_sym(sym, env)
          name = sym.name
          return 'self' if name == 'self'
          return 'Float::INFINITY' if name == 'math.huge'
          return binding_value_code(env.lookup(sym)) if env.defined?(sym)
          return emit_multisym_value(sym, env) if sym.dotted?
          return 'ARGV' if name == 'ARGV'
          return name if name.match?(/\A[A-Z]/)

          raise Error, "undefined symbol: #{name}"
        end

        def emit_gvar(sym)
          ruby_name = global_name(sym.name)
          return "$#{ruby_name}" if direct_global_name?(ruby_name)

          runtime_call(:get_gvar, sym.name.inspect)
        end

        def emit_multisym_value(sym, env)
          base_code, segments = multisym_base(sym.segments, env)
          return base_code if segments.empty?

          runtime_call(:method_path_value, base_code, segments.inspect)
        end

        def multisym_base(segments, env)
          if segments[0] == 'self'
            ['self', segments[1..]]
          elsif env.defined?(segments[0])
            [binding_value_code(env.lookup(segments[0])), segments[1..]]
          else
            idx = 0
            const_path = []
            while idx < segments.length && segments[idx].match?(/\A[A-Z]/)
              const_path << segments[idx]
              idx += 1
            end
            raise Error, "bad multisym: #{segments.join('.')}" if const_path.empty?

            [const_path.join('::'), segments[idx..]]
          end
        end

        def parenthesize(code)
          return code if simple_expression?(code)

          "(#{code})"
        end

        def direct_method_name?(name)
          Kapusta.kebab_to_snake(name).match?(/\A[a-z_]\w*[!?=]?\z/)
        end

        def direct_global_name?(name)
          name.match?(/\A[a-z_]\w*\z/)
        end

        def global_name(name)
          Kapusta.kebab_to_snake(name).gsub(/[^a-zA-Z0-9_]/, '_')
        end

        def simple_expression?(code)
          code.match?(/\A[a-z_]\w*\z/) ||
            code.match?(/\A[A-Z]\w*(?:::[A-Z]\w*)*\z/) ||
            code.match?(/\A[a-z_]\w*[!?=]?\([^()\n]*\)\z/) ||
            code.match?(/\A\d+(?:\.\d+)?\z/) ||
            code.match?(/\A[a-z_]\w*(?:\.[a-z_]\w*[!?=]?(?:\([^()\n]*\))?)+\z/) ||
            code.match?(/\A:[a-zA-Z_]\w*[!?=]?\z/) ||
            code.match?(/\A"(?:[^"\\]|\\.)*"\z/) ||
            code.match?(/\A'(?:[^'\\]|\\.)*'\z/) ||
            %w[nil true false self].include?(code)
        end
      end
    end
  end
end
