def debug_data(packet, seq)
  no_nil = proc do
    _1 || "nil"
  end
  _, packet_seq = packet
  "packet[:ping, " + no_nil.call(packet_seq).to_s + "] seq " + no_nil.call(seq).to_s
end
def show_case(packet, seq)
  case packet
  in [:ping, seq, *] if !seq.nil?
    debug_data(packet, seq)
  in _
    "other"
  end
end
def show_match(packet, seq)
  case packet
  in [:ping, ^(seq), *]
    debug_data(packet, seq)
  in _
    "other"
  end
end
p("case: " + show_case([:ping, 42], 7).to_s)
p("case: " + show_case([:ping, 42], nil).to_s)
p("case: " + show_case([:ping, nil], nil).to_s)
p("case: " + show_case([:ping, 42], 42).to_s)
p("match: " + show_match([:ping, 42], 7).to_s)
p("match: " + show_match([:ping, 42], nil).to_s)
p("match: " + show_match([:ping, nil], nil).to_s)
p("match: " + show_match([:ping, 42], 42).to_s)
