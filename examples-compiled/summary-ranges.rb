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

def range_label(lo, hi)
  if lo == hi
    lo.to_s
  else
    join("", [lo.to_s, "->", hi.to_s])
  end
end

def append_range(out, lo, hi)
  label = range_label(lo, hi)
  parts = [out, if out == ""
    ""
  else
    "|"
  end, label]
  join("", parts)
end

def summary_ranges(nums)
  started_q = false
  start = 0
  prev = 0
  out = ""
  nums.each do |n|
    if started_q
      if n == (prev + 1)
        prev = n
      else
        out = append_range(out, start, prev)
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
    append_range(out, start, prev)
  else
    out
  end
end

p summary_ranges([0, 1, 2, 4, 5, 7])
p summary_ranges([0, 2, 3, 4, 6, 8, 9])
p("empty=" + summary_ranges([]).to_s)
