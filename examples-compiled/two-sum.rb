def two_sum(xs, target)
  i = 0
  answer = nil
  while (i < xs.length) && answer.nil?
    j = i + 1
    while (j < xs.length) && answer.nil?
      if (xs[i] + xs[j]) == target
        answer = [i, j]
      end
      j += 1
    end
    i += 1
  end
  answer
end
(-> do
  first_pair = two_sum([2, 7, 11, 15], 9)
  second_pair = two_sum([3, 2, 4], 6)
  missing_pair = two_sum([1, 2, 3], 10)
  p first_pair
  p second_pair
  p missing_pair
end).call
