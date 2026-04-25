def majority(nums)
  candidate = nil
  count = 0
  nums.each do |n|
    if count == 0
      candidate = n
    end
    if n == candidate
      count = count + 1
    else
      count = count - 1
    end
  end
  candidate
end
p majority([3, 2, 3])
p majority([2, 2, 1, 1, 1, 2, 2])
p majority([1])
