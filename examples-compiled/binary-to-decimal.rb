def binary_to_decimal(bits)
  (0..bits.length - 1).inject(0) do |value, i|
    (value * 2) + (if bits[i] == "1"
      1
    else
      0
    end)
  end
end
p binary_to_decimal("1011")
p binary_to_decimal("0")
p binary_to_decimal("101010")
