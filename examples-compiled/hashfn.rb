add = proc do
  _1 + _2
end
triple = proc do
  3 * _1
end
p add.call(2, 3)
p triple.call(7)
