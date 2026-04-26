(-> do
  xs = [10, 20, 30, 40]
  total = xs.inject(0) do |s, x|
    s + x
  end
  p total
end).call
