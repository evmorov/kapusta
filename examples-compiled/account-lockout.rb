MAX_MISSED = 3
def classify(guesses)
  missed = 0
  guesses.each do |g|
    missed += 1 if g == 1
  end
  if missed < MAX_MISSED
    :ok
  else
    :locked
  end
end
p classify([0, 1, 0, 1])
p classify([1, 1, 1])
p classify([1, 1, 1, 0])
