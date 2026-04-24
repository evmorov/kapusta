# frozen_string_literal: true

module Kapusta
  module Compiler
    module EmitterModules
      module Support
        private

        def emit_forms_with_headers(forms, env, current_scope)
          i = 0
          codes = []
          while i < forms.length
            form = forms[i]
            if bodyless_header?(form)
              codes << emit_bodyless_header(form, forms[(i + 1)..], env, current_scope)
              break
            else
              code, env = emit_form_in_sequence(form, env, current_scope, allow_method_definitions: true)
              codes << code
              i += 1
            end
          end
          codes.join("\n")
        end

        def bodyless_header?(form)
          return false unless form.is_a?(List) && !form.empty? && form.head.is_a?(Sym)

          case form.head.name
          when 'module'
            body = form.items[2..] || []
            return true if body.empty?

            body.length == 1 && bodyless_header?(body[0])
          when 'class'
            _, _, body = split_class_args(form.items[1..])
            body.empty?
          else
            false
          end
        end

        def emit_bodyless_header(form, remaining_forms, env, _current_scope)
          head = form.head.name
          name_sym = form.items[1]

          if head == 'module'
            inner = form.items[2..] || []
            body =
              if inner.length == 1 && bodyless_header?(inner[0])
                emit_bodyless_header(inner[0], remaining_forms, env, :module)
              else
                emit_forms_with_headers(remaining_forms, env, :module)
              end
            emit_module_wrapper(name_sym, body)
          else
            name_sym, supers, = split_class_args(form.items[1..])
            body = emit_forms_with_headers(remaining_forms, env, :class)
            emit_class_wrapper(name_sym, supers, env, body)
          end
        end

        def emit_form_in_sequence(form, env, current_scope, allow_method_definitions:)
          if allow_method_definitions && method_definition_form?(form) && %i[module class].include?(current_scope)
            [emit_method_definition(form, env), env]
          elsif named_function_form?(form)
            emit_named_fn_assignment(form, env, current_scope)
          elsif local_form?(form)
            emit_local_form(form, env, current_scope)
          elsif do_form?(form)
            emit_do_form(form.rest, env, current_scope)
          elsif set_new_local_form?(form, env)
            emit_set_form(form, env, current_scope)
          else
            [emit_expr(form, env, current_scope), env]
          end
        end

        def emit_do_form(forms, env, current_scope)
          body, new_env = emit_sequence(forms, env, current_scope, allow_method_definitions: false)
          ["begin\n#{indent(body)}\nend", new_env]
        end

        def emit_sequence(forms, env, current_scope, allow_method_definitions:)
          current_env = env
          codes = []
          forms.each do |form|
            code, current_env = emit_form_in_sequence(form, current_env, current_scope,
                                                      allow_method_definitions:)
            codes << code
          end
          [codes.join("\n"), current_env]
        end

        def special_form?(name)
          Compiler::SPECIAL_FORMS.include?(name)
        end

        def split_class_args(args)
          name_sym = args[0]
          if args[1].is_a?(Vec)
            [name_sym, args[1], args[2..] || []]
          else
            [name_sym, nil, args[1..] || []]
          end
        end

        def named_function_form?(form)
          form.is_a?(List) && !form.empty? && form.head.is_a?(Sym) &&
            %w[fn lambda λ].include?(form.head.name) && form.items[1].is_a?(Sym)
        end

        def method_definition_form?(form)
          named_function_form?(form)
        end

        def block_form?(form)
          form.is_a?(List) && form.head.is_a?(Sym) && %w[fn lambda λ hashfn].include?(form.head.name)
        end

        def local_form?(form)
          form.is_a?(List) && form.head.is_a?(Sym) && %w[local var].include?(form.head.name)
        end

        def do_form?(form)
          form.is_a?(List) && form.head.is_a?(Sym) && form.head.name == 'do'
        end

        def set_new_local_form?(form, env)
          return false unless form.is_a?(List) && form.head.is_a?(Sym) && form.head.name == 'set'

          target = form.items[1]
          target.is_a?(Sym) && !target.dotted? && !env.defined?(target.name)
        end

        def indent(text, level = 1)
          prefix = '  ' * level
          text.lines.map { |line| line.strip.empty? ? line : "#{prefix}#{line}" }.join
        end

        def temp(prefix)
          @temp_index += 1
          "__kap_#{prefix}_#{@temp_index}"
        end

        def runtime_helper(name)
          helper = name.to_sym
          @runtime_helpers << helper unless @runtime_helpers.include?(helper)
          Runtime.helper_name(helper)
        end

        def runtime_call(name, *args)
          rendered_args = args.map do |arg|
            arg.is_a?(Array) ? "[#{arg.join(', ')}]" : arg || 'nil'
          end
          "#{runtime_helper(name)}(#{rendered_args.join(', ')})"
        end

        def parse_counted_for_bindings(bindings, env, current_scope)
          name_sym = bindings[0]
          ruby_name = temp(sanitize_local(name_sym.name))
          loop_env = env.child
          loop_env.define(name_sym.name, ruby_name)
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
          { ruby_name:, loop_env:, start_code:, finish_code:, step_code:, until_form: }
        end

        def emit_counted_loop(ruby_name:, start_code:, finish_code:, step_code:,
                              until_form:, loop_env:, current_scope:, body_code:)
          finish_var = temp('finish')
          step_var = temp('step')
          cmp_var = temp('cmp')
          until_code = until_form ? "break if #{emit_expr(until_form, loop_env, current_scope)}" : nil
          <<~RUBY.chomp
            #{ruby_name} = #{start_code}
            #{finish_var} = #{finish_code}
            #{step_var} = #{step_code}
            #{cmp_var} = #{step_var} >= 0 ? :<= : :>=
            while #{ruby_name}.public_send(#{cmp_var}, #{finish_var})
              #{until_code}
              #{indent(body_code)}
              #{ruby_name} += #{step_var}
            end
          RUBY
        end

        def sanitize_local(name)
          base = Kapusta.kebab_to_snake(name)
          base = base.gsub('?', '_q').gsub('!', '_bang')
          base = base.gsub(/[^a-zA-Z0-9_]/, '_')
          base = "_#{base}" if base.empty? || base.match?(/\A\d/) || self.class::RUBY_KEYWORDS.include?(base)
          base
        end
      end
    end
  end
end
