def leap_year?(y)
  (-> do
      div_q = ->(*kap_args_1) do
      0 == (kap_args_1[0] % kap_args_1[1])
    end
    div_q.call(y, 4) && (!div_q.call(y, 100) || div_q.call(y, 400))
  end).call
end
p(leap_year?(2000))
