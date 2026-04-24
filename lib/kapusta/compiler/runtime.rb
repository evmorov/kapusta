# frozen_string_literal: true

module Kapusta
  module Compiler
    module Runtime
      HELPER_DEPENDENCIES = {
        print_values: %i[stringify],
        concat: %i[stringify],
        method_path_value: %i[kebab_to_snake],
        set_method_path: %i[kebab_to_snake],
        get_ivar: %i[kebab_to_snake],
        set_ivar: %i[kebab_to_snake],
        get_cvar: %i[current_class_scope kebab_to_snake],
        set_cvar: %i[current_class_scope kebab_to_snake],
        get_gvar: %i[kebab_to_snake],
        set_gvar: %i[kebab_to_snake],
        destructure: %i[destructure_into],
        match_pattern: %i[match_pattern_into]
      }.freeze

      HELPER_SOURCES = {
        kebab_to_snake: <<~RUBY.chomp,
          def kap_kebab_to_snake(name)
            name.tr('-', '_')
          end
        RUBY
        call: <<~'RUBY'.chomp,
          def kap_call(callee, positional, kwargs = nil, block = nil)
            raise "not callable: #{callee.inspect}" unless callee.respond_to?(:call)

            if block
              kwargs ? callee.call(*positional, **kwargs, &block) : callee.call(*positional, &block)
            else
              kwargs ? callee.call(*positional, **kwargs) : callee.call(*positional)
            end
          end
        RUBY
        send_call: <<~RUBY.chomp,
          def kap_send_call(receiver, method_name, positional, kwargs = nil, block = nil)
            if block
              if kwargs
                receiver.public_send(method_name, *positional, **kwargs, &block)
              else
                receiver.public_send(method_name, *positional, &block)
              end
            elsif kwargs
              receiver.public_send(method_name, *positional, **kwargs)
            else
              receiver.public_send(method_name, *positional)
            end
          end
        RUBY
        invoke_self: <<~RUBY.chomp,
          def kap_invoke_self(receiver, method_name, positional, kwargs = nil, block = nil)
            if block
              if kwargs
                receiver.send(method_name, *positional, **kwargs, &block)
              else
                receiver.send(method_name, *positional, &block)
              end
            else
              kwargs ? receiver.send(method_name, *positional, **kwargs) : receiver.send(method_name, *positional)
            end
          end
        RUBY
        stringify: <<~'RUBY'.chomp,
          def kap_stringify(value)
            render = nil
            render = lambda do |item|
              case item
              when nil then 'nil'
              when true then 'true'
              when false then 'false'
              when String, Symbol then item.inspect
              when Array
                "[#{item.map { |child| render.call(child) }.join(', ')}]"
              when Hash
                "{#{item.map { |key, child| "#{render.call(key)}=>#{render.call(child)}" }.join(', ')}}"
              else
                item.inspect
              end
            end

            case value
            when nil then 'nil'
            when true then 'true'
            when false then 'false'
            when Array, Hash then render.call(value)
            else value.to_s
            end
          end
        RUBY
        print_values: <<~'RUBY'.chomp,
          def kap_print_values(*values)
            $stdout.puts(values.map { |value| kap_stringify(value) }.join("\t"))
            nil
          end
        RUBY
        concat: <<~RUBY.chomp,
          def kap_concat(values)
            values.map { |value| kap_stringify(value) }.join
          end
        RUBY
        get_path: <<~RUBY.chomp,
          def kap_get_path(obj, keys)
            keys.reduce(obj) { |acc, key| acc[key] }
          end
        RUBY
        qget_path: <<~RUBY.chomp,
          def kap_qget_path(obj, keys)
            keys.each do |key|
              return nil if obj.nil?

              obj = obj[key]
            end
            obj
          end
        RUBY
        set_path: <<~RUBY.chomp,
          def kap_set_path(obj, keys, value)
            target = obj
            keys[0...-1].each { |key| target = target[key] }
            target[keys.last] = value
          end
        RUBY
        method_path_value: <<~RUBY.chomp,
          def kap_method_path_value(base, segments)
            segments.reduce(base) { |obj, segment| obj.public_send(kap_kebab_to_snake(segment).to_sym) }
          end
        RUBY
        set_method_path: <<~'RUBY'.chomp,
          def kap_set_method_path(base, segments, value)
            target = base
            segments[0...-1].each do |segment|
              target = target.public_send(kap_kebab_to_snake(segment).to_sym)
            end
            setter = "#{kap_kebab_to_snake(segments.last)}="
            target.public_send(setter.to_sym, value)
          end
        RUBY
        current_class_scope: <<~RUBY.chomp,
          def kap_current_class_scope(receiver)
            receiver.is_a?(Module) ? receiver : receiver.class
          end
        RUBY
        get_ivar: <<~'RUBY'.chomp,
          def kap_get_ivar(receiver, name)
            receiver.instance_variable_get("@#{kap_kebab_to_snake(name)}")
          end
        RUBY
        set_ivar: <<~'RUBY'.chomp,
          def kap_set_ivar(receiver, name, value)
            receiver.instance_variable_set("@#{kap_kebab_to_snake(name)}", value)
          end
        RUBY
        get_cvar: <<~'RUBY'.chomp,
          def kap_get_cvar(receiver, name)
            kap_current_class_scope(receiver).class_variable_get("@@#{kap_kebab_to_snake(name)}")
          end
        RUBY
        set_cvar: <<~'RUBY'.chomp,
          def kap_set_cvar(receiver, name, value)
            kap_current_class_scope(receiver).class_variable_set("@@#{kap_kebab_to_snake(name)}", value)
          end
        RUBY
        get_gvar: <<~'RUBY'.chomp,
          def kap_get_gvar(name)
            Kernel.eval("$#{kap_kebab_to_snake(name)}", binding, __FILE__, __LINE__)
          end
        RUBY
        set_gvar: <<~'RUBY'.chomp,
          def kap_set_gvar(name, value)
            Kernel.eval("$#{kap_kebab_to_snake(name)} = value", binding, __FILE__, __LINE__)
          end
        RUBY
        ensure_module: <<~RUBY.chomp,
          def kap_ensure_module(holder, path)
            segments = path.split('.')
            last = segments.pop
            scope = holder.is_a?(Module) ? holder : Object
            segments.each do |segment|
              scope =
                if scope.const_defined?(segment, false)
                  scope.const_get(segment, false)
                else
                  mod = Module.new
                  scope.const_set(segment, mod)
                  mod
                end
            end
            if scope.const_defined?(last, false)
              scope.const_get(last, false)
            else
              mod = Module.new
              scope.const_set(last, mod)
              mod
            end
          end
        RUBY
        ensure_class: <<~RUBY.chomp,
          def kap_ensure_class(holder, path, super_class)
            segments = path.split('.')
            last = segments.pop
            scope = holder.is_a?(Module) ? holder : Object
            segments.each do |segment|
              scope =
                if scope.const_defined?(segment, false)
                  scope.const_get(segment, false)
                else
                  mod = Module.new
                  scope.const_set(segment, mod)
                  mod
                end
            end
            if scope.const_defined?(last, false)
              scope.const_get(last, false)
            else
              klass = Class.new(super_class)
              scope.const_set(last, klass)
              klass
            end
          end
        RUBY
        destructure: <<~RUBY.chomp,
          def kap_destructure(pattern, value)
            bindings = {}
            kap_destructure_into(pattern, value, bindings)
            bindings
          end
        RUBY
        destructure_into: <<~'RUBY'.chomp,
          def kap_destructure_into(pattern, value, bindings)
            case pattern[0]
            when :sym
              name = pattern[1]
              bindings[name] = value unless name == '_'
            when :vec
              items = pattern[1]
              rest_idx = items.index { |item| item.is_a?(Array) && item[0] == :rest }
              if rest_idx
                before = items[0...rest_idx]
                rest_pattern = items[rest_idx][1]
                before.each_with_index do |item, i|
                  kap_destructure_into(item, value ? value[i] : nil, bindings)
                end
                rest_value = value ? (value[rest_idx..] || []) : []
                kap_destructure_into(rest_pattern, rest_value, bindings)
              else
                items.each_with_index do |item, i|
                  kap_destructure_into(item, value ? value[i] : nil, bindings)
                end
              end
            when :hash
              pattern[1].each do |key, subpattern|
                kap_destructure_into(subpattern, value ? value[key] : nil, bindings)
              end
            when :ignore
              nil
            else
              raise "unknown destructure pattern: #{pattern.inspect}"
            end
          end
        RUBY
        match_pattern: <<~RUBY.chomp,
          def kap_match_pattern(pattern, value)
            bindings = {}
            [kap_match_pattern_into(pattern, value, bindings), bindings]
          end
        RUBY
        match_pattern_into: <<~'RUBY'.chomp
          def kap_match_pattern_into(pattern, value, bindings)
            case pattern[0]
            when :bind
              name = pattern[1]
              allow_nil = pattern[2]
              return false if value.nil? && !allow_nil

              bindings[name] = value
              true
            when :ref
              bindings.key?(pattern[1]) && bindings[pattern[1]] == value
            when :wild
              true
            when :vec
              return false unless value.is_a?(Array) || value.respond_to?(:to_ary)

              array = value.is_a?(Array) ? value : value.to_ary
              items = pattern[1]
              rest_idx = items.index { |item| item.is_a?(Array) && item[0] == :rest }
              if rest_idx
                before = items[0...rest_idx]
                rest_pattern = items[rest_idx][1]
                return false if array.length < before.length

                before.each_with_index do |item, i|
                  return false unless kap_match_pattern_into(item, array[i], bindings)
                end
                kap_match_pattern_into(rest_pattern, array[rest_idx..], bindings)
              else
                return false unless array.length >= items.length

                items.each_with_index do |item, i|
                  return false unless kap_match_pattern_into(item, array[i], bindings)
                end
                true
              end
            when :hash
              return false unless value.is_a?(Hash)

              pattern[1].each do |key, subpattern|
                return false unless value.key?(key)
                return false unless kap_match_pattern_into(subpattern, value[key], bindings)
              end
              true
            when :lit
              value == pattern[1]
            when :pin
              value == pattern[1]
            when :or
              pattern[1].any? do |option|
                option_bindings = bindings.dup
                next false unless kap_match_pattern_into(option, value, option_bindings)

                bindings.replace(option_bindings)
                true
              end
            else
              raise "bad pattern: #{pattern.inspect}"
            end
          end
        RUBY
      }.transform_values(&:freeze).freeze

      module_function

      def helper_name(name)
        "kap_#{name}"
      end

      def helper_source(helpers)
        ordered = []
        seen = {}
        helpers.each { |name| append_helper_source(name.to_sym, ordered, seen) }
        return '' if ordered.empty?

        [
          ordered.map { |name| HELPER_SOURCES.fetch(name) }.join("\n\n"),
          "private #{ordered.map { |name| ":#{helper_name(name)}" }.join(', ')}"
        ].join("\n\n")
      end

      def append_helper_source(name, ordered, seen)
        return if seen[name]

        HELPER_DEPENDENCIES.fetch(name, []).each do |dependency|
          append_helper_source(dependency, ordered, seen)
        end
        ordered << name
        seen[name] = true
      end

      HELPER_SOURCES.each_value do |source|
        module_eval(source, __FILE__, __LINE__)
      end

      helper_methods = []

      HELPER_SOURCES.each_key do |name|
        helper_method = :"kap_#{name}"
        define_singleton_method(name, instance_method(helper_method))
        helper_methods << helper_method
      end

      send(:private, *helper_methods)
    end
  end
end
