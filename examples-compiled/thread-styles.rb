def positive?(n)
  n > 0
end
def square(n)
  n * n
end
def add(x, y)
  x + y
end
def mul(x, y)
  x * y
end
def nonzero(n)
  if n == 0
    nil
  else
    n
  end
end
def non_empty(s)
  if s == ""
    nil
  else
    s
  end
end
def wrap(s)
  ">>" + s.to_s + "<<"
end
def shout(s)
  s.to_s + "!"
end
def keep(pred, xs)
  xs.filter_map do |x|
    x if pred.call(x)
  end
end
def map(f, xs)
  xs.filter_map do |x|
    f.call(x)
  end
end
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
scores = [-2, 3, -1, 4, 0, 5]
report = join(", ", map(method(:square), keep(method(:positive?), scores)))
adjusted = square(mul(add(7, 3), 2))
ok = (-> do
  thread_1 = "hello"
  thread_2 = if thread_1.nil?
    nil
  else
    non_empty(thread_1)
  end
  thread_3 = if thread_2.nil?
    nil
  else
    wrap(thread_2)
  end
  if thread_3.nil?
    nil
  else
    shout(thread_3)
  end
end).call
bad = (-> do
  thread_4 = ""
  thread_5 = if thread_4.nil?
    nil
  else
    non_empty(thread_4)
  end
  thread_6 = if thread_5.nil?
    nil
  else
    wrap(thread_5)
  end
  if thread_6.nil?
    nil
  else
    shout(thread_6)
  end
end).call
live = (-> do
  thread_7 = 5
  thread_8 = if thread_7.nil?
    nil
  else
    nonzero(thread_7)
  end
  thread_9 = if thread_8.nil?
    nil
  else
    mul(3, thread_8)
  end
  if thread_9.nil?
    nil
  else
    add(1, thread_9)
  end
end).call
dead = (-> do
  thread_10 = 0
  thread_11 = if thread_10.nil?
    nil
  else
    nonzero(thread_10)
  end
  thread_12 = if thread_11.nil?
    nil
  else
    mul(3, thread_11)
  end
  if thread_12.nil?
    nil
  else
    add(1, thread_12)
  end
end).call
p report
p adjusted
p ok
p bad
p live
p dead
