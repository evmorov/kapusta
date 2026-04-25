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

def point_kind(point)
  (-> do
    kap_case_value_1 = point
    kap_match_8 = kap_match_pattern([:vec, [[:lit, 0], [:lit, 0]]], kap_case_value_1)
  if kap_match_8[0]
    kap_bindings_9 = kap_match_8[1]
    "origin"
  else
      kap_match_6 = kap_match_pattern([:vec, [[:lit, 0], [:wild]]], kap_case_value_1)
    if kap_match_6[0]
      kap_bindings_7 = kap_match_6[1]
      "y-axis"
    else
        kap_match_4 = kap_match_pattern([:vec, [[:wild], [:lit, 0]]], kap_case_value_1)
      if kap_match_4[0]
        kap_bindings_5 = kap_match_4[1]
        "x-axis"
      else
          kap_match_2 = kap_match_pattern([:vec, [[:wild], [:wild]]], kap_case_value_1)
        if kap_match_2[0]
          kap_bindings_3 = kap_match_2[1]
          "point"
        else
            nil
        end
      end
    end
  end
  end).call
end
[[0, 0], [0, 2], [3, 0], [3, 4]].each_with_index do |point, kap_index_10|
  p point_kind(point)
end
nil
