def binary_to_decimal(bits)
  (-> do
    value = 0
      0.step(bits.length - 1) do |i|
      value = begin
        (value * 2) + (if bits[i] == "1"
          1
        else
          0
        end)
      end
    end
    value
  end).call
end
p binary_to_decimal("1011")
p binary_to_decimal("0")
p binary_to_decimal("101010")
