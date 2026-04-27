xs = (-> do
  doto_1 = []
  doto_1.push(1)
  doto_1.push(2)
  doto_1.push(3)
  doto_1
end).call
p xs.join(", ")
