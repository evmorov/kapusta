(-> do
    xs = [3, 1, 2]
  sorted = xs.sort(&proc do |a, b|
    b.public_send(:<=>, a)
  end)
  p(sorted.join(", "))
end).call
