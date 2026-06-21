module Digits
  class << self
    def sum(n)
      total = 0
      x = n
      while x > 0
        total += (x % 10)
        x /= 10
      end
      total
    end

    def reverse(n)
      result = 0
      x = n
      while x > 0
        result = (result * 10) + (x % 10)
        x /= 10
      end
      result
    end

    def palindrome?(n)
      n == Digits.reverse(n)
    end
  end
end

p Digits.sum(12345)
p Digits.reverse(1230)
p Digits.palindrome?(121)
p Digits.palindrome?(123)
