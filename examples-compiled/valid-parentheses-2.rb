unless defined?(Kapusta)
  require "kapusta"
end
Kapusta.require("./valid-parentheses-1", relative_to: "/Users/evgenii.morozov/projects/kapusta/examples/valid-parentheses-2.kap")
(-> do
  solution = ValidParenthesesSolution.new
  p(solution.valid?("()"))
  p(solution.valid?("()[]{}"))
  p(solution.valid?("([])"))
  p(solution.valid?("(]"))
  p(solution.valid?("([)]"))
end).call
