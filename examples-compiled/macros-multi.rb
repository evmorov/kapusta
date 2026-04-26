p((-> do
  x_g5 = 10
  y_g6 = 20
  if x_g5 < y_g6
    x_g5
  else
    y_g6
  end
end).call)
p((-> do
  x_g7 = 10
  y_g8 = 20
  if x_g7 < y_g8
    y_g8
  else
    x_g7
  end
end).call)
p((-> do
  x_g9 = 7
  y_g10 = 7
  if x_g9 < y_g10
    x_g9
  else
    y_g10
  end
end).call)
