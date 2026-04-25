(-> do
  xs = [1, 2, 3, 4, 5]
  ys = (-> do
    kap_result_1 = []
      xs.each_with_index do |x, _|
      kap_value_2 = begin
        x * x
      end
      kap_result_1 << kap_value_2 unless kap_value_2.nil?
    end
    kap_result_1
  end).call
  ys.each_with_index do |y, _|
    p y
  end
  nil
end).call
