def divisibility_stats(n)
  threes = (1..n).inject(0) do |acc, i|
    (-> do
      step = if 0 == (i % 3)
        1
      else
        0
      end
      acc + step
    end).call
  end
  fives = (1..n).inject(0) do |acc, i|
    (-> do
      step = if 0 == (i % 5)
        1
      else
        0
      end
      acc + step
    end).call
  end
  [threes, fives]
end
t, f = divisibility_stats(30)
p t
p f
t, f = divisibility_stats(100)
p t
p f
