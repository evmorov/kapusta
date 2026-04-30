class Counter
  def initialize(start)
    @n = start
  end
  def tick
    @n += 1
  end
  def value
    @n
  end
  def self.zero
    Counter.new(0)
  end
end
c = Counter.new(10)
c.tick
c.tick
p c.value
