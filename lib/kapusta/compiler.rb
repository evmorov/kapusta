# frozen_string_literal: true

require_relative 'error'
require_relative 'compiler/runtime'
require_relative 'compiler/normalizer'
require_relative 'compiler/emitter'

module Kapusta
  module Compiler
    class Error < Kapusta::Error; end
    SPECIAL_FORMS = %w[
      fn lambda λ let local var set if when unless case match
      while for each do values
      -> ->> -?> -?>> doto
      icollect collect fcollect accumulate faccumulate
      hashfn
      . ?. :
      ..
      length
      require
      module class
      try catch finally
      raise
      ivar cvar gvar
      ruby
      tset pcall xpcall
      and or not
      = not= < <= > >=
      + - * / %
      print
    ].freeze

    def self.compile(source, path: '(kapusta)')
      forms = Reader.read_all(source)
      normalized = Normalizer.new.normalize_all(forms)
      Emitter.new(path:).emit_file(normalized)
    end

    def self.run(source, path: '(kapusta)')
      ruby = compile(source, path:)
      TOPLEVEL_BINDING.eval(ruby, path, 1)
    end

    def self.run_file(path)
      run(File.read(path), path:)
    end
  end
end
