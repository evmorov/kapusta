def normalize_word(word)
  (-> do
    lower = word.downcase
    chars = lower.chars
    sorted = chars.sort
    sorted.join
  end).call
end
def anagram?(a, b)
  normalize_word(a) == normalize_word(b)
end
p(anagram?("listen", "silent"))
p(anagram?("apple", "papel"))
p(anagram?("hello", "world"))
