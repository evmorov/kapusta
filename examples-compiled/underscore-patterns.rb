def loose(v)
  case v
  in _x
    _x
  in _
    "fallback"
  end
end
def strict(v)
  case v
  in x if !x.nil?
    x
  in _
    "fallback"
  end
end
p loose(5)
p loose(nil)
p strict(5)
p strict(nil)
