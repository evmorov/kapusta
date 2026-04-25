1.step(20) do |n|
  d3_q = 0 == (n % 3)
  d5_q = 0 == (n % 5)
  if d3_q && d5_q
    p "FizzBuzz"
  elsif d3_q
    p "Fizz"
  elsif d5_q
    p "Buzz"
  else
    p n
  end
end
