(-> do
  two_sum_hash = proc do |nums, target, seen|
    i = 0
    answer = nil
    while (i < nums.length) && (answer == nil)
      n = nums[i]
      complement = target - n
      if seen.key?(complement)
        answer = [seen[complement], i]
      else
        seen[n] = i
      end
      i = i + 1
    end
    answer
  end
  p two_sum_hash.call([2, 7, 11, 15], 9, {})
  p two_sum_hash.call([3, 2, 4], 6, {})
  p two_sum_hash.call([1, 2, 3], 10, {})
end).call
