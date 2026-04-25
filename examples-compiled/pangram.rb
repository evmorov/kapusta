def pangram?(s)
  26 == ((((s.downcase.gsub(Kernel.eval("/[^a-z]/"), "")).chars).uniq).length)
end
p pangram?("The quick brown fox jumps over the lazy dog")
p pangram?("Hello, world")
