def palindrome?(s)
  normalized = s.downcase.gsub(Kernel.eval("/[^a-z]/"), "")
  normalized == normalized.reverse
end
p palindrome?("racecar")
p palindrome?("A man, a plan, a canal: Panama")
p palindrome?("kapusta")
