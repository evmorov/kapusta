def plus_one(digits)
  i = digits.length - 1
  carry = 1
  while (i >= 0) && (carry > 0)
    total = digits[i] + carry
    digits[i] = total % 10
    carry = (total / 10).floor
    i -= 1
  end
  if carry > 0
    digits.unshift(carry)
  else
    digits
  end
end
p plus_one([1, 2, 3])
p plus_one([4, 3, 2, 1])
p plus_one([9])
p plus_one([9, 9])
