def kap_match_pattern_into(pattern, value, bindings)
  case pattern[0]
  when :bind
    name = pattern[1]
    allow_nil = pattern[2]
    return false if value.nil? && !allow_nil

    bindings[name] = value
    true
  when :ref
    bindings.key?(pattern[1]) && bindings[pattern[1]] == value
  when :wild
    true
  when :vec
    return false unless value.is_a?(Array) || value.respond_to?(:to_ary)

    array = value.is_a?(Array) ? value : value.to_ary
    items = pattern[1]
    rest_idx = items.index { |item| item.is_a?(Array) && item[0] == :rest }
    if rest_idx
      before = items[0...rest_idx]
      rest_pattern = items[rest_idx][1]
      return false if array.length < before.length

      before.each_with_index do |item, i|
        return false unless kap_match_pattern_into(item, array[i], bindings)
      end
      kap_match_pattern_into(rest_pattern, array[rest_idx..], bindings)
    else
      return false unless array.length >= items.length

      items.each_with_index do |item, i|
        return false unless kap_match_pattern_into(item, array[i], bindings)
      end
      true
    end
  when :hash
    return false unless value.is_a?(Hash)

    pattern[1].each do |key, subpattern|
      return false unless value.key?(key)
      return false unless kap_match_pattern_into(subpattern, value[key], bindings)
    end
    true
  when :lit
    value == pattern[1]
  when :pin
    value == pattern[1]
  when :or
    pattern[1].any? do |option|
      option_bindings = bindings.dup
      next false unless kap_match_pattern_into(option, value, option_bindings)

      bindings.replace(option_bindings)
      true
    end
  else
    raise "bad pattern: #{pattern.inspect}"
  end
end

def kap_match_pattern(pattern, value)
  bindings = {}
  [kap_match_pattern_into(pattern, value, bindings), bindings]
end

private :kap_match_pattern_into, :kap_match_pattern

def inbox_line(user, event)
  (-> do
    kap_case_value_1 = event
    case kap_case_value_1
    in [:score, ^(user), points, *] if !points.nil?
      "score:" + points.to_s
    in [:profile, ^(user), city, *]
      if city
        "city:" + city.to_s
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
    kap_match_5 = kap_match_pattern([:or, [[:vec, [[:lit, :bonus], [:pin, user], [:bind, "points", false]]], [:vec, [[:lit, :score], [:pin, user], [:bind, "points", false]]]]], kap_case_value_2)
    if kap_match_5[0]
      kap_bindings_6 = kap_match_5[1]
      points = kap_bindings_6.fetch("points")
      if (points > 0) && (points < 10)
        points
      else
            kap_match_3 = kap_match_pattern([:wild], kap_case_value_2)
        if kap_match_3[0]
          kap_bindings_4 = kap_match_3[1]
          0
        else
            nil
        end
      end
    else
        kap_match_3 = kap_match_pattern([:wild], kap_case_value_2)
      if kap_match_3[0]
        kap_bindings_4 = kap_match_3[1]
        0
      else
          nil
      end
    end
  end).call
end
def packet_kind(packet)
  (-> do
    kap_case_value_7 = packet
    case kap_case_value_7
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
