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
          "require #{path_code}"
        end

        def emit_module_expr(args, env)
          emit_module_wrapper(args[0], emit_sequence(args[1..], env, :module, allow_method_definitions: true).first)
        end

        def emit_class_expr(args, env)
          name_sym, supers, body_forms = split_class_args(args)
          emit_class_wrapper(name_sym, supers, env,
                             emit_sequence(body_forms, env, :class, allow_method_definitions: true).first)
        end

        def emit_module_wrapper(name_sym, body)
          mod_var = temp('module')
          <<~RUBY.chomp
            (-> do
              #{mod_var} = #{runtime_call(:ensure_module, 'self', name_sym.name.inspect)}
              #{mod_var}.module_eval do
                #{indent(body)}
              end
              #{mod_var}
            end).call
          RUBY
        end

        def emit_class_wrapper(name_sym, supers, env, body)
          klass_var = temp('class')
          super_code =
            if supers.is_a?(Vec) && !supers.items.empty?
              emit_expr(supers.items.first, env, :toplevel)
            else
              'Object'
            end
          <<~RUBY.chomp
            (-> do
              #{klass_var} = #{runtime_call(:ensure_class, 'self', name_sym.name.inspect, super_code)}
              #{klass_var}.class_eval do
                #{indent(body)}
              end
              #{klass_var}
            end).call
          RUBY
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
            rescue_name = temp(sanitize_local(bind_sym.name))
            rescue_env.define(bind_sym.name, rescue_name)
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
          runtime_call(:call, callee_code, "[#{positional.join(', ')}]", kwargs, block)
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
            runtime_call(:send_call, receiver, method_name, positional, kwargs, block)
          end
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
          return env.lookup(name) if env.defined?(name)
          return emit_multisym_value(sym, env) if sym.dotted?
          return 'ARGV' if name == 'ARGV'
          return name if name.match?(/\A[A-Z]/)

          raise Error, "undefined symbol: #{name}"
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
            [env.lookup(segments[0]), segments[1..]]
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
          "(#{code})"
        end
      end
    end
  end
end
