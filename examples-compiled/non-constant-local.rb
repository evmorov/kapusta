hash_fn = proc do
  _1 || "nil"
end
regular_fn = proc do |x|
  x + 1
end
lambda_fn = proc do |x|
  x * 2
end
vec_binding = [10, 20, 30]
hash_binding = {:a => 1}
p hash_fn.call(nil)
p regular_fn.call(5)
p lambda_fn.call(5)
p vec_binding.length
p hash_binding[:a]
