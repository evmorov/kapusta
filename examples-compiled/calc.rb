def eval_expr(expr)
  case expr
  in [:num, n, *] if !n.nil?
    n
  in [:add, a, b, *] if !a.nil? && !b.nil?
    eval_expr(a) + eval_expr(b)
  in [:sub, a, b, *] if !a.nil? && !b.nil?
    eval_expr(a) - eval_expr(b)
  in [:mul, a, b, *] if !a.nil? && !b.nil?
    eval_expr(a) * eval_expr(b)
  in [:div, a, b, *] if !a.nil? && !b.nil?
    eval_expr(a) / eval_expr(b)
  in _
    Kernel.raise(ArgumentError.new("unknown op: " + expr.inspect.to_s))
  end
end
p eval_expr([:add, [:num, 2], [:mul, [:num, 3], [:num, 4]]])
