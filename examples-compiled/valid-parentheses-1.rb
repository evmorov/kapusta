class ValidParenthesesSolution
  def initialize
    @pairs = {")" => "(", "]" => "[", "}" => "{"}
  end
  def valid?(s)
    (-> do
      pairs = @pairs
      stack = []
      chars = s.chars
      i = 0
      ok = true
      while ok && (i < chars.length)
        ch = chars[i]
        if pairs.key?(ch)
          if (-> do
            kap_thread_1 = stack.pop
            if kap_thread_1.nil?
              nil
            else
              kap_thread_1 == pairs[ch]
            end
          end).call
            nil
          else
            ok = false
          end
        else
          stack.push(ch)
        end
        i = i + 1
      end
      ok && stack.empty?
    end).call
  end
end
ValidParenthesesSolution
