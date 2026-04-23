# frozen_string_literal: true

module Kapusta
  class Sym
    attr_reader :name

    def initialize(name)
      @name = name.to_s
    end

    def to_s
      @name
    end

    def inspect
      "#<Sym #{@name}>"
    end

    def ==(other)
      other.is_a?(Sym) && other.name == @name
    end
    alias eql? ==

    def hash
      @name.hash
    end

    def dotted?
      @name != '.' && @name.include?('.')
    end

    def segments
      @name.split('.')
    end
  end

  class Vec
    attr_reader :items

    def initialize(items)
      @items = items
    end
  end

  class HashLit
    attr_reader :pairs

    def initialize(pairs)
      @pairs = pairs
    end

    def all_sym_keys?
      @pairs.all? { |key, _| key.is_a?(Symbol) }
    end
  end

  class List
    attr_reader :items

    def initialize(items)
      @items = items
    end

    def head
      @items.first
    end

    def rest
      @items[1..] || []
    end

    def empty?
      @items.empty?
    end
  end
end
