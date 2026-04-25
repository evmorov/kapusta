def single_number(nums)
  (-> do
    acc = 0
    nums.each_with_index do |kap_value_1, kap_index_2|
    nil
    n = kap_value_1
    acc = begin
      acc ^ n
    end
  end
    acc
  end).call
end
p single_number([2, 2, 1])
p single_number([4, 1, 2, 1, 2])
p single_number([1])
