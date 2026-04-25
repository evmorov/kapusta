(-> do
    __doto__ = 99
  xs = []
  kap_doto_1 = xs
  kap_doto_1.push(__doto__)
  kap_doto_1
  p(xs.inspect)
end).call
