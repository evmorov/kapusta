# frozen_string_literal: true

module Kapusta
  module Compiler
    module EmitterModules
      module SimpleExpression
        module_function

        KEYWORDS = %w[nil true false self].freeze

        OPENERS = { '(' => ')', '[' => ']', '{' => '}' }.freeze
        CLOSERS = OPENERS.values.freeze

        # `{...}` is intentionally excluded — a top-level hash or block literal
        # shouldn't be treated as a bare primary even though balanced.
        PRIMARY_OPENERS = { '(' => ')', '[' => ']' }.freeze

        PRIMARY_PATTERNS = [
          /\A-?\d+(?:\.\d+)?/, # number (incl. negative literal)
          /\A:[a-zA-Z_]\w*[!?=]?/, # :symbol
          /\A"(?:[^"\\]|\\.)*"/, # "string"
          /\A'(?:[^'\\]|\\.)*'/, # 'string'
          /\A@@?[a-z_]\w*/, # @ivar / @@cvar
          /\A\$[a-zA-Z_]\w*/, # $gvar
          /\A[A-Z]\w*(?:::[A-Z]\w*)*/, # Constant / A::B::C
          /\A[a-z_]\w*[!?=]?/ # local or bare call head
        ].freeze

        CHAIN_METHOD = /\A\.[a-zA-Z_]\w*[!?=]?/

        def match?(code)
          return false if code.empty? || code.include?("\n")
          return true if KEYWORDS.include?(code)
          return negation?(code) if code.start_with?('!')

          consume(code, 0) == code.length
        end

        def negation?(code)
          return false if code.length < 2

          rest = code[1..]
          match?(rest) || (rest.start_with?('(') && rest.end_with?(')'))
        end

        def consume(code, pos)
          pos = consume_primary(code, pos)
          while pos && pos < code.length
            advanced = consume_segment(code, pos)
            break unless advanced

            pos = advanced
          end
          pos
        end

        def consume_primary(code, pos)
          return consume_group(code, pos) if PRIMARY_OPENERS.key?(code[pos])

          regex = PRIMARY_PATTERNS.find { |re| code[pos..].match?(re) }
          return unless regex

          after = pos + regex.match(code[pos..]).end(0)
          code[after] == '(' ? consume_group(code, after) : after
        end

        def consume_segment(code, pos)
          return consume_group(code, pos) if code[pos] == '['
          return unless code[pos] == '.'

          match = CHAIN_METHOD.match(code[pos..])
          return unless match

          after = pos + match.end(0)
          code[after] == '(' ? consume_group(code, after) : after
        end

        def consume_group(code, pos)
          return unless OPENERS.key?(code[pos])

          stack = [OPENERS[code[pos]]]
          pos += 1
          quote = nil
          while pos < code.length
            ch = code[pos]
            if quote
              if ch == '\\' && pos + 1 < code.length
                pos += 2
              else
                quote = nil if ch == quote
                pos += 1
              end
            elsif ['"', "'"].include?(ch)
              quote = ch
              pos += 1
            elsif OPENERS.key?(ch)
              stack.push(OPENERS[ch])
              pos += 1
            elsif CLOSERS.include?(ch)
              return unless stack.last == ch

              stack.pop
              pos += 1
              return pos if stack.empty?
            else
              pos += 1
            end
          end
          nil
        end
      end
    end
  end
end
