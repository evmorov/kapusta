# frozen_string_literal: true

module Kapusta
  class Env
    MethodBinding = Struct.new(:ruby_name)

    def initialize(parent = nil)
      @parent = parent
      @vars = {}
    end

    def define(name, value)
      @vars[name] = value
    end

    def lookup(name)
      if @vars.key?(name)
        @vars[name]
      elsif @parent
        @parent.lookup(name)
      else
        raise NameError, "undefined: #{name}"
      end
    end

    def defined?(name)
      @vars.key?(name) || @parent&.defined?(name)
    end

    def ruby_name_defined?(name)
      @vars.any? { |_source_name, value| binding_ruby_name(value) == name } || @parent&.ruby_name_defined?(name)
    end

    def local_ruby_name_defined?(name)
      @vars.any? { |_source_name, value| binding_ruby_name(value) == name }
    end

    def set_existing!(name, value)
      if @vars.key?(name)
        @vars[name] = value
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

    def binding_ruby_name(value)
      value.respond_to?(:ruby_name) ? value.ruby_name : value
    end
  end
end
