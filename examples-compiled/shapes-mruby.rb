def area(shape)
  case
  when shape.is_a?(Array) && shape.length >= 2 && shape[0] == :circle && (r = shape[1]) != nil
    3.14 * r * r
  when shape.is_a?(Array) && shape.length >= 2 && shape[0] == :square && (s = shape[1]) != nil
    s * s
  when shape.is_a?(Array) && shape.length >= 3 && shape[0] == :rect && (w = shape[1]) != nil && (h = shape[2]) != nil
    w * h
  else
    0
  end
end
[[:circle, 5], [:square, 3], [:rect, 2, 4], [:dot]].each do |s|
  p area(s)
end
