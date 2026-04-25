(-> do
  xs = [1, 2, 3, 4, 5]
  ys = (-> do
    kap_result_1 = []
      xs.each_with_index do |kap_value_2, kap_index_3|
      x = kap_value_2
      kap_value_4 = begin
        x * x
      end
      kap_result_1 << kap_value_4 unless kap_value_4.nil?
    end
    kap_result_1
  end).call
  ys.each_with_index do |kap_value_5, kap_index_6|
    y = kap_value_5
    p y
  end
  nil
end).call
