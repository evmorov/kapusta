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
  add_drop.call("Pling") if div_q.call(n, 3)
  add_drop.call("Plang") if div_q.call(n, 5)
  add_drop.call("Plong") if div_q.call(n, 7)
  if empty_q.call(drops)
    n.to_s
  else
    drops.join
  end
end
p raindrops(15)
