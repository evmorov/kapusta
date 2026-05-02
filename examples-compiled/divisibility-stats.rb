def divisibility_stats(n)
  threes = (-> do
    acc = 0
    1.step(n) do |i|
      acc = begin
        (-> do
          step = if 0 == (i % 3)
            1
          else
            0
          end
          acc + step
        end).call
      end
    end
    acc
  end).call
  fives = (-> do
    acc = 0
    1.step(n) do |i|
      acc = begin
        (-> do
          step = if 0 == (i % 5)
            1
          else
            0
          end
          acc + step
        end).call
      end
    end
    acc
  end).call
  [threes, fives]
end
t, f = divisibility_stats(30)
p t
p f
t, f = divisibility_stats(100)
p t
p f
