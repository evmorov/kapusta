(-> do
    words = ["red", "green", "blue", "black", "olive"]
  (((words.select(&proc do |w|
    w.length < 5
  end)).map(&proc do |w|
    w.upcase
  end)).sort).each(&proc do |w|
    p(w)
  end)
end).call
