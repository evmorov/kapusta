def describe(x)
  case
  when x == 0
    "zero"
  when x == 1
    "one"
  when (n = x) != nil && n < 0
    "negative"
  else
    "many"
  end
end
define_singleton_method(:describe) do |*args|
  Object.instance_method(:describe).bind(self).call(*args)
end
[-3, 0, 1, 2, 99].each do |n|
  p(n, describe(n))
end
