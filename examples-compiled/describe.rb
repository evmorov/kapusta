def describe(x)
  case x
  in 0
    "zero"
  in 1
    "one"
  in n if !n.nil? && n < 0
    "negative"
  in _
    "many"
  end
end
define_singleton_method(:describe, Object.instance_method(:describe).bind(self))
[-3, 0, 1, 2, 99].each do |n|
  p(n, describe(n))
end
