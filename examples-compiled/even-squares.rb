(-> do
  even_squares = ([1, 2, 3, 4, 5, 6].select do |n|
    n.even?
  end).map do |n|
    n * n
  end
  p even_squares.join(", ")
end).call
