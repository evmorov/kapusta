require_relative "valid-parentheses-1"
(-> do
  solution = ValidParenthesesSolution.new
  p(solution.valid?("()"))
  p(solution.valid?("()[]{}"))
  p(solution.valid?("([])"))
  p(solution.valid?("(]"))
  p(solution.valid?("([)]"))
end).call
