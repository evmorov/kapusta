(-> do
  person = {:name => "Ada"}
  person[:city] = "Amsterdam"
  p person
  p person[:city]
end).call
