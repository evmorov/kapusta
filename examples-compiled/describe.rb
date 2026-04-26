def describe(x)
  (-> do
    kap_case_value_1 = x
    case kap_case_value_1
    in 0
      "zero"
    in 1
      "one"
    in n if !n.nil? && n < 0
      "negative"
    in _
      "many"
    else
      nil
    end
  end).call
end
define_singleton_method(:describe, Object.instance_method(:describe).bind(self))
[-3, 0, 1, 2, 99].each_with_index do |n, _|
  p(n, describe(n))
end
