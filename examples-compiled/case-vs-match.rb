def show_case(packet, seq)
  case packet
  in [:ping, seq, *] if !seq.nil?
    "packet[:ping, " + seq.to_s + "] seq " + seq.to_s
  in _
    "other"
  end
end
def show_match(packet, seq)
  case packet
  in [:ping, ^(seq), *]
    "packet[:ping, " + seq.to_s + "] seq " + seq.to_s
  in _
    "other"
  end
end
p("case: " + show_case([:ping, 42], 7).to_s)
p("case: " + show_case([:ping, 42], nil).to_s)
p("case: " + show_case([:ping, 42], 42).to_s)
p("match: " + show_match([:ping, 42], 7).to_s)
p("match: " + show_match([:ping, 42], nil).to_s)
p("match: " + show_match([:ping, 42], 42).to_s)
