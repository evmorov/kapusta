def pivot_index(nums)
  total = 0
  nums.each do |n|
    total = total + n
  end
  left = 0
  found = -1
  nums.each_with_index do |n, i|
    if (found == -1) && (left == (total - left - n))
      found = i
    end
    left = left + n
  end
  found
end
p pivot_index([1, 7, 3, 6, 5, 6])
p pivot_index([1, 2, 3])
p pivot_index([2, 1, -1])
