class MinStack
  def initialize
    @xs = []
    @mins = []
  end
  def push(x)
    xs = @xs
    mins = @mins
    current_min = if mins.empty?
      x
    elsif x < mins[-1]
      x
    else
      mins[-1]
    end
    xs.push(x)
    mins.push(current_min)
    self
  end
  def pop
    mins = @mins
    mins.pop
    (-> do
      xs = @xs
      xs.pop
    end).call
  end
  def top
    @xs[-1]
  end
  def get_min
    @mins[-1]
  end
  s = MinStack.new
  s.push(-2)
  s.push(0)
  s.push(-3)
  p(s.get_min)
  s.pop
  p(s.top)
  p(s.get_min)
  p(MinStack.superclass == Object)
end
MinStack
