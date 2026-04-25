(-> do
    words = ["red", "green", "blue", "black", "olive"]
  (((words.select do |w|
    w.length < 5
  end).map do |w|
    w.upcase
  end).sort).each do |w|
    p(w)
  end
end).call
