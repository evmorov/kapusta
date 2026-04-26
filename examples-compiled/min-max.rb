def min_max(xs)
  (-> do
    first, *rest = xs
    lo = first
    hi = first
    rest.each_with_index do |x, _|
      if x < lo
        lo = x
      end
      if x > hi
        hi = x
      end
    end
    [lo, hi]
  end).call
end
(-> do
  lo, hi = min_max([3, 1, 4, 1, 5, 9, 2, 6])
  p(lo, hi)
end).call
