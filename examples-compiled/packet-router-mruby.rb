def inbox_line(user, event)
  case
  when event.is_a?(Array) && event.length >= 3 && event[0] == :score && event[1] == user && (points = event[2]) != nil
    "score:" + points.to_s
  when event.is_a?(Array) && event.length >= 3 && event[0] == :profile && event[1] == user
    q_city = event[2]
    if q_city
      "city:" + q_city.to_s
    else
      "city:nil"
    end
  else
    "other"
  end
end
def score_delta(user, event)
  case
  when event.is_a?(Array) && event.length >= 3 && event[0] == :bonus && event[1] == user && (p = event[2]) != nil && p > 0 && p < 10
    p
  when event.is_a?(Array) && event.length >= 3 && event[0] == :score && event[1] == user && (p = event[2]) != nil && p > 0 && p < 10
    p
  else
    0
  end
end
def packet_kind(packet)
  case
  when packet.is_a?(Array) && packet.length >= 2 && packet[0] == :ping && (seq = packet[1]) != nil
    "ping:" + seq.to_s
  when packet.is_a?(Array) && packet.length >= 2 && packet[0] == :pong && (seq = packet[1]) != nil
    "pong:" + seq.to_s
  else
    "other"
  end
end
p inbox_line("Ada", [:score, "Ada", 9])
p inbox_line("Ada", [:score, "Lin", 7])
p inbox_line("Ada", [:profile, "Ada", nil])
p score_delta("Ada", [:bonus, "Ada", 5])
p score_delta("Ada", [:score, "Lin", 5])
p packet_kind([:ping, 7, :fast])
