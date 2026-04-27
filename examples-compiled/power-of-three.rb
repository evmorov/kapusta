def power_of_three?(n)
  x = n
  while (x > 1) && (0 == (x % 3))
    x /= 3
  end
  x == 1
end
p power_of_three?(27)
p power_of_three?(9)
p power_of_three?(45)
p power_of_three?(1)
