class Accumulator
  def initialize(start)
    @total = start
  end
  def add!(n)
    @total = @total + n
    self
  end
  def value
    @total
  end
  acc = Accumulator.new(10)
  acc.add!(5)
  acc.add!(7)
  p acc.value
end
Accumulator
