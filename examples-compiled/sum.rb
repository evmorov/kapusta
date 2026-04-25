(-> do
  xs = [10, 20, 30, 40]
  total = (-> do
    s = 0
    xs.each_with_index do |x, _|
      s = s + x
    end
    s
  end).call
  p total
end).call
