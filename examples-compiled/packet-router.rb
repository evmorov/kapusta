def inbox_line(user, event)
  case event
  in [:score, ^(user), points, *] if !points.nil?
    "score:" + points.to_s
  in [:profile, ^(user), q_city, *]
    if q_city
      "city:" + q_city.to_s
    else
      "city:nil"
    end
  in _
    "other"
  end
end
def score_delta(user, event)
  case event
  in [:bonus, ^(user), p, *] if !p.nil? && p > 0 && p < 10
    p
  in [:score, ^(user), p, *] if !p.nil? && p > 0 && p < 10
    p
  in _
    0
  end
end
def packet_kind(packet)
  case packet
  in [:ping, seq, *] if !seq.nil?
    "ping:" + seq.to_s
  in [:pong, seq, *] if !seq.nil?
    "pong:" + seq.to_s
  in _
    "other"
  end
end
p inbox_line("Ada", [:score, "Ada", 9])
p inbox_line("Ada", [:score, "Lin", 7])
p inbox_line("Ada", [:profile, "Ada", nil])
p score_delta("Ada", [:bonus, "Ada", 5])
p score_delta("Ada", [:score, "Lin", 5])
p packet_kind([:ping, 7, :fast])
