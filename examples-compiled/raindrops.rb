def raindrops(n)
  div_q = ->(*kap_args_1) do
    0 == (kap_args_1[0] % kap_args_1[1])
  end
  empty_q = ->(*kap_args_2) do
    0 == kap_args_2[0].length
  end
  drops = []
  add_drop = ->(*kap_args_3) do
    drops.push(kap_args_3[0])
  end
  if div_q.call(n, 3)
    add_drop.call("Pling")
  end
  if div_q.call(n, 5)
    add_drop.call("Plang")
  end
  if div_q.call(n, 7)
    add_drop.call("Plong")
  end
  if empty_q.call(drops)
    send(:tostring, n)
  else
    drops.join
  end
end
p(raindrops(15))
