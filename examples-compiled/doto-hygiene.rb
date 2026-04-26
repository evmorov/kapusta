(-> do
  __doto__ = 99
  xs = []
  doto_1 = xs
  doto_1.push(__doto__)
  doto_1
  p xs.inspect
end).call
