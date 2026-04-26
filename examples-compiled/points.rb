def point_kind(point)
  (-> do
    kap_case_value_1 = point
    case kap_case_value_1
    in [0, 0, *]
      "origin"
    in [0, _, *]
      "y-axis"
    in [_, 0, *]
      "x-axis"
    in [_, _, *]
      "point"
    else
      nil
    end
  end).call
end
[[0, 0], [0, 2], [3, 0], [3, 4]].each do |point|
  p point_kind(point)
end
