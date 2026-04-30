def swap_kind(v)
  case
  when v.is_a?(Array) && v.length >= 3 && v[0] == :pair && (x = v[1]) != nil && (y = v[2]) != nil
    x.to_s + ":" + y.to_s
  when v.is_a?(Array) && v.length >= 3 && v[0] == :flipped && (y = v[1]) != nil && (x = v[2]) != nil
    x.to_s + ":" + y.to_s
  else
    "other"
  end
end
p swap_kind([:pair, 1, 2])
p swap_kind([:flipped, 1, 2])
p swap_kind([:nope, 1, 2])
