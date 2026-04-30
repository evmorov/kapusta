module HeaderDemo
  def self.greet(name)
    "Hello, " + name.to_s + "!"
  end
end
p HeaderDemo.greet("Ada")
