def show_case(seq, packet)
  case
  when packet.is_a?(Array) && packet.length >= 2 && packet[0] == :ping && (seq_2 = packet[1]) != nil
    "ping:" + seq_2.to_s
  else
    "other"
  end
end
def show_match(seq, packet)
  case
  when packet.is_a?(Array) && packet.length >= 2 && packet[0] == :ping && packet[1] == seq
    "ping:" + seq.to_s
  else
    "other"
  end
end
p("case: " + show_case(42, [:ping, 7]).to_s)
p("case: " + show_case(42, [:ping, 42]).to_s)
p("match: " + show_match(42, [:ping, 7]).to_s)
p("match: " + show_match(42, [:ping, 42]).to_s)
