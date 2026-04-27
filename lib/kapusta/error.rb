# frozen_string_literal: true

module Kapusta
  class Error < StandardError
    attr_reader :path, :line, :column, :reason

    def initialize(reason, path: nil, line: nil, column: nil)
      @reason = reason
      @path = path
      @line = line
      @column = column
      super(formatted)
    end

    def formatted
      prefix = [path, line, column].compact.join(':')
      prefix.empty? ? reason : "#{prefix}: #{reason}"
    end

    def with_defaults(path: nil, line: nil, column: nil)
      copy = self.class.new(@reason,
                            path: @path || path,
                            line: @line || line,
                            column: @column || column)
      copy.set_backtrace(backtrace) if backtrace
      copy
    end
  end
end
