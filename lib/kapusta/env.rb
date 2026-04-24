# frozen_string_literal: true

module Kapusta
  class Env
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
      @vars.value?(name) || @parent&.ruby_name_defined?(name)
    end

    def local_ruby_name_defined?(name)
      @vars.value?(name)
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
  end
end
