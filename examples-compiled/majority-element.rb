def majority(nums)
  candidate = nil
  count = 0
  nums.each do |n|
    candidate = n if count == 0
    if n == candidate
      count += 1
    else
      count -= 1
    end
  end
  candidate
end
p majority([3, 2, 3])
p majority([2, 2, 1, 1, 1, 2, 2])
p majority([1])
