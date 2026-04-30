# frozen_string_literal: true

module Kapusta
  class Comment
    attr_reader :text

    def initialize(text)
      @text = text
    end
  end

  BlankLine = Class.new

  class Sym
    attr_reader :name
    attr_accessor :line, :column

    def initialize(name)
      @name = name.to_s
    end

    def to_s
      @name
    end

    def inspect
      @name.to_s
    end

    def ==(other)
      other.instance_of?(self.class) && other.name == @name
    end
    alias eql? ==

    def hash
      [self.class, @name].hash
    end

    def binding_key
      @name
    end

    def dotted?
      @name != '.' && @name.include?('.')
    end

    def segments
      @name.split('.')
    end
  end

  class GeneratedSym < Sym
    attr_reader :id

    def initialize(name, id)
      super(name)
      @id = id
    end

    def inspect
      "#<GeneratedSym #{@name} #{@id}>"
    end

    def ==(other)
      other.is_a?(GeneratedSym) && other.id == @id
    end
    alias eql? ==

    def hash
      [self.class, @id].hash
    end

    def binding_key
      [self.class, @id]
    end
  end

  class Vec
    attr_reader :items
    attr_accessor :multiline_source, :line, :column

    def initialize(items)
      @items = items
      @multiline_source = false
    end

    def to_ary
      @items
    end

    def inspect
      "[#{@items.map(&:inspect).join(' ')}]"
    end
  end

  class HashLit
    attr_reader :entries
    attr_accessor :multiline_source, :line, :column

    def initialize(entries)
      @entries = entries
      @multiline_source = false
    end

    def inspect
      pairs.map { |k, v| "#{k.inspect} #{v.inspect}" }.then { |p| "{#{p.join(' ')}}" }
    end

    def pairs
      @entries.grep(Array)
    end

    def all_sym_keys?
      pairs.any? && pairs.all? { |key, _| key.is_a?(Symbol) }
    end
  end

  class List
    attr_reader :items
    attr_accessor :multiline_source, :line, :column, :sigil

    def initialize(items)
      @items = items
      @multiline_source = false
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

    def inspect
      "(#{@items.map(&:inspect).join(' ')})"
    end
  end

  class AutoGensym < Sym
    def inspect
      "#<AutoGensym #{@name}#>"
    end
  end

  class MacroSym < Sym
    def inspect
      "#<MacroSym #{@name}>"
    end
  end

  class Quasiquote
    attr_reader :form
    attr_accessor :line, :column

    def initialize(form)
      @form = form
    end

    def inspect
      "`#{@form.inspect}"
    end
  end

  class Unquote
    attr_reader :form
    attr_accessor :line, :column

    def initialize(form)
      @form = form
    end

    def inspect
      ",#{@form.inspect}"
    end
  end

  class UnquoteSplice
    attr_reader :form
    attr_accessor :line, :column

    def initialize(form)
      @form = form
    end

    def inspect
      ",@#{@form.inspect}"
    end
  end
end
