def loose(v)
  (-> do
    kap_case_value_1 = v
    case kap_case_value_1
    in _x
      _x
    in _
      "fallback"
    else
      nil
    end
  end).call
end
def strict(v)
  (-> do
    kap_case_value_2 = v
    case kap_case_value_2
    in x if !x.nil?
      x
    in _
      "fallback"
    else
      nil
    end
  end).call
end
p loose(5)
p loose(nil)
p strict(5)
p strict(nil)
