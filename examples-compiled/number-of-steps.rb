TARGET = 0
def steps_to_zero(n)
  x = n
  steps = 0
  while x != TARGET
    if 0 == (x % 2)
      x = (x / 2).floor
    else
      x -= 1
    end
    steps += 1
  end
  steps
end
p steps_to_zero(14)
p steps_to_zero(8)
p steps_to_zero(123)
