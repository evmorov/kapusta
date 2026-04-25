(-> do
    name = nil
  greet = proc do |value|
    if value
      "Hello, " + value.to_s + "!"
    else
      "Hello, anonymous!"
    end
  end
  p(greet.call(name))
  p(greet.call("Ada"))
end).call
