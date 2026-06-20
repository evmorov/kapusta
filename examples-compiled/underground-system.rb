def underground_system
  active = []
  routes = {:leyton_waterloo => {:total => 0, :count => 0}, :paradise_cambridge => {:total => 0, :count => 0}}

  route_stat = proc do |start, _end|
    kap_case_value_1 = [start, _end]
    case kap_case_value_1
    in ["Leyton", "Waterloo", *]
      routes[:leyton_waterloo]
    in ["Paradise", "Cambridge", *]
      routes[:paradise_cambridge]
    else
      nil
    end
  end

  find_trip = proc do |id|
    found = nil
    active.each do |trip|
      found = trip if trip[:id] == id
    end
    found
  end

  ops = {:check_in => proc do |id, station, time|
    active.push(**{:id => id, :station => station, :time => time})
  end, :check_out => proc do |id, station, time|
    trip = find_trip.call(id)
    start = trip[:station]
    duration = time - trip[:time]
    stat = route_stat.call(start, station)
    stat[:total] += duration
    stat[:count] += 1
  end, :average_time => proc do |start, _end|
    stat = route_stat.call(start, _end)
    stat[:total] / stat[:count]
  end}
  {:active => active, :ops => ops, :routes => routes}
end

system = underground_system()
system[:ops][:check_in].call(45, "Leyton", 3)
system[:ops][:check_in].call(32, "Paradise", 8)
system[:ops][:check_in].call(27, "Leyton", 10)
system[:ops][:check_out].call(45, "Waterloo", 15)
system[:ops][:check_out].call(27, "Waterloo", 20)
system[:ops][:check_out].call(32, "Cambridge", 22)
p system[:ops][:average_time].call("Leyton", "Waterloo")
p system[:ops][:average_time].call("Paradise", "Cambridge")
