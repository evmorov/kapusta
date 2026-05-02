def show_case(packet, seq)
  case
  when packet.is_a?(Array) && packet.length >= 2 && packet[0] == :ping && (seq_2 = packet[1]) != nil
    "packet[:ping, " + seq_2.to_s + "] seq " + seq_2.to_s
  else
    "other"
  end
end
def show_match(packet, seq)
  case
  when packet.is_a?(Array) && packet.length >= 2 && packet[0] == :ping && packet[1] == seq
    "packet[:ping, " + seq.to_s + "] seq " + seq.to_s
  else
    "other"
  end
end
p("case: " + show_case([:ping, 42], 7).to_s)
p("case: " + show_case([:ping, 42], nil).to_s)
p("case: " + show_case([:ping, 42], 42).to_s)
p("match: " + show_match([:ping, 42], 7).to_s)
p("match: " + show_match([:ping, 42], nil).to_s)
p("match: " + show_match([:ping, 42], 42).to_s)
