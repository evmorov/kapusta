def climb_stairs(n)
  prev = 1
  curr = 1
  2.step(n) do
    _next = prev + curr
    prev = curr
    curr = _next
  end
  curr
end
p(climb_stairs(2))
p(climb_stairs(3))
p(climb_stairs(5))
p(climb_stairs(10))
