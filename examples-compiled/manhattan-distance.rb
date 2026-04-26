def manhattan(edge)
  (-> do
    x1, y1 = edge[:from]
    x2, y2 = edge[:to]
    ((x1 - x2).abs) + ((y1 - y2).abs)
  end).call
end
def total_distance(edges)
  (-> do
    total = 0
    edges.each do |edge|
      total += manhattan(edge)
    end
    total
  end).call
end
p total_distance([{:from => [0, 0], :to => [3, 4]}, {:from => [1, 1], :to => [4, 5]}])
