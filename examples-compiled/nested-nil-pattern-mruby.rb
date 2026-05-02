def check(packet)
  case
  when packet.is_a?(Array) && packet.length >= 2 && packet[0] == :ping && (seq = packet[1]) != nil
    "got " + seq.to_s
  else
    "other"
  end
end
p check([:ping, 42])
p check([:ping, nil])
