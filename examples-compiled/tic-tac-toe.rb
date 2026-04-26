def winner(board)
  (-> do
    kap_case_value_1 = board
    case kap_case_value_1
    in [["X", "X", "X", *], _, _, *]
      "X"
    in [_, ["O", "O", "O", *], _, *]
      "O"
    in [["X", _, _, *], [_, "X", _, *], [_, _, "X", *], *]
      "X"
    in [["O", _, _, *], ["O", _, _, *], ["O", _, _, *], *]
      "O"
    in _
      "draw"
    else
      nil
    end
  end).call
end
[[["X", "X", "X"], ["O", "", ""], ["", "O", ""]], [["O", "X", "X"], ["O", "", "X"], ["O", "", ""]], [["X", "O", ""], ["", "X", "O"], ["", "", "X"]], [["X", "O", "X"], ["O", "X", "O"], ["O", "X", "O"]]].each_with_index do |board, _|
  p winner(board)
end
