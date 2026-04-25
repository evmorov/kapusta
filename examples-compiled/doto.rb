(-> do
  xs = (-> do
    kap_doto_1 = []
    kap_doto_1.push(1)
    kap_doto_1.push(2)
    kap_doto_1.push(3)
    kap_doto_1
  end).call
  p(xs.join(", "))
end).call
