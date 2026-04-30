class Circle
  PI = 3.14159
  def initialize(radius)
    @radius = radius
  end
  def area
    PI * @radius * @radius
  end
  def circumference
    2 * PI * @radius
  end
  c = Circle.new(5)
  p c.area
  p c.circumference
end
Circle
