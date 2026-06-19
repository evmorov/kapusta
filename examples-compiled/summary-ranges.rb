def join(sep, xs)
  s = ""
  xs.each do |x|
    if s == ""
      s = x.to_s
    else
      s = s.to_s + sep.to_s + x.to_s
    end
  end
  s
end

range_boundary__string = nil
range_boundary__string = proc do |n|
  n.to_s
end

range_label = nil
range_label = proc do |range_start, range_end|
  if range_start == range_end
    range_boundary__string.call(range_start)
  else
    join("", [range_boundary__string.call(range_start), "->", range_boundary__string.call(range_end)])
  end
end

append_range = nil
append_range = proc do |out, lo, hi|
  label = range_label.call(lo, hi)
  parts = [out, if out == ""
    ""
  else
    "|"
  end, label]
  join("", parts)
end

summary_ranges = nil
summary_ranges = proc do |nums|
  started_q = false
  start = 0
  prev = 0
  out = ""
  nums.each do |n|
    if started_q
      if n == (prev + 1)
        prev = n
      else
        out = append_range.call(out, start, prev)
        start = n
        prev = n
      end
    else
      started_q = true
      start = n
      prev = n
    end
  end
  if started_q
    append_range.call(out, start, prev)
  else
    out
  end
end

p summary_ranges.call([0, 1, 2, 4, 5, 7])
p summary_ranges.call([0, 2, 3, 4, 6, 8, 9])
p("empty=" + summary_ranges.call([]).to_s)
