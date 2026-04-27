def contains_duplicate?(nums)
  (-> do
    seen = nums.each_with_object({}) do |n, kap_result_1|
      kap_result_1[n] = true unless n.nil?
    end
    seen.length < nums.length
  end).call
end
p contains_duplicate?([1, 2, 3, 1])
p contains_duplicate?([1, 2, 3, 4])
p contains_duplicate?([1, 1, 1, 3, 3, 4, 3, 2, 4, 2])
