def inbox_line(user, event)
  (-> do
    kap_case_value_1 = event
    case kap_case_value_1
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
    else
      nil
    end
  end).call
end
def score_delta(user, event)
  (-> do
    kap_case_value_2 = event
    case kap_case_value_2
    in [:bonus, ^(user), p, *] if !p.nil? && p > 0 && p < 10
      p
    in [:score, ^(user), p, *] if !p.nil? && p > 0 && p < 10
      p
    in _
      0
    else
      nil
    end
  end).call
end
def packet_kind(packet)
  (-> do
    kap_case_value_3 = packet
    case kap_case_value_3
    in [:ping, seq, *] if !seq.nil?
      "ping:" + seq.to_s
    in [:pong, seq, *] if !seq.nil?
      "pong:" + seq.to_s
    in _
      "other"
    else
      nil
    end
  end).call
end
p inbox_line("Ada", [:score, "Ada", 9])
p inbox_line("Ada", [:score, "Lin", 7])
p inbox_line("Ada", [:profile, "Ada", nil])
p score_delta("Ada", [:bonus, "Ada", 5])
p score_delta("Ada", [:score, "Lin", 5])
p packet_kind([:ping, 7, :fast])
