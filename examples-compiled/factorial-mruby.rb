def factorial(n)
  case
  when n == 0
    1
  when n == 1
    1
  else
    n * factorial(n - 1)
  end
end
[0, 1, 5, 6, 10].each do |n|
  p(n, factorial(n))
end
