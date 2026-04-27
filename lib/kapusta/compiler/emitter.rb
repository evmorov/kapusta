# frozen_string_literal: true

require_relative 'emitter/support'
require_relative 'emitter/expressions'
require_relative 'emitter/bindings'
require_relative 'emitter/control_flow'
require_relative 'emitter/collections'
require_relative 'emitter/interop'
require_relative 'emitter/patterns'

module Kapusta
  module Compiler
    class Emitter
      RUBY_KEYWORDS = %w[
        BEGIN END alias and begin break case class def defined? do else elsif end ensure false for if in
        module next nil not or redo rescue retry return self super then true undef unless until when while yield
      ].freeze

      include EmitterModules::Support
      include EmitterModules::Expressions
      include EmitterModules::Bindings
      include EmitterModules::ControlFlow
      include EmitterModules::Collections
      include EmitterModules::Interop
      include EmitterModules::Patterns

      def initialize(path:)
        @path = path
        @temp_index = 0
      end

      def emit_file(forms)
        env = Env.new
        body = emit_forms_with_headers(forms, env, :toplevel, result: false)
        "#{body}\n"
      end
    end
  end
end
