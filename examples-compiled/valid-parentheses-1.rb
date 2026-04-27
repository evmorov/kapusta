class ValidParenthesesSolution
  def initialize
    @pairs = {")" => "(", "]" => "[", "}" => "{"}
  end
  def valid?(s)
    pairs = @pairs
    stack = []
    chars = s.chars
    i = 0
    ok = true
    while ok && (i < chars.length)
      ch = chars[i]
      if pairs.key?(ch)
        if (-> do
          thread_1 = stack.pop
          if thread_1.nil?
            nil
          else
            thread_1 == pairs[ch]
          end
        end).call
          nil
        else
          ok = false
        end
      else
        stack.push(ch)
      end
      i += 1
    end
    ok && stack.empty?
  end
end
ValidParenthesesSolution
