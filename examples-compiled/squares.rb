(-> do
  xs = [1, 2, 3, 4, 5]
  ys = (-> do
    kap_result_1 = []
    xs.each do |x|
      kap_value_2 = x * x
      kap_result_1 << kap_value_2 unless kap_value_2.nil?
    end
    kap_result_1
  end).call
  ys.each do |y|
    p y
  end
end).call
