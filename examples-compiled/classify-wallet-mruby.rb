def classify_wallet(wallet)
  case
  when wallet.is_a?(Hash) && (a = wallet[1]) != nil && (b = wallet[25]) != nil
    "pennies-" + a.to_s + "-quarters-" + b.to_s
  when wallet.is_a?(Hash) && (q = wallet[25]) != nil
    "quarters-only-" + q.to_s
  when wallet.is_a?(Hash) && (p = wallet[1]) != nil
    "pennies-only-" + p.to_s
  else
    "mixed"
  end
end
p classify_wallet({1 => 5, 25 => 2})
p classify_wallet({25 => 4})
p classify_wallet({1 => 10})
p classify_wallet({5 => 3, 10 => 2})
