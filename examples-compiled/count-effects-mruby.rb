def count_by_kind(effects)
  quits = 0
  moves = 0
  effects.each do |effect|
    kap_case_value_1 = effect[:kind]
    case
    when kap_case_value_1 == :quit
      quits += 1
    when kap_case_value_1 == :move
      moves += 1
    else
      nil
    end
  end
  [quits, moves]
end
effects = [{:kind => :move}, {:kind => :quit}, {:kind => :move}, {:kind => :other}]
q, m = count_by_kind(effects)
p(q, m)
