# frozen_string_literal: true

module Kapusta
  module Compiler
    module EmitterModules
      module Expressions
        private

        def emit_expr(form, env, current_scope)
          with_current_form(form) do
            case form
            when Sym then emit_sym(form, env)
            when Vec then "[#{form.items.map { |item| emit_expr(item, env, current_scope) }.join(', ')}]"
            when HashLit
              "{#{form.pairs.map do |key, value|
                "#{emit_hash_key(key, env, current_scope)} => #{emit_expr(value, env, current_scope)}"
              end.join(', ')}}"
            when List then emit_list(form, env, current_scope)
            when String, Symbol, Numeric, true, false, nil then form.inspect
            else
              emit_error!(:cannot_emit_form, form: form.inspect)
            end
          end
        end

        def emit_hash_key(key, env, current_scope)
          case key
          when Sym, Vec, HashLit, List then emit_expr(key, env, current_scope)
          else key.inspect
          end
        end

        def emit_list(list, env, current_scope)
          emit_error!(:empty_call) if list.empty?

          head = list.head
          args = list.rest
          if head.is_a?(Sym)
            return emit_special(head.name, args, env, current_scope) if special_form?(head.name)
            return emit_multisym_call(head, args, env, current_scope) if head.dotted?
            if (binding = env.lookup_if_defined(head.name))
              return emit_bound_call(binding, args, env, current_scope)
            end

            return emit_self_call(head.name, args, env, current_scope)
          end

          case head
          when Numeric, String, Symbol, true, false, nil
            emit_error!(:cannot_call_literal, value: head.inspect)
          end

          emit_callable_call(emit_expr(head, env, current_scope), args, env, current_scope)
        end

        def emit_special(name, args, env, current_scope)
          case name
          when 'fn', 'lambda', 'λ' then emit_fn(args, env, current_scope)
          when 'let' then emit_let(args, env, current_scope)
          when 'local', 'var' then emit_local_expr(args, env, current_scope)
          when 'global' then emit_global_expr(args, env, current_scope)
          when 'set' then emit_set_expr(args, env, current_scope)
          when 'if' then emit_if(args, env, current_scope)
          when 'case' then emit_case(args, env, current_scope, :case)
          when 'match' then emit_case(args, env, current_scope, :match)
          when 'while' then emit_while(args, env, current_scope)
          when 'for' then emit_for(args, env, current_scope)
          when 'each' then emit_each(args, env, current_scope)
          when 'do' then "begin\n#{indent(emit_sequence(args, env, current_scope,
                                                        allow_method_definitions: false).first)}\nend"
          when 'values' then "[#{args.map { |arg| emit_expr(arg, env, current_scope) }.join(', ')}]"
          when 'icollect' then emit_icollect(args, env, current_scope)
          when 'collect' then emit_collect(args, env, current_scope)
          when 'fcollect' then emit_fcollect(args, env, current_scope)
          when 'accumulate' then emit_accumulate(args, env, current_scope)
          when 'faccumulate' then emit_faccumulate(args, env, current_scope)
          when 'hashfn' then emit_hashfn(args, env, current_scope)
          when '.' then emit_lookup(args, env, current_scope)
          when '?.' then emit_safe_lookup(args, env, current_scope)
          when ':' then emit_colon(args, env, current_scope)
          when '..' then emit_concat(args, env, current_scope)
          when 'length' then "#{parenthesize(emit_expr(args[0], env, current_scope))}.length"
          when 'require' then emit_require(args[0], env, current_scope)
          when 'module' then emit_module_expr(args, env)
          when 'class' then emit_class_expr(args, env)
          when 'end' then emit_error!(:end_outside_header)
          when 'try' then emit_try(args, env, current_scope)
          when 'raise' then emit_raise(args, env, current_scope)
          when 'ivar' then "@#{Kapusta.kebab_to_snake(args[0].name)}"
          when 'cvar' then "@@#{Kapusta.kebab_to_snake(args[0].name)}"
          when 'gvar' then emit_gvar(args[0])
          when 'ruby' then "Kernel.eval(#{emit_expr(args[0], env, current_scope)})"
          when 'and' then emit_and(args, env, current_scope)
          when 'or' then emit_or(args, env, current_scope)
          when 'not' then "!#{parenthesize(emit_expr(args[0], env, current_scope))}"
          when '=' then emit_compare(args, env, current_scope, '==')
          when 'not=' then emit_compare_any(args, env, current_scope, '!=')
          when '<' then emit_compare(args, env, current_scope, '<')
          when '<=' then emit_compare(args, env, current_scope, '<=')
          when '>' then emit_compare(args, env, current_scope, '>')
          when '>=' then emit_compare(args, env, current_scope, '>=')
          when '+' then emit_reduce(args, env, current_scope, '0', :+)
          when '-' then emit_minus(args, env, current_scope)
          when '*' then emit_reduce(args, env, current_scope, '1', :*)
          when '/' then emit_div(args, env, current_scope)
          when '%' then args.map { |arg| parenthesize(emit_expr(arg, env, current_scope)) }.join(' % ')
          when 'print' then emit_print(args, env, current_scope)
          when 'quasi-sym' then "Kapusta::MacroSym.new(#{emit_expr(args[0], env, current_scope)})"
          when 'quasi-list' then "Kapusta::List.new([#{args.map { |a| emit_expr(a, env, current_scope) }.join(', ')}])"
          when 'quasi-list-tail' then emit_quasi_list_tail(args, env, current_scope)
          when 'quasi-vec' then "Kapusta::Vec.new([#{args.map { |a| emit_expr(a, env, current_scope) }.join(', ')}])"
          when 'quasi-vec-tail' then emit_quasi_vec_tail(args, env, current_scope)
          when 'quasi-hash' then emit_quasi_hash(args, env, current_scope)
          when 'quasi-gensym' then emit_quasi_gensym(args[0], env, current_scope)
          else
            emit_error!(:unknown_special_form, name:)
          end
        end

        def emit_quasi_list_tail(args, env, current_scope)
          head_items = args[0]
          tail_expr = emit_expr(args[1], env, current_scope)
          head_code = head_items.items.map { |item| emit_expr(item, env, current_scope) }.join(', ')
          "Kapusta::List.new([#{head_code}, *#{parenthesize(tail_expr)}])"
        end

        def emit_quasi_vec_tail(args, env, current_scope)
          head_items = args[0]
          tail_expr = emit_expr(args[1], env, current_scope)
          head_code = head_items.items.map { |item| emit_expr(item, env, current_scope) }.join(', ')
          "Kapusta::Vec.new([#{head_code}, *#{parenthesize(tail_expr)}])"
        end

        def emit_quasi_gensym(arg, env, current_scope)
          "Kapusta::Compiler::MacroExpander.fresh_gensym(#{emit_expr(arg, env, current_scope)})"
        end

        def emit_quasi_hash(args, env, current_scope)
          pairs = args.each_slice(2).map do |key, value|
            "[#{emit_expr(key, env, current_scope)}, #{emit_expr(value, env, current_scope)}]"
          end
          "Kapusta::HashLit.new([#{pairs.join(', ')}])"
        end

        def emit_concat(args, env, current_scope)
          return '""' if args.empty?

          args.each do |arg|
            emit_error!(:vararg_with_operator) if arg.is_a?(Sym) && arg.name == '...'
          end
          args.map { |arg| emit_string_part(arg, env, current_scope) }.join(' + ')
        end

        def emit_print(args, env, current_scope)
          return 'p' if args.empty?

          rendered = args.map { |arg| emit_expr(arg, env, current_scope) }
          return "p #{rendered[0]}" if rendered.length == 1 && simple_expression?(rendered[0])

          "p(#{rendered.join(', ')})"
        end

        def emit_string_part(arg, env, current_scope)
          return arg.inspect if arg.is_a?(String)

          code = emit_expr(arg, env, current_scope)
          "#{simple_expression?(code) ? code : "(#{code})"}.to_s"
        end
      end
    end
  end
end
