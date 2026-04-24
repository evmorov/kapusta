# frozen_string_literal: true

module Kapusta
  module Compiler
    module Runtime
      HELPER_DEPENDENCIES = {
        destructure: %i[destructure_into],
        match_pattern: %i[match_pattern_into]
      }.freeze

      HELPER_SOURCES = {
        qget_path: <<~RUBY.chomp,
          def kap_qget_path(obj, keys)
            keys.each do |key|
              return if obj.nil?

              obj = obj[key]
            end
            obj
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
        body = instance_method(helper_method)
        define_singleton_method(helper_method, body)
        define_singleton_method(name, body)
        helper_methods << helper_method
      end

      private_class_method(*helper_methods)
      send(:private, *helper_methods)
    end
  end
end
