def check(packet)
  case packet
  in [:ping, seq, *] if !seq.nil?
    "got " + seq.to_s
  in _
    "other"
  end
end
p check([:ping, 42])
p check([:ping, nil])
