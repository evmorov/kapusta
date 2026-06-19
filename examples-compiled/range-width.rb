def range_width(lo, hi)
  hi - lo
end

def min_max_range(nums)
  lo = 1000000
  hi = -1000000
  nums.each do |n|
    lo = n if n < lo
    hi = n if n > hi
  end
  range_width(*[lo, hi])
end

p min_max_range([4, 2, 9, 1, 7])
p min_max_range([10, 10, 10])
p min_max_range([-3, 8, 0, 5])
