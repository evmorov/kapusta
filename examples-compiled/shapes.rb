def area(shape)
  case shape
  in [:circle, r, *] if !r.nil?
    3.14 * r * r
  in [:square, s, *] if !s.nil?
    s * s
  in [:rect, w, h, *] if !w.nil? && !h.nil?
    w * h
  in _
    0
  end
end
[[:circle, 5], [:square, 3], [:rect, 2, 4], [:dot]].each do |s|
  p area(s)
end
