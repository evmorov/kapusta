def raindrops(n)
  div_q = proc do
    0 == (_1 % _2)
  end
  empty_q = proc do
    0 == _1.length
  end
  drops = []
  add_drop = proc do
    drops.push(_1)
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
    n.to_s
  else
    drops.join
  end
end
p raindrops(15)
