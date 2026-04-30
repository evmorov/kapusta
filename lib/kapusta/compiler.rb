# frozen_string_literal: true

require_relative 'error'
require_relative 'compiler/lua_compat'
require_relative 'compiler/normalizer'
require_relative 'compiler/emitter'
require_relative 'compiler/macro_expander'

module Kapusta
  module Compiler
    class Error < Kapusta::Error; end
    CORE_SPECIAL_FORMS = %w[
      fn lambda λ let local var global set if when unless case match
      while for each do values
      -> ->> -?> -?>> doto
      icollect collect fcollect accumulate faccumulate
      hashfn
      . ?. :
      ..
      length
      require
      module class end
      try catch finally
      raise
      ivar cvar gvar
      ruby
      tset
      and or not
      = not= < <= > >=
      + - * / %
      print
      macro macros import-macros
      quasi-sym quasi-list quasi-list-tail quasi-vec quasi-vec-tail quasi-hash quasi-gensym
    ].freeze
    SPECIAL_FORMS = (CORE_SPECIAL_FORMS + LuaCompat::SPECIAL_FORMS).freeze

    def self.compile(source, path: '(kapusta)', target: nil)
      forms = Reader.read_all(source)
      expanded = MacroExpander.new(path:).expand_all(forms)
      compile_forms(expanded, path:, target:)
    rescue Kapusta::Error => e
      raise e.with_defaults(path:)
    end

    def self.compile_forms(forms, path: '(kapusta)', target: nil)
      normalized = Normalizer.new.normalize_all(forms)
      Emitter.new(path:, target: normalize_target(target)).emit_file(normalized)
    rescue Kapusta::Error => e
      raise e.with_defaults(path:)
    end

    def self.run(source, path: '(kapusta)')
      ruby = compile(source, path:)
      TOPLEVEL_BINDING.eval(ruby, path, 1)
    end

    def self.run_file(path)
      run(File.read(path), path:)
    end

    def self.normalize_target(target)
      case target
      when nil then nil
      when :mruby, 'mruby' then :mruby
      else
        raise Error, Kapusta::Errors.format(:unknown_target, target: target.inspect)
      end
    end
  end
end
