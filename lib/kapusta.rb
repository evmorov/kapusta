# frozen_string_literal: true

require_relative 'kapusta/version'
require_relative 'kapusta/error'
require_relative 'kapusta/support'
require_relative 'kapusta/ast'
require_relative 'kapusta/reader'
require_relative 'kapusta/env'
require_relative 'kapusta/compiler'

module Kapusta
  def self.eval(source, path: '(eval)', **_opts)
    Compiler.run(source, path:)
  end

  def self.dofile(path, **_opts)
    source = File.read(path)
    self.eval(source, path:)
  end

  def self.compile(source, path: '(eval)', **_opts)
    Compiler.compile(source, path:)
  end

  def self.install!
    @install ||= begin
      require 'rubygems'
      true
    end
  end
end
