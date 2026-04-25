def roman_to_integer(s)
  (-> do
    values = {"I" => 1, "V" => 5, "X" => 10, "L" => 50, "C" => 100, "D" => 500, "M" => 1000}
    chars = s.chars
    n = chars.length
    total = 0
    i = 0
    while i < n
      curr = values[chars[i]]
      ahead = if (i + 1) < n
        values[chars[i + 1]]
      else
        0
      end
      subtract_q = curr < ahead
      total = total + (if subtract_q
        ahead - curr
      else
        curr
      end)
      i = i + (if subtract_q
        2
      else
        1
      end)
    end
    total
  end).call
end
p(roman_to_integer("III"))
p(roman_to_integer("LVIII"))
p(roman_to_integer("MCMXCIV"))
