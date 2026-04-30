def winner(board)
  case
  when board.is_a?(Array) && board.length >= 3 && board[0].is_a?(Array) && board[0].length >= 3 && board[0][0] == "X" && board[0][1] == "X" && board[0][2] == "X"
    "X"
  when board.is_a?(Array) && board.length >= 3 && board[1].is_a?(Array) && board[1].length >= 3 && board[1][0] == "O" && board[1][1] == "O" && board[1][2] == "O"
    "O"
  when board.is_a?(Array) && board.length >= 3 && board[0].is_a?(Array) && board[0].length >= 3 && board[0][0] == "X" && board[1].is_a?(Array) && board[1].length >= 3 && board[1][1] == "X" && board[2].is_a?(Array) && board[2].length >= 3 && board[2][2] == "X"
    "X"
  when board.is_a?(Array) && board.length >= 3 && board[0].is_a?(Array) && board[0].length >= 3 && board[0][0] == "O" && board[1].is_a?(Array) && board[1].length >= 3 && board[1][0] == "O" && board[2].is_a?(Array) && board[2].length >= 3 && board[2][0] == "O"
    "O"
  else
    "draw"
  end
end
[[["X", "X", "X"], ["O", "", ""], ["", "O", ""]], [["O", "X", "X"], ["O", "", "X"], ["O", "", ""]], [["X", "O", ""], ["", "X", "O"], ["", "", "X"]], [["X", "O", "X"], ["O", "X", "O"], ["O", "X", "O"]]].each do |board|
  p winner(board)
end
