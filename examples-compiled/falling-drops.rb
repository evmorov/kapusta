def step(drops)
  drops.each do |drop|
    falling = {:kind => drop[:kind], :x => drop[:x], :y => drop[:y] + drop[:speed], :w => drop[:w], :h => drop[:h], :speed => drop[:speed]}
    p(falling[:kind], falling[:x], falling[:y])
  end
end
step([{:kind => "rain", :x => 0, :y => 0, :w => 1, :h => 1, :speed => 2}, {:kind => "snow", :x => 5, :y => 1, :w => 1, :h => 1, :speed => 1}])
