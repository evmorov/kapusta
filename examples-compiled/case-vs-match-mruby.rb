def debug_data(packet, seq)
  no_nil = proc do
    _1 || "nil"
  end
  _, packet_seq = packet
  "packet[:ping, " + no_nil.call(packet_seq).to_s + "] seq " + no_nil.call(seq).to_s
end
def show_case(packet, seq)
  case
  when packet.is_a?(Array) && packet.length >= 2 && packet[0] == :ping && (seq_2 = packet[1]) != nil
    debug_data(packet, seq_2)
  else
    "other"
  end
end
def show_match(packet, seq)
  case
  when packet.is_a?(Array) && packet.length >= 2 && packet[0] == :ping && packet[1] == seq
    debug_data(packet, seq)
  else
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
