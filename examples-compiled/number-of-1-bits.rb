BIT_WIDTH = 32
def hamming_weight(n)
  x = n
  count = 0
  1.step(BIT_WIDTH) do
    count += (x % 2)
    x = (x / 2).floor
  end
  count
end
p hamming_weight(11)
p hamming_weight(128)
p hamming_weight(4294967293)
