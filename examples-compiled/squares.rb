(-> do
  xs = [1, 2, 3, 4, 5]
  ys = xs.filter_map do |x|
    x * x
  end
  ys.each do |y|
    p y
  end
end).call
