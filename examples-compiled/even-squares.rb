def even?(n)
  0 == (n % 2)
end
def select(tbl, pred)
  tbl.filter_map do |x|
    x if pred.call(x)
  end
end
def map(tbl, f)
  tbl.filter_map do |x|
    f.call(x)
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
xs = [1, 2, 3, 4, 5, 6]
filtered = select(xs, method(:even?))
squared = map(filtered, proc do
  _1 * _1
end)
p join(squared, ", ")
