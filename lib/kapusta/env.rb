# frozen_string_literal: true

module Kapusta
  class Env
    MethodBinding = Struct.new(:ruby_name)

    def initialize(parent = nil)
      @parent = parent
      @vars = {}
    end

    def define(name, value)
      @vars[binding_key(name)] = value
    end

    def lookup(name)
      key = binding_key(name)
      if @vars.key?(key)
        @vars[key]
      elsif @parent
        @parent.lookup(name)
      else
        raise NameError, "undefined: #{name}"
      end
    end

    def lookup_if_defined(name)
      key = binding_key(name)
      if @vars.key?(key)
        @vars[key]
      else
        @parent&.lookup_if_defined(name)
      end
    end

    def defined?(name)
      @vars.key?(binding_key(name)) || @parent&.defined?(name)
    end

    def ruby_name_defined?(name)
      @vars.any? { |_source_name, value| binding_ruby_name(value) == name } || @parent&.ruby_name_defined?(name)
    end

    def local_ruby_name_defined?(name)
      @vars.any? { |_source_name, value| binding_ruby_name(value) == name }
    end

    def set_existing!(name, value)
      key = binding_key(name)
      if @vars.key?(key)
        @vars[key] = value
      elsif @parent
        @parent.set_existing!(name, value)
      else
        raise NameError, "undefined: #{name}"
      end
    end

    def child
      Env.new(self)
    end

    private

    def binding_key(name)
      name.respond_to?(:binding_key) ? name.binding_key : name
    end

    def binding_ruby_name(value)
      value.respond_to?(:ruby_name) ? value.ruby_name : value
    end
  end
end
