require "kapusta" unless defined?(Kapusta)
Kapusta.require("./valid-parentheses-1", relative_to: __FILE__)
(-> do
  solution = ValidParenthesesSolution.new
  p(solution.valid?("()"))
  p(solution.valid?("()[]{}"))
  p(solution.valid?("([])"))
  p(solution.valid?("(]"))
  p(solution.valid?("([)]"))
end).call
