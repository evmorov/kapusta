def prime?(n)
  ok = true
  2.step(n - 1) do |d|
    break if !ok
    if 0 == (n % d)
      ok = false
    end
  end
  (n > 1) && ok
end
(-> do
  ps = (-> do
    kap_result_1 = []
      2.step(30) do |n|
      kap_value_2 = begin
        if prime?(n)
          n
        end
      end
      kap_result_1 << kap_value_2 unless kap_value_2.nil?
    end
    kap_result_1
  end).call
  ps.each_with_index do |kap_value_3, kap_index_4|
    nil
  p = kap_value_3
    p(p)
  end
  nil
end).call
