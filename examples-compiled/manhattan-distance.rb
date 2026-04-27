def manhattan(edge)
  x1, y1 = edge[:from]
  x2, y2 = edge[:to]
  ((x1 - x2).abs) + ((y1 - y2).abs)
end
def total_distance(edges)
  edges.inject(0) do |total, edge|
    total + manhattan(edge)
  end
end
p total_distance([{:from => [0, 0], :to => [3, 4]}, {:from => [1, 1], :to => [4, 5]}])
