def egg_count(number)
  odd_q = ->(*kap_args_1) do
    (kap_args_1[0] % 2) > 0
  end
  n = number
  eggs = 0
  while n > 0
    if odd_q.call(n)
      eggs = eggs + 1
    end
    n = (n / 2).floor
  end
  eggs
end
p egg_count(30)
