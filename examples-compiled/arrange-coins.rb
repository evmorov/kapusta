def arrange_coins(n)
  rows = (-> do
    acc = {:sum => 0, :rows => 0}
    1.step(n) do |i|
      acc = begin
        (-> do
          new_sum = acc[:sum] + i
          if new_sum <= n
            {:sum => new_sum, :rows => i}
          else
            acc
          end
        end).call
      end
    end
    acc
  end).call
  used = (-> do
    acc = {:sum => 0, :rows => 0}
    1.step(n) do |i|
      acc = begin
        (-> do
          new_sum = acc[:sum] + i
          if new_sum <= n
            {:sum => new_sum, :rows => i}
          else
            acc
          end
        end).call
      end
    end
    acc
  end).call
  [rows[:rows], used[:sum]]
end
r, u = arrange_coins(0)
p r
p u
r, u = arrange_coins(1)
p r
p u
r, u = arrange_coins(5)
p r
p u
r, u = arrange_coins(8)
p r
p u
r, u = arrange_coins(10)
p r
p u
