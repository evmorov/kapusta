def require_score(s)
  if s == "oops"
    Kernel.raise(ArgumentError.new("not a number"))
  else
    s.to_i
  end
end
def parse_score(s)
  begin
    require_score(s)
  rescue ArgumentError => e
    "bad: " + s.to_s
  ensure
    p("seen: " + s.to_s)
  end
end
["12", "oops"].each_with_index do |kap_value_1, kap_index_2|
  s = kap_value_1
  p parse_score(s)
end
nil
