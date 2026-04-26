result = (-> do
  v_g2 = 1 + 2 + 3
  p("dbg", v_g2)
  v_g2
end).call
p("result", result)
(-> do
  v_g3 = 10 * (2 + 3)
  p("dbg", v_g3)
  v_g3
end).call
