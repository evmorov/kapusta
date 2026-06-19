def same_list?(a, b)
  ok = a.length == b.length
  a.each_with_index do |value, i|
    ok = false if !(value == b[i])
  end
  ok
end

def abs(n)
  if n < 0
    (-n)
  else
    n
  end
end

def left_right_difference(nums)
  total = nums.inject(0) do |sum, n|
    sum + n
  end
  left = 0
  nums.filter_map do |n|
    begin
      lambda do
        right = total - left - n
        diff = abs(left - right)
        left += n
        diff
      end.call
    end
  end
end

p same_list?([209, 206, 201, 194, 185, 174, 161, 146, 129, 110, 89, 66, 41, 14, 15, 46, 79, 114, 151, 190], left_right_difference([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]))
