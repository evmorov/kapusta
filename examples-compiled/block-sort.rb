(-> do
  xs = [3, 1, 2]
  sorted = xs.sort do |a, b|
    b <=> a
  end
  p sorted.join(", ")
end).call
