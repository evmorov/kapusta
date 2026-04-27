def classify_wallet(wallet)
  case wallet
  in Hash => kap_hash_1 if !(a = kap_hash_1[1]).nil? && !(b = kap_hash_1[25]).nil?
    "pennies-" + a.to_s + "-quarters-" + b.to_s
  in Hash => kap_hash_2 if !(q = kap_hash_2[25]).nil?
    "quarters-only-" + q.to_s
  in Hash => kap_hash_3 if !(p = kap_hash_3[1]).nil?
    "pennies-only-" + p.to_s
  in _
    "mixed"
  end
end
p classify_wallet({1 => 5, 25 => 2})
p classify_wallet({25 => 4})
p classify_wallet({1 => 10})
p classify_wallet({5 => 3, 10 => 2})
