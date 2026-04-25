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
  kap_bindings_1 = kap_destructure([:vec, [[:sym, "ok"], [:sym, "value"]]], begin
    [true, send(:Integer, "12")]
  rescue StandardError => e
    [false, e]
  end)
  ok = kap_bindings_1.fetch("ok")
  value = kap_bindings_1.fetch("value")
  kap_bindings_2 = kap_destructure([:vec, [[:sym, "bad-ok"], [:sym, "error"]]], begin
    [true, send(:Integer, "oops")]
  rescue StandardError => e
    [false, e]
  end)
  bad_ok = kap_bindings_2.fetch("bad-ok")
  error = kap_bindings_2.fetch("error")
  kap_bindings_3 = kap_destructure([:vec, [[:sym, "handled-ok"], [:sym, "handled"]]], begin
    [true, send(:Integer, "oops")]
  rescue StandardError => e
    [false, (proc do |e|
      e.message
    end).call(e)]
  end)
  handled_ok = kap_bindings_3.fetch("handled-ok")
  handled = kap_bindings_3.fetch("handled")
  p(ok)
  p(value)
  p(bad_ok)
  p(error.class)
  p(handled_ok)
  p(handled)
end).call
