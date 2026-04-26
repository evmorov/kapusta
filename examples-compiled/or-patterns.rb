def swap_kind(v)
  (-> do
    kap_case_value_1 = v
    case kap_case_value_1
    in [:pair, x, y, *] if !x.nil? && !y.nil?
      x.to_s + ":" + y.to_s
    in [:flipped, y, x, *] if !y.nil? && !x.nil?
      x.to_s + ":" + y.to_s
    in _
      "other"
    else
      nil
    end
  end).call
end
p swap_kind([:pair, 1, 2])
p swap_kind([:flipped, 1, 2])
p swap_kind([:nope, 1, 2])
