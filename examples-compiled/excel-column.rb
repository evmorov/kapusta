module Excel
  class << self
    def to_number(title)
      result = 0
      title.chars.each do |ch|
        result = (result * 26) + (ch.ord - 64)
      end
      result
    end

    def to_title(number)
      n = number
      chars = []
      while n > 0
        n -= 1
        code = 65 + (n % 26)
        chars.unshift(code.chr)
        n /= 26
      end
      chars.join("")
    end
  end
end

p Excel.to_number("A")
p Excel.to_number("AB")
p Excel.to_number("ZY")
p Excel.to_title(1)
p Excel.to_title(28)
p Excel.to_title(701)
