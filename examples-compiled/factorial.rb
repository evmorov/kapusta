def factorial(n)
  (-> do
    kap_case_value_1 = n
    case kap_case_value_1
    in 0
      1
    in 1
      1
    in _
      n * factorial(n - 1)
    else
      nil
    end
  end).call
end
[0, 1, 5, 6, 10].each_with_index do |n, _|
  p(n, factorial(n))
end
