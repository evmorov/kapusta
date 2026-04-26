def single_number(nums)
  nums.inject(0) do |acc, n|
    acc ^ n
  end
end
p single_number([2, 2, 1])
p single_number([4, 1, 2, 1, 2])
p single_number([1])
