def max_subarray_step(current, best, n)
  extended = current + n
  next_current = if extended > n
    extended
  else
    n
  end
  next_best = if next_current > best
    next_current
  else
    best
  end
  [next_current, next_best]
end

def max_subarray_state(nums)
  current = 0
  best = 0
  initialized_q = false
  nums.each do |n|
    if initialized_q
      lambda do
        next_current, next_best = max_subarray_step(current, best, n)
        current = next_current
        best = next_best
      end.call
    else
      current = n
      best = n
      initialized_q = true
    end
  end
  [current, best]
end

def max_subarray(nums)
  _current, best = max_subarray_state(nums)
  best
end

p max_subarray([-2, 1, -3, 4, -1, 2, 1, -5, 4])
p max_subarray([1])
p max_subarray([5, 4, -1, 7, 8])
