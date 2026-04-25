(-> do
  xs = [10, 20, 30, 40]
  total = (-> do
    s = 0
    xs.each_with_index do |kap_value_1, kap_index_2|
    x = kap_value_1
    s = begin
      s + x
    end
  end
    s
  end).call
  p total
end).call
