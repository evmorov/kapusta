def swap_kind(v)
  case v
  in [:pair, x, y, *] if !x.nil? && !y.nil?
    x.to_s + ":" + y.to_s
  in [:flipped, y, x, *] if !y.nil? && !x.nil?
    x.to_s + ":" + y.to_s
  in _
    "other"
  end
end
p swap_kind([:pair, 1, 2])
p swap_kind([:flipped, 1, 2])
p swap_kind([:nope, 1, 2])
