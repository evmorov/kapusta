def kap_destructure_into(pattern, value, bindings)
  case pattern[0]
  when :sym
    name = pattern[1]
    bindings[name] = value unless name == '_'
  when :vec
    items = pattern[1]
    rest_idx = items.index { |item| item.is_a?(Array) && item[0] == :rest }
    if rest_idx
      before = items[0...rest_idx]
      rest_pattern = items[rest_idx][1]
      before.each_with_index do |item, i|
        kap_destructure_into(item, value ? value[i] : nil, bindings)
      end
      rest_value = value ? (value[rest_idx..] || []) : []
      kap_destructure_into(rest_pattern, rest_value, bindings)
    else
      items.each_with_index do |item, i|
        kap_destructure_into(item, value ? value[i] : nil, bindings)
      end
    end
  when :hash
    pattern[1].each do |key, subpattern|
      kap_destructure_into(subpattern, value ? value[key] : nil, bindings)
    end
  when :ignore
    nil
  else
    raise "unknown destructure pattern: #{pattern.inspect}"
  end
end

def kap_destructure(pattern, value)
  bindings = {}
  kap_destructure_into(pattern, value, bindings)
  bindings
end

private :kap_destructure_into, :kap_destructure

def min_max(xs)
  (-> do
      kap_bindings_1 = kap_destructure([:vec, [[:sym, "first"], [:rest, [:sym, "rest"]]]], xs)
    first = kap_bindings_1.fetch("first")
    rest = kap_bindings_1.fetch("rest")
    lo = first
    hi = first
    rest.each_with_index do |kap_value_2, kap_index_3|
      nil
    x = kap_value_2
      if x < lo
      lo = x
    end
    if x > hi
      hi = x
    end
    end
    [lo, hi]
  end).call
end
(-> do
    kap_bindings_4 = kap_destructure([:vec, [[:sym, "lo"], [:sym, "hi"]]], min_max([3, 1, 4, 1, 5, 9, 2, 6]))
  lo = kap_bindings_4.fetch("lo")
  hi = kap_bindings_4.fetch("hi")
  p(lo, hi)
end).call
