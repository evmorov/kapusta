def ugly?(n)
  x = n
  if n <= 0
    false
  else
    while 0 == (x % 2)
      x = (x / 2).floor
    end
    while 0 == (x % 3)
      x = (x / 3).floor
    end
    while 0 == (x % 5)
      x = (x / 5).floor
    end
    x == 1
  end
end
p ugly?(6)
p ugly?(1)
p ugly?(14)
p ugly?(0)
p ugly?(30)
