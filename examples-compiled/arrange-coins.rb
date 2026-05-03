def arrange_coins(n)
  rows = (1..n).inject({:sum => 0, :rows => 0}) do |acc, i|
    (-> do
      new_sum = acc[:sum] + i
      if new_sum <= n
        {:sum => new_sum, :rows => i}
      else
        acc
      end
    end).call
  end
  used = (1..n).inject({:sum => 0, :rows => 0}) do |acc, i|
    (-> do
      new_sum = acc[:sum] + i
      if new_sum <= n
        {:sum => new_sum, :rows => i}
      else
        acc
      end
    end).call
  end
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
