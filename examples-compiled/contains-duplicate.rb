def contains_duplicate?(nums)
  (-> do
    seen = (-> do
      kap_result_1 = {}
        nums.each do |n|
        kap_pair_2 = [n, true]
        if kap_pair_2.is_a?(Array) && kap_pair_2.length == 2 && !kap_pair_2[0].nil? && !kap_pair_2[1].nil?
          kap_result_1[kap_pair_2[0]] = kap_pair_2[1]
        end
      end
      kap_result_1
    end).call
    seen.length < nums.length
  end).call
end
p contains_duplicate?([1, 2, 3, 1])
p contains_duplicate?([1, 2, 3, 4])
p contains_duplicate?([1, 1, 1, 3, 3, 4, 3, 2, 4, 2])
