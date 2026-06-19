def add_good_pairs(pairs, counts, n)
  prev = counts[n] || 0
  next_pairs = pairs + prev
  counts[n] = prev + 1
  [next_pairs, counts]
end

def num_identical_pairs(nums)
  pairs = 0
  counts = {}
  nums.each do |n|
    next_pairs, next_counts = add_good_pairs(pairs, counts, n)
    pairs = next_pairs
    counts = next_counts
  end
  pairs
end

p num_identical_pairs([1, 2, 3, 1, 1, 3])
p num_identical_pairs([1, 1, 1, 1])
p num_identical_pairs([1, 2, 3])
