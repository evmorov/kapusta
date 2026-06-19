def minimum_start_value(nums)
  prefix = 0
  lowest = 0
  nums.each do |n|
    prefix += n
    lowest = prefix if prefix < lowest
  end
  [1 + (-lowest), prefix]
end

start, total = minimum_start_value([-3, 2, -3, 4, 2])
p start
p total
start, total = minimum_start_value([1, 2])
p start
p total
start, total = minimum_start_value([1, -2, -3])
p start
p total
