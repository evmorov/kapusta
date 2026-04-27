require_relative "valid-parentheses-1"
solution = ValidParenthesesSolution.new
p(solution.valid?("()"))
p(solution.valid?("()[]{}"))
p(solution.valid?("([])"))
p(solution.valid?("(]"))
p(solution.valid?("([)]"))
