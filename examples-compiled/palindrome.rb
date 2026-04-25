def palindrome?(s)
  (-> do
    lower = s.downcase
    normalized = lower.gsub(Kernel.eval("/[^a-z]/"), "")
    normalized == normalized.reverse
  end).call
end
p(palindrome?("racecar"))
p(palindrome?("A man, a plan, a canal: Panama"))
p(palindrome?("kapusta"))
