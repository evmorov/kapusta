def length_of_last_word(s)
  (-> do
    words = s.strip.split
    words[-1].length
  end).call
end
p(length_of_last_word("Hello World"))
p(length_of_last_word("   fly me   to   the moon  "))
p(length_of_last_word("luffy is still joyboy"))
