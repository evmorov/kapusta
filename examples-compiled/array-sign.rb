def sign(n)
  if n > 0
    1
  elsif n < 0
    -1
  else
    0
  end
end
def array_sign(nums)
  nums.inject(1) do |acc, n|
    acc * sign(n)
  end
end
def join(tbl, sep)
  s = ""
  tbl.each do |x|
    if s == ""
      s = x.to_s
    else
      s = s.to_s + sep.to_s + x.to_s
    end
  end
  s
end
def debug_sign(label, nums)
  pretty = proc do
    "[" + join(_1, ", ").to_s + "]"
  end
  "case[" + label.to_s + "] in " + pretty.call(nums).to_s + " out " + array_sign(nums).to_s
end
p debug_sign("mixed", [-1, -2, -3, -4, 3, 2, 1])
p debug_sign("withzero", [1, 5, 0, 2, -3])
p debug_sign("allneg", [-1, 1, -1, 1, -1])
