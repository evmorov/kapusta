# frozen_string_literal: true

module Kapusta
  module Compiler
    module LuaCompat
      SPECIAL_FORMS = %w[pcall xpcall].freeze
      ITERATOR_FORMS = %w[ipairs pairs].freeze

      def self.special_form?(name)
        SPECIAL_FORMS.include?(name)
      end

      def self.iterator_form?(name)
        ITERATOR_FORMS.include?(name)
      end

      module Normalization
        private

        def normalize_lua_compat_form(name, items)
          case name
          when 'pcall' then normalize_lua_pcall(items)
          when 'xpcall' then normalize_lua_xpcall(items)
          end
        end

        def normalize_lua_pcall(items)
          fn = items[1]
          args = items[2..]
          List.new([
                     Sym.new('try'),
                     List.new([Sym.new('values'), true, List.new([fn, *args])]),
                     List.new([Sym.new('catch'), Sym.new('StandardError'), Sym.new('e'),
                               List.new([Sym.new('values'), false, Sym.new('e')])])
                   ])
        end

        def normalize_lua_xpcall(items)
          fn = items[1]
          handler = items[2]
          args = items[3..]
          List.new([
                     Sym.new('try'),
                     List.new([Sym.new('values'), true, List.new([fn, *args])]),
                     List.new([Sym.new('catch'), Sym.new('StandardError'), Sym.new('e'),
                               List.new([Sym.new('values'), false, List.new([handler, Sym.new('e')])])])
                   ])
        end
      end

      module Emission
        private

        def emit_lua_compat_inject(iter_expr, binding_pats, body_env, env, current_scope, acc_var,
                                   init_code, body_forms)
          return unless lua_iterator_expr?(iter_expr)

          case iter_expr.head.name
          when 'ipairs'
            emit_lua_ipairs_inject(iter_expr, binding_pats, body_env, env, current_scope,
                                   acc_var, init_code, body_forms)
          when 'pairs'
            emit_lua_pairs_inject(iter_expr, binding_pats, body_env, env, current_scope,
                                  acc_var, init_code, body_forms)
          end
        end

        def emit_lua_compat_iteration(iter_expr, binding_pats, env, current_scope, method:, &block)
          return unless lua_iterator_expr?(iter_expr)

          case iter_expr.head.name
          when 'ipairs'
            emit_lua_ipairs_iteration(iter_expr, binding_pats, env, current_scope, method:, &block)
          when 'pairs'
            emit_lua_pairs_iteration(iter_expr, binding_pats, env, current_scope, method:, &block)
          end
        end

        def lua_iterator_expr?(expr)
          expr.is_a?(List) && expr.head.is_a?(Sym) && LuaCompat.iterator_form?(expr.head.name)
        end

        def emit_lua_ipairs_inject(iter_expr, binding_pats, body_env, env, current_scope, acc_var,
                                   init_code, body_forms)
          coll_code = emit_expr(iter_expr.items[1], env, current_scope)
          value_var, value_bind = bind_iteration_param(binding_pats[1], 'value', body_env)
          if ignored_pattern?(binding_pats[0])
            body_code, = emit_sequence(body_forms, body_env, current_scope, allow_method_definitions: false)
            return inject_block(coll_code, "#{acc_var}, #{value_var}", init_code, value_bind || '', body_code)
          end

          index_var, index_bind = bind_iteration_param(binding_pats[0], 'index', body_env)
          bind_code = [index_bind, value_bind].compact.join("\n")
          body_code, = emit_sequence(body_forms, body_env, current_scope, allow_method_definitions: false)
          inject_block("#{coll_code}.each_with_index", "#{acc_var}, (#{value_var}, #{index_var})",
                       init_code, bind_code, body_code)
        end

        def emit_lua_pairs_inject(iter_expr, binding_pats, body_env, env, current_scope, acc_var,
                                  init_code, body_forms)
          key_var, key_bind = bind_iteration_param(binding_pats[0], 'key', body_env)
          value_var, value_bind = bind_iteration_param(binding_pats[1], 'value', body_env)
          bind_code = [key_bind, value_bind].compact.join("\n")
          body_code, = emit_sequence(body_forms, body_env, current_scope, allow_method_definitions: false)
          coll_code = emit_expr(iter_expr.items[1], env, current_scope)
          inject_block(coll_code, "#{acc_var}, (#{key_var}, #{value_var})",
                       init_code, bind_code, body_code)
        end

        def emit_lua_ipairs_iteration(iter_expr, binding_pats, env, current_scope, method:, &block)
          body_env = env.child
          value_var, value_bind = bind_iteration_param(binding_pats[1], 'value', body_env)
          coll_code = emit_expr(iter_expr.items[1], env, current_scope)
          if ignored_pattern?(binding_pats[0])
            bind_code = value_bind || ''
            body_code = block.call(body_env)
            return iteration_block("#{coll_code}.#{method} do |#{value_var}|", bind_code, body_code)
          end

          index_var, index_bind = bind_iteration_param(binding_pats[0], 'index', body_env)
          bind_code = [index_bind, value_bind].compact.join("\n")
          body_code = block.call(body_env)
          receiver = method == 'each' ? "#{coll_code}.each_with_index" : "#{coll_code}.each_with_index.#{method}"
          header = "#{receiver} do |#{value_var}, #{index_var}|"
          iteration_block(header, bind_code, body_code)
        end

        def emit_lua_pairs_iteration(iter_expr, binding_pats, env, current_scope, method:, &block)
          body_env = env.child
          key_var, key_bind = bind_iteration_param(binding_pats[0], 'key', body_env)
          value_var, value_bind = bind_iteration_param(binding_pats[1], 'value', body_env)
          bind_code = [key_bind, value_bind].compact.join("\n")
          body_code = block.call(body_env)
          coll_code = emit_expr(iter_expr.items[1], env, current_scope)
          header = "#{coll_code}.#{method} do |#{key_var}, #{value_var}|"
          iteration_block(header, bind_code, body_code)
        end
      end
    end
  end
end
