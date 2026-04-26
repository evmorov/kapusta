def prime?(n)
  ok = true
  2.step(n - 1) do |d|
    break if !ok
    ok = false if 0 == (n % d)
  end
  (n > 1) && ok
end
(-> do
  ps = (-> do
    kap_result_1 = []
    2.step(30) do |n|
      kap_value_2 = n if prime?(n)
      kap_result_1 << kap_value_2 unless kap_value_2.nil?
    end
    kap_result_1
  end).call
  ps.each do |p|
    p p
  end
end).call
