class HitCounter
  @@total = 0
  def initialize(name)
    @name = name
  end
  def hit
    @@total += 1
    $last_hitter = @name
    @@total
  end
  a = HitCounter.new("alice")
  b = HitCounter.new("bob")
  p a.hit
  p b.hit
  p a.hit
  p $last_hitter
end
HitCounter
