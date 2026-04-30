class ParkingSystem
  def initialize(big, medium, small)
    @big = big
    @medium = medium
    @small = small
  end
  def add_car(car_type)
    if (car_type == 1) && (@big > 0)
      @big -= 1
      true
    elsif (car_type == 2) && (@medium > 0)
      @medium -= 1
      true
    elsif (car_type == 3) && (@small > 0)
      @small -= 1
      true
    else
      false
    end
  end
end
parking = ParkingSystem.new(1, 1, 0)
p parking.add_car(1)
p parking.add_car(2)
p parking.add_car(3)
p parking.add_car(1)
