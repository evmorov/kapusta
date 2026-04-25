(-> do
    even_squares = (([1, 2, 3, 4, 5, 6]).public_send(:select, &proc do |n|
    n.even?
  end)).public_send(:map, &proc do |n|
    n * n
  end)
  p(even_squares.join(", "))
end).call
