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
            emit_error!(:fn_no_params) unless name_sym.is_a?(Sym) && pattern.is_a?(Vec)

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
          validate_fn_params!(pattern)
          return emit_simple_lambda(pattern, body, env, current_scope) if simple_parameter_pattern?(pattern)

          args_var = temp('args')
          body_env = env.child
          bindings_code, body_env = emit_pattern_bind(pattern, args_var, body_env)
          body_code, = emit_sequence(body, body_env, current_scope,
                                     allow_method_definitions: false, result: false)
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
          body_code, = emit_sequence(body, body_env, current_scope,
                                     allow_method_definitions: false, result: false)
          [params, body_code]
        end

        def simple_parameter_pattern?(pattern)
          pattern.is_a?(Vec) && pattern.items.all? do |item|
            item.is_a?(Sym) && (!item.dotted? || item.name == '...') && item.name != '&'
          end
        end

        def validate_fn_params!(pattern)
          return unless pattern.is_a?(Vec)

          pattern.items.each_with_index do |item, idx|
            next unless item.is_a?(Sym) && item.name == '...'
            next if idx == pattern.items.length - 1

            emit_error!(:vararg_not_last)
          end
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
          validate_fn_params!(pattern)
          return unless simple_parameter_pattern?(pattern)

          ruby_name = direct_method_definition_name(name_sym)
          return unless ruby_name
          return if captures_outer_binding?(body, env, pattern_names(pattern))

          body_env = env.child
          params = pattern.items.map { |sym| define_local(body_env, sym.name, shadow: true) }
          body_code, = emit_sequence(body, body_env, :toplevel,
                                     allow_method_definitions: false, result: false)
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
          validate_fn_params!(pattern)
          return emit_simple_method_body(pattern, body, env) if simple_parameter_pattern?(pattern)

          args_var = temp('args')
          method_env = env.child
          bindings_code, body_env = emit_pattern_bind(pattern, args_var, method_env)
          body_code, = emit_sequence(body, body_env, :toplevel,
                                     allow_method_definitions: false, result: false)
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
          return false if method_binding?(binding)
          return false if constant_binding?(binding)

          true
        end

        def constant_binding?(binding)
          binding.is_a?(String) && binding.match?(/\A[A-Z][A-Z0-9_]*\z/)
        end

        def emit_let(args, env, current_scope)
          binding_code, body_code = emit_let_parts(args, env, current_scope, result: true)
          [
            '(-> do',
            indent(join_code(binding_code, body_code)),
            'end).call'
          ].join("\n")
        end

        def emit_let_statement(args, env, current_scope)
          binding_code, body_code = emit_let_parts(args, env, current_scope, result: false)
          join_code(binding_code, body_code)
        end

        def emit_let_parts(args, env, current_scope, result:)
          bindings = args[0]
          emit_error!(:let_odd_bindings) if bindings.items.length.odd?
          emit_error!(:let_no_body) if args.length < 2

          body = args[1..]
          child_env = env.child
          binding_codes = []
          items = bindings.items
          i = 0
          while i < items.length
            pattern = items[i]
            value_form = items[i + 1]
            check_destructure_value!(pattern, value_form)
            value_code = emit_expr(value_form, child_env, current_scope)
            bind_code, child_env = emit_pattern_bind(pattern, value_code, child_env)
            walk_pattern_syms(pattern) { |sym| mark_mutability(child_env, sym, mutable: false) }
            binding_codes << bind_code
            i += 2
          end
          body_code, = emit_sequence(body, child_env, current_scope,
                                     allow_method_definitions: false,
                                     result:)
          [binding_codes.reject(&:empty?).join("\n"), body_code]
        end

        def join_code(*chunks)
          chunks.reject(&:empty?).join("\n")
        end

        def emit_local_form(form, env, current_scope, allow_constant: false)
          emit_error!(:local_arity, form: form.head.name) unless form.items.length == 3

          target = form.items[1]
          value_code = emit_expr(form.items[2], env, current_scope)

          if target.is_a?(Sym)
            validate_binding_symbol!(target)
            if allow_constant && form.head.name == 'local' && (constant_name = constant_name_for(target.name))
              env.define(target.name, constant_name)
              mark_mutability(env, target.name, mutable: false)
              return ["#{constant_name} = #{value_code}\nnil", env]
            end

            ruby_name = define_local(env, target.name)
            mark_mutability(env, target.name, mutable: form.head.name == 'var')
            ["#{ruby_name} = #{value_code}\nnil", env]
          else
            bind_code, env = emit_pattern_bind(target, value_code, env)
            [join_code(bind_code, 'nil'), env]
          end
        end

        def constant_name_for(source_name)
          candidate = source_name.tr('-', '_').upcase
          candidate if candidate.match?(/\A[A-Z][A-Z0-9_]*\z/)
        end

        def check_destructure_value!(pattern, value_form)
          return unless pattern.is_a?(Vec) || pattern.is_a?(HashLit)

          case value_form
          when String, Numeric, Symbol, true, false
            emit_error!(:could_not_destructure_literal)
          end
        end

        def mark_mutability(env, name, mutable:)
          @binding_mutability ||= {}
          ruby_name = env.lookup(name)
          @binding_mutability[ruby_name] = mutable
        end

        def walk_pattern_syms(pattern, &block)
          case pattern
          when Sym
            yield pattern unless pattern.name == '_'
          when Vec
            pattern.items.each do |item|
              next if item.is_a?(Sym) && ['&', '...'].include?(item.name)

              walk_pattern_syms(item, &block)
            end
          when HashLit
            pattern.pairs.each { |pair| walk_pattern_syms(pair[1], &block) }
          end
        end

        def mutable_binding?(env, name)
          ruby_name = env.lookup_if_defined(name)
          return false unless ruby_name

          (@binding_mutability ||= {}).fetch(ruby_name, true)
        end

        def emit_local_expr(args, env, current_scope)
          code, = emit_local_form(List.new([Sym.new('local'), *args]), env.child, current_scope)
          "(-> do\n#{indent(code)}\nend).call"
        end

        def emit_global_expr(args, _env, _current_scope)
          emit_error!(:global_arity) unless args.length == 2
          unless args[0].is_a?(Sym)
            emit_error!(:global_non_symbol_name, type: args[0].class.name.downcase, value: args[0].inspect)
          end

          name = args[0].name
          "$#{global_name(name)} = #{emit_expr(args[1], Env.new, :toplevel)}\nnil"
        end

        def emit_set_form(form, env, current_scope)
          target = form.items[1]
          value_code = emit_expr(form.items[2], env, current_scope)

          if target.is_a?(Sym) && !target.dotted?
            binding = env.lookup_if_defined(target.name)
            ruby_name =
              if binding
                emit_error!(:cannot_set_method_binding, name: target.name) if method_binding?(binding)

                binding
              else
                define_local(env, target.name)
              end
            [emit_assignment(ruby_name, value_code), env]
          else
            [emit_set_target(target, value_code, env, current_scope), env]
          end
        end

        def emit_assignment(lhs, value_code)
          prefix = "#{lhs} "
          if value_code.start_with?(prefix) &&
             (m = value_code[prefix.length..].match(/\A(\S+) (.*)\z/m)) &&
             !m[1].include?('=')
            "#{lhs} #{m[1]}= #{m[2]}"
          else
            "#{lhs} = #{value_code}"
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
              receiver = emit_method_path(base_code, segments[0...-1])
              last = segments.last
              snake = Kapusta.kebab_to_snake(last)
              if direct_method_name?(last)
                emit_assignment("#{receiver}.#{snake}", value_code)
              else
                "#{receiver}.public_send(:\"#{snake}=\", #{value_code})"
              end
            else
              binding = env.lookup(target.name)
              emit_error!(:cannot_set_method_binding, name: target.name) if method_binding?(binding)
              emit_error!(:expected_var, name: target.name) unless mutable_binding?(env, target.name)

              emit_assignment(binding, value_code)
            end
          when List
            head = target.head
            if head.is_a?(Sym) && head.name == '.'
              object_code = emit_expr(target.items[1], env, current_scope)
              keys = target.items[2..].map { |item| emit_expr(item, env, current_scope) }
              receiver = simple_expression?(object_code) ? object_code : parenthesize(object_code)
              prefix = keys[0...-1].map { |k| "[#{k}]" }.join
              emit_assignment("#{receiver}#{prefix}[#{keys.last}]", value_code)
            elsif head.is_a?(Sym) && head.name == 'ivar'
              emit_assignment("@#{Kapusta.kebab_to_snake(target.items[1].name)}", value_code)
            elsif head.is_a?(Sym) && head.name == 'cvar'
              emit_assignment("@@#{Kapusta.kebab_to_snake(target.items[1].name)}", value_code)
            elsif head.is_a?(Sym) && head.name == 'gvar'
              emit_assignment("$#{global_name(target.items[1].name)}", value_code)
            else
              emit_error!(:bad_set_target, target: target.inspect)
            end
          else
            emit_error!(:bad_set_target, target: target.inspect)
          end
        end
      end
    end
  end
end
