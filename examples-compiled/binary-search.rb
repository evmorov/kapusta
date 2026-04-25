def binary_search(xs, target)
  lo = 0
  hi = xs.length - 1
  answer = nil
  while (lo <= hi) && answer.nil?
    mid = ((lo + hi) / 2).floor
    guess = xs[mid]
    if guess == target
      answer = mid
    elsif guess < target
      lo = mid + 1
    else
      hi = mid - 1
    end
  end
  answer
end
(-> do
  found = binary_search([1, 3, 5, 7, 9, 11], 7)
  missing = binary_search([1, 3, 5, 7, 9, 11], 2)
  p found
  p missing
end).call
