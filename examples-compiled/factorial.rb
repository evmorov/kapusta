def factorial(n)
  case n
  in 0
    1
  in 1
    1
  in _
    n * factorial(n - 1)
  end
end
[0, 1, 5, 6, 10].each do |n|
  p(n, factorial(n))
end
