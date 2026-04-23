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
          def __kap_kebab_to_snake(name)
            name.tr('-', '_')
          end
        RUBY
        call: <<~'RUBY'.chomp,
          def __kap_call(callee, positional, kwargs = nil, block = nil)
            raise "not callable: #{callee.inspect}" unless callee.respond_to?(:call)

            if block
              kwargs ? callee.call(*positional, **kwargs, &block) : callee.call(*positional, &block)
            else
              kwargs ? callee.call(*positional, **kwargs) : callee.call(*positional)
            end
          end
        RUBY
        send_call: <<~RUBY.chomp,
          def __kap_send_call(receiver, method_name, positional, kwargs = nil, block = nil)
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
          def __kap_invoke_self(receiver, method_name, positional, kwargs = nil, block = nil)
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
        stringify: <<~RUBY.chomp,
          def __kap_stringify(value)
            case value
            when nil then 'nil'
            when true then 'true'
            when false then 'false'
            else value.to_s
            end
          end
        RUBY
        print_values: <<~'RUBY'.chomp,
          def __kap_print_values(*values)
            $stdout.puts(values.map { |value| __kap_stringify(value) }.join("\t"))
            nil
          end
        RUBY
        concat: <<~RUBY.chomp,
          def __kap_concat(values)
            values.map { |value| __kap_stringify(value) }.join
          end
        RUBY
        get_path: <<~RUBY.chomp,
          def __kap_get_path(obj, keys)
            keys.reduce(obj) { |acc, key| acc[key] }
          end
        RUBY
        qget_path: <<~RUBY.chomp,
          def __kap_qget_path(obj, keys)
            keys.each do |key|
              return nil if obj.nil?

              obj = obj[key]
            end
            obj
          end
        RUBY
        set_path: <<~RUBY.chomp,
          def __kap_set_path(obj, keys, value)
            target = obj
            keys[0...-1].each { |key| target = target[key] }
            target[keys.last] = value
          end
        RUBY
        method_path_value: <<~RUBY.chomp,
          def __kap_method_path_value(base, segments)
            segments.reduce(base) { |obj, segment| obj.public_send(__kap_kebab_to_snake(segment).to_sym) }
          end
        RUBY
        set_method_path: <<~'RUBY'.chomp,
          def __kap_set_method_path(base, segments, value)
            target = base
            segments[0...-1].each do |segment|
              target = target.public_send(__kap_kebab_to_snake(segment).to_sym)
            end
            setter = "#{__kap_kebab_to_snake(segments.last)}="
            target.public_send(setter.to_sym, value)
          end
        RUBY
        current_class_scope: <<~RUBY.chomp,
          def __kap_current_class_scope(receiver)
            receiver.is_a?(Module) ? receiver : receiver.class
          end
        RUBY
        get_ivar: <<~'RUBY'.chomp,
          def __kap_get_ivar(receiver, name)
            receiver.instance_variable_get("@#{__kap_kebab_to_snake(name)}")
          end
        RUBY
        set_ivar: <<~'RUBY'.chomp,
          def __kap_set_ivar(receiver, name, value)
            receiver.instance_variable_set("@#{__kap_kebab_to_snake(name)}", value)
          end
        RUBY
        get_cvar: <<~'RUBY'.chomp,
          def __kap_get_cvar(receiver, name)
            __kap_current_class_scope(receiver).class_variable_get("@@#{__kap_kebab_to_snake(name)}")
          end
        RUBY
        set_cvar: <<~'RUBY'.chomp,
          def __kap_set_cvar(receiver, name, value)
            __kap_current_class_scope(receiver).class_variable_set("@@#{__kap_kebab_to_snake(name)}", value)
          end
        RUBY
        get_gvar: <<~'RUBY'.chomp,
          def __kap_get_gvar(name)
            Kernel.eval("$#{__kap_kebab_to_snake(name)}", binding, __FILE__, __LINE__)
          end
        RUBY
        set_gvar: <<~'RUBY'.chomp,
          def __kap_set_gvar(name, value)
            Kernel.eval("$#{__kap_kebab_to_snake(name)} = value", binding, __FILE__, __LINE__)
          end
        RUBY
        ensure_module: <<~RUBY.chomp,
          def __kap_ensure_module(holder, path)
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
          def __kap_ensure_class(holder, path, super_class)
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
          def __kap_destructure(pattern, value)
            bindings = {}
            __kap_destructure_into(pattern, value, bindings)
            bindings
          end
        RUBY
        destructure_into: <<~'RUBY'.chomp,
          def __kap_destructure_into(pattern, value, bindings)
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
                  __kap_destructure_into(item, value ? value[i] : nil, bindings)
                end
                rest_value = value ? (value[rest_idx..] || []) : []
                __kap_destructure_into(rest_pattern, rest_value, bindings)
              else
                items.each_with_index do |item, i|
                  __kap_destructure_into(item, value ? value[i] : nil, bindings)
                end
              end
            when :hash
              pattern[1].each do |key, subpattern|
                __kap_destructure_into(subpattern, value ? value[key] : nil, bindings)
              end
            when :ignore
              nil
            else
              raise "unknown destructure pattern: #{pattern.inspect}"
            end
          end
        RUBY
        match_pattern: <<~RUBY.chomp,
          def __kap_match_pattern(pattern, value)
            bindings = {}
            [__kap_match_pattern_into(pattern, value, bindings), bindings]
          end
        RUBY
        match_pattern_into: <<~'RUBY'.chomp
          def __kap_match_pattern_into(pattern, value, bindings)
            case pattern[0]
            when :sym
              name = pattern[1]
              bindings[name] = value unless name == '_'
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
                  return false unless __kap_match_pattern_into(item, array[i], bindings)
                end
                __kap_match_pattern_into(rest_pattern, array[rest_idx..], bindings)
              else
                return false unless array.length == items.length

                items.each_with_index do |item, i|
                  return false unless __kap_match_pattern_into(item, array[i], bindings)
                end
                true
              end
            when :hash
              return false unless value.is_a?(Hash)

              pattern[1].each do |key, subpattern|
                return false unless value.key?(key)
                return false unless __kap_match_pattern_into(subpattern, value[key], bindings)
              end
              true
            when :lit
              value == pattern[1]
            when :nil
              value.nil?
            else
              raise "bad pattern: #{pattern.inspect}"
            end
          end
        RUBY
      }.transform_values(&:freeze).freeze

      module_function

      def helper_name(name)
        "__kap_#{name}"
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

      def call(callee, positional, kwargs = nil, block = nil)
        raise "not callable: #{callee.inspect}" unless callee.respond_to?(:call)

        if block
          kwargs ? callee.call(*positional, **kwargs, &block) : callee.call(*positional, &block)
        else
          kwargs ? callee.call(*positional, **kwargs) : callee.call(*positional)
        end
      end

      def send_call(receiver, method_name, positional, kwargs = nil, block = nil)
        if block
          if kwargs
            receiver.public_send(method_name, *positional, **kwargs,
                                 &block)
          else
            receiver.public_send(method_name, *positional, &block)
          end
        elsif kwargs
          receiver.public_send(method_name, *positional,
                               **kwargs)
        else
          receiver.public_send(method_name, *positional)
        end
      end

      def invoke_self(receiver, method_name, positional, kwargs = nil, block = nil)
        if block
          if kwargs
            receiver.send(method_name, *positional, **kwargs,
                          &block)
          else
            receiver.send(method_name, *positional, &block)
          end
        else
          kwargs ? receiver.send(method_name, *positional, **kwargs) : receiver.send(method_name, *positional)
        end
      end

      def stringify(value)
        case value
        when nil then 'nil'
        when true then 'true'
        when false then 'false'
        else value.to_s
        end
      end

      def print_values(*values)
        $stdout.puts(values.map { |value| stringify(value) }.join("\t"))
        nil
      end

      def concat(values)
        values.map { |value| stringify(value) }.join
      end

      def get_path(obj, keys)
        keys.reduce(obj) { |acc, key| acc[key] }
      end

      def qget_path(obj, keys)
        keys.each do |key|
          return nil if obj.nil?

          obj = obj[key]
        end
        obj
      end

      def set_path(obj, keys, value)
        target = obj
        keys[0...-1].each { |key| target = target[key] }
        target[keys.last] = value
      end

      def method_path_value(base, segments)
        segments.reduce(base) { |obj, segment| obj.public_send(Kapusta.kebab_to_snake(segment).to_sym) }
      end

      def set_method_path(base, segments, value)
        target = base
        segments[0...-1].each do |segment|
          target = target.public_send(Kapusta.kebab_to_snake(segment).to_sym)
        end
        setter = "#{Kapusta.kebab_to_snake(segments.last)}="
        target.public_send(setter.to_sym, value)
      end

      def current_class_scope(receiver)
        receiver.is_a?(Module) ? receiver : receiver.class
      end

      def get_ivar(receiver, name)
        receiver.instance_variable_get("@#{Kapusta.kebab_to_snake(name)}")
      end

      def set_ivar(receiver, name, value)
        receiver.instance_variable_set("@#{Kapusta.kebab_to_snake(name)}", value)
      end

      def get_cvar(receiver, name)
        current_class_scope(receiver).class_variable_get("@@#{Kapusta.kebab_to_snake(name)}")
      end

      def set_cvar(receiver, name, value)
        current_class_scope(receiver).class_variable_set("@@#{Kapusta.kebab_to_snake(name)}", value)
      end

      def get_gvar(name)
        Kernel.eval("$#{Kapusta.kebab_to_snake(name)}", binding, __FILE__, __LINE__) # $stderr
      end

      def set_gvar(name, value)
        Kernel.eval("$#{Kapusta.kebab_to_snake(name)} = value", binding, __FILE__, __LINE__) # $stderr = value
      end

      def ensure_module(holder, path)
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

      def ensure_class(holder, path, super_class)
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

      def destructure(pattern, value)
        bindings = {}
        destructure_into(pattern, value, bindings)
        bindings
      end

      def destructure_into(pattern, value, bindings)
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
              destructure_into(item, value ? value[i] : nil, bindings)
            end
            rest_value = value ? (value[rest_idx..] || []) : []
            destructure_into(rest_pattern, rest_value, bindings)
          else
            items.each_with_index do |item, i|
              destructure_into(item, value ? value[i] : nil, bindings)
            end
          end
        when :hash
          pattern[1].each do |key, subpattern|
            destructure_into(subpattern, value ? value[key] : nil, bindings)
          end
        when :ignore
          nil
        else
          raise "unknown destructure pattern: #{pattern.inspect}"
        end
      end

      def match_pattern(pattern, value)
        bindings = {}
        [match_pattern_into(pattern, value, bindings), bindings]
      end

      def match_pattern_into(pattern, value, bindings)
        case pattern[0]
        when :sym
          name = pattern[1]
          bindings[name] = value unless name == '_'
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
              return false unless match_pattern_into(item, array[i], bindings)
            end
            match_pattern_into(rest_pattern, array[rest_idx..], bindings)
          else
            return false unless array.length == items.length

            items.each_with_index do |item, i|
              return false unless match_pattern_into(item, array[i], bindings)
            end
            true
          end
        when :hash
          return false unless value.is_a?(Hash)

          pattern[1].each do |key, subpattern|
            return false unless value.key?(key)
            return false unless match_pattern_into(subpattern, value[key], bindings)
          end
          true
        when :lit
          value == pattern[1]
        when :nil
          value.nil?
        else
          raise "bad pattern: #{pattern.inspect}"
        end
      end
    end
  end
end
