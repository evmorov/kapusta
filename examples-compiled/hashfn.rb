(-> do
    add = ->(*kap_args_1) do
    kap_args_1[0] + kap_args_1[1]
  end
  triple = ->(*kap_args_2) do
    3 * kap_args_2[0]
  end
  p(add.call(2, 3))
  p(triple.call(7))
end).call
