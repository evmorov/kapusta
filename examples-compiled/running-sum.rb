def same_list?(a, b)
  ok = a.length == b.length
  a.each_with_index do |value, i|
    ok = false if !(value == b[i])
  end
  ok
end

def running_sum(nums)
  total = 0
  nums.filter_map do |n|
    begin
      total += n
      total
    end
  end
end

p same_list?([1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 66, 78], running_sum([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]))
p same_list?([1, 2, 3, 4, 5], running_sum([1, 1, 1, 1, 1]))
p same_list?([3, 4, 6, 16, 17], running_sum([3, 1, 2, 10, 1]))
