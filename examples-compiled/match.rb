def describe_user(user)
  (-> do
    kap_case_value_1 = user
    case kap_case_value_1
    in {name: name, stats: {score: score}} if !name.nil? && !score.nil?
      name.to_s + ": " + score.to_s
    in {name: name} if !name.nil?
      name.to_s + ": no score"
    in _
      "unknown"
    else
      nil
    end
  end).call
end
p describe_user({:name => "Ada", :stats => {:score => 9}})
p describe_user({:name => "Lin"})
p describe_user({})
