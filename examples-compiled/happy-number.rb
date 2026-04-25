def sum_of_squares(n)
  x = n
  total = 0
  while x > 0
    d = x % 10
    total = total + (d * d)
    x = (x / 10).floor
  end
  total
end
def happy?(n)
  (-> do
      seen = {}
    x = n
    while (x != 1) && !seen.key?(x)
      seen[x] = true
      x = sum_of_squares(x)
    end
    x == 1
  end).call
end
p(happy?(19))
p(happy?(2))
p(happy?(1))
