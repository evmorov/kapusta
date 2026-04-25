class Counter
  def initialize(start)
    @n = start
  end
  def tick
    @n = @n + 1
    @n
  end
  def value
    @n
  end
  def self.zero
    Counter.new(0)
  end
  c = Counter.new(10)
  c.tick
  c.tick
  p c.value
end
Counter
