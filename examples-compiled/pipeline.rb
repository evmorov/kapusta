(-> do
    words = ["red", "green", "blue", "black", "olive"]
  (((words.public_send(:select, &proc do |w|
    w.length < 5
  end)).public_send(:map, &proc do |w|
    w.upcase
  end)).sort).public_send(:each, &proc do |w|
    p(w)
  end)
end).call
