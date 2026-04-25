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

def format_record(record)
  (-> do
    kap_bindings_1 = kap_destructure([:hash, [[:name, [:sym, "name"]], [:role, [:sym, "role"]], [:tags, [:sym, "tags"]]]], record)
    name = kap_bindings_1.fetch("name")
    role = kap_bindings_1.fetch("role")
    tags = kap_bindings_1.fetch("tags")
    name.to_s + " / " + role.to_s + " / " + tags.join(", ").to_s
  end).call
end
(-> do
  record = {:name => "Ada", :role => "engineer", :tags => ["ruby", "lisp"]}
  p(format_record(record))
end).call
