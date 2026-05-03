def equal_sums?(a, b)
  (a.inject(0) do |s, x|
    s + x
  end) == (b.inject(0) do |s, x|
    s + x
  end)
end
p equal_sums?([1, 2, 3], [3, 2, 1])
p equal_sums?([1, 2, 3], [4, 5, 6])
p equal_sums?([0], [0])
