def length_of_last_word(s)
  s.strip.split[-1].length
end
p length_of_last_word("Hello World")
p length_of_last_word("   fly me   to   the moon  ")
p length_of_last_word("luffy is still joyboy")
