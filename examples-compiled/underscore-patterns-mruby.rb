def loose(v)
  case
  when true
    _x = v
    _x
  else
    "not-reachable"
  end
end
def strict(v)
  case
  when (x = v) != nil
    x
  else
    "fallback"
  end
end
p loose(5)
p loose(nil)
p strict(5)
p strict(nil)
