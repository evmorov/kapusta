(-> do
    even_squares = (([1, 2, 3, 4, 5, 6]).select(&proc do |n|
    n.even?
  end)).map(&proc do |n|
    n * n
  end)
  p(even_squares.join(", "))
end).call
