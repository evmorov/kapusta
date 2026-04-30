KELVIN_OFFSET = 273.15
FAHRENHEIT_SCALE = 1.8
FAHRENHEIT_OFFSET = 32.0
def convert_temperature(celsius)
  k = celsius + KELVIN_OFFSET
  f = (celsius * FAHRENHEIT_SCALE) + FAHRENHEIT_OFFSET
  [k, f]
end
k, f = convert_temperature(36.5)
p(k, f)
k, f = convert_temperature(122.11)
p(k, f)
