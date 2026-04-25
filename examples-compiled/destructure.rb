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

(-> do
  kap_bindings_1 = kap_destructure([:vec, [[:sym, "a"], [:sym, "b"], [:sym, "c"]]], [1, 2, 3])
  a = kap_bindings_1.fetch("a")
  b = kap_bindings_1.fetch("b")
  c = kap_bindings_1.fetch("c")
  kap_bindings_2 = kap_destructure([:hash, [[:name, [:sym, "name"]], [:age, [:sym, "age"]]]], {:name => "Ada", :age => 36})
  name = kap_bindings_2.fetch("name")
  age = kap_bindings_2.fetch("age")
  p(a + b + c)
  p(name, age)
end).call
