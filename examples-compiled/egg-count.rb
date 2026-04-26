def egg_count(number)
  odd_q = proc do
    (_1 % 2) > 0
  end
  n = number
  eggs = 0
  while n > 0
    if odd_q.call(n)
      eggs += 1
    end
    n = (n / 2).floor
  end
  eggs
end
p egg_count(30)
