def pangram?(s)
  (-> do
    lower = s.downcase
    letters = lower.gsub(Kernel.eval("/[^a-z]/"), "")
    chars = letters.chars
    uniq = chars.uniq
    uniq.length == 26
  end).call
end
p(pangram?("The quick brown fox jumps over the lazy dog"))
p(pangram?("Hello, world"))
