def move_zeroes(nums)
  write = 0
  0.step(nums.length - 1) do |read|
    if nums[read] != 0
      nums[write] = nums[read]
      write = write + 1
    end
  end
  write.step(nums.length - 1) do |i|
    nums[i] = 0
  end
  nums
end
p(move_zeroes([0, 1, 0, 3, 12]))
p(move_zeroes([0]))
p(move_zeroes([1, 2, 3]))
