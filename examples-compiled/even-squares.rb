def even?(n)
  0 == (n % 2)
end
def select(tbl, pred)
  (-> do
    kap_result_1 = []
    tbl.each do |x|
      kap_value_2 = x if pred.call(x)
      kap_result_1 << kap_value_2 unless kap_value_2.nil?
    end
    kap_result_1
  end).call
end
def map(tbl, f)
  (-> do
    kap_result_3 = []
    tbl.each do |x|
      kap_value_4 = f.call(x)
      kap_result_3 << kap_value_4 unless kap_value_4.nil?
    end
    kap_result_3
  end).call
end
def join(tbl, sep)
  s = ""
  tbl.each do |x|
    if s == ""
      s = x.to_s
    else
      s = s.to_s + sep.to_s + x.to_s
    end
  end
  s
end
(-> do
  xs = [1, 2, 3, 4, 5, 6]
  filtered = select(xs, method(:even?))
  squared = map(filtered, proc do |n|
    n * n
  end)
  p join(squared, ", ")
end).call
