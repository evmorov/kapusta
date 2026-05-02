def show_case(seq, packet)
  case packet
  in [:ping, seq, *] if !seq.nil?
    "ping:" + seq.to_s
  in _
    "other"
  end
end
def show_match(seq, packet)
  case packet
  in [:ping, ^(seq), *]
    "ping:" + seq.to_s
  in _
    "other"
  end
end
p("case: " + show_case(42, [:ping, 7]).to_s)
p("case: " + show_case(42, [:ping, 42]).to_s)
p("match: " + show_match(42, [:ping, 7]).to_s)
p("match: " + show_match(42, [:ping, 42]).to_s)
