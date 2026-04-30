def describe_user(user)
  case
  when user.is_a?(Hash) && (name = user[:name]) != nil && user[:stats].is_a?(Hash) && (score = user[:stats][:score]) != nil
    name.to_s + ": " + score.to_s
  when user.is_a?(Hash) && (name = user[:name]) != nil
    name.to_s + ": no score"
  else
    "unknown"
  end
end
p describe_user({:name => "Ada", :stats => {:score => 9}})
p describe_user({:name => "Lin"})
p describe_user({})
