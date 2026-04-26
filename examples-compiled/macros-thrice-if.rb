counter = 0
ready_q = nil
ready_q = proc do
  counter < 5
end
tick = nil
tick = proc do
  counter += 1
  p("tick", counter)
end
if ready_q.call
  tick.call
  if ready_q.call
    tick.call
    if ready_q.call
      tick.call
      nil
    end
  end
end
p("final", counter)
