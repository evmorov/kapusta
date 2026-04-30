def point_kind(point)
  case
  when point.is_a?(Array) && point.length >= 2 && point[0] == 0 && point[1] == 0
    "origin"
  when point.is_a?(Array) && point.length >= 2 && point[0] == 0
    "y-axis"
  when point.is_a?(Array) && point.length >= 2 && point[1] == 0
    "x-axis"
  when point.is_a?(Array) && point.length >= 2
    "point"
  else
    nil
  end
end
[[0, 0], [0, 2], [3, 0], [3, 4]].each do |point|
  p point_kind(point)
end
