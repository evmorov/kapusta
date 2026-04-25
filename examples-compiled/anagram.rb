def normalize_word(word)
  word.downcase.chars.sort
end
def anagram?(a, b)
  normalize_word(a) == normalize_word(b)
end
p anagram?("listen", "silent")
p anagram?("apple", "papel")
p anagram?("hello", "world")
