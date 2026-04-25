(-> do
  xs = [10, 20, 30, 40]
  total = (-> do
    s = 0
    xs.each_with_index do |x, _|
    s = begin
      s + x
    end
  end
    s
  end).call
  p total
end).call
