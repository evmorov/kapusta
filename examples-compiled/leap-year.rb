def leap_year?(y)
  div_q = proc do
    0 == (_1 % _2)
  end
  div_q.call(y, 4) && (!div_q.call(y, 100) || div_q.call(y, 400))
end
p leap_year?(2000)
