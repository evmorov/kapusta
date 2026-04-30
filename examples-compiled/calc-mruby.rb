def eval_expr(expr)
  case
  when expr.is_a?(Array) && expr.length >= 2 && expr[0] == :num && (n = expr[1]) != nil
    n
  when expr.is_a?(Array) && expr.length >= 3 && expr[0] == :add && (a = expr[1]) != nil && (b = expr[2]) != nil
    eval_expr(a) + eval_expr(b)
  when expr.is_a?(Array) && expr.length >= 3 && expr[0] == :sub && (a = expr[1]) != nil && (b = expr[2]) != nil
    eval_expr(a) - eval_expr(b)
  when expr.is_a?(Array) && expr.length >= 3 && expr[0] == :mul && (a = expr[1]) != nil && (b = expr[2]) != nil
    eval_expr(a) * eval_expr(b)
  when expr.is_a?(Array) && expr.length >= 3 && expr[0] == :div && (a = expr[1]) != nil && (b = expr[2]) != nil
    eval_expr(a) / eval_expr(b)
  else
    Kernel.raise(ArgumentError.new("unknown op: " + expr.inspect.to_s))
  end
end
p eval_expr([:add, [:num, 2], [:mul, [:num, 3], [:num, 4]]])
