def reverse_integer(x)
  sign = if x < 0
    -1
  else
    1
  end
  remaining = x * sign
  result = 0
  while remaining > 0
    result = (result * 10) + (remaining % 10)
    remaining = (remaining / 10).floor
  end
  result * sign
end
p reverse_integer(123)
p reverse_integer(-123)
p reverse_integer(120)
p reverse_integer(0)
