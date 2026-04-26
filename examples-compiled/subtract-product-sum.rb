def subtract_product_sum(n)
  x = n
  product = 1
  sum = 0
  while x > 0
    d = x % 10
    product *= d
    sum += d
    x = (x / 10).floor
  end
  product - sum
end
p subtract_product_sum(234)
p subtract_product_sum(4421)
p subtract_product_sum(1)
