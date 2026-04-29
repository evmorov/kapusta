# frozen_string_literal: true

module Kapusta
  module Compiler
    module MacroGensym
      @counter = 0

      class << self
        def fresh_gensym(prefix)
          @counter += 1
          GeneratedSym.new("#{prefix}_g#{@counter}", @counter)
        end

        def fresh_local_gensym(prefix)
          @counter += 1
          GeneratedSym.new("#{prefix}_local_#{@counter}", @counter)
        end
      end
    end
  end
end
