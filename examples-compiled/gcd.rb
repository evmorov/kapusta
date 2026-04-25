def gcd(a, b)
  if b == 0
    a
  else
    gcd(b, a % b)
  end
end
p(gcd(48, 36))
p(gcd(270, 192))
