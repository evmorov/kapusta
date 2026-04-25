(-> do
  xs = [1, 2, 3, 4, 5]
  ys = (-> do
    kap_result_1 = []
      xs.each_with_index do |x, kap_index_2|
      kap_value_3 = begin
        x * x
      end
      kap_result_1 << kap_value_3 unless kap_value_3.nil?
    end
    kap_result_1
  end).call
  ys.each_with_index do |y, kap_index_4|
    p y
  end
  nil
end).call
