def max_profit(prices)
  min_price = prices[0]
  best = 0
  1.step(prices.length - 1) do |i|
    p = prices[i]
    min_price = p if p < min_price
    best = p - min_price if (p - min_price) > best
  end
  best
end
p max_profit([7, 1, 5, 3, 6, 4])
p max_profit([7, 6, 4, 3, 1])
p max_profit([2, 4, 1])
