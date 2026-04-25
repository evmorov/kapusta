def max_subarray(nums)
  best = nums[0]
  curr = nums[0]
  1.step(nums.length - 1) do |i|
    n = nums[i]
    curr = if (curr + n) > n
      curr + n
    else
      n
    end
    if curr > best
      best = curr
    end
  end
  best
end
p(max_subarray([-2, 1, -3, 4, -1, 2, 1, -5, 4]))
p(max_subarray([1]))
p(max_subarray([5, 4, -1, 7, 8]))
