def count_by_kind(effects)
  quits = 0
  moves = 0
  effects.each do |effect|
    case effect[:kind]
    in :quit
      quits += 1
    in :move
      moves += 1
    in _
      nil
    end
  end
  [quits, moves]
end

effects = [{:kind => :move}, {:kind => :quit}, {:kind => :move}, {:kind => :other}]
q, m = count_by_kind(effects)
p(q, m)
