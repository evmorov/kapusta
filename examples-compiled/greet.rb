(-> do
    name = (ARGV[0]) || "world"
  p("Hello, " + name.to_s + "!")
end).call
