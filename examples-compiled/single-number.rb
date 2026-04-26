def single_number(nums)
  (-> do
    acc = 0
    nums.each do |n|
      acc = acc ^ n
    end
    acc
  end).call
end
p single_number([2, 2, 1])
p single_number([4, 1, 2, 1, 2])
p single_number([1])
