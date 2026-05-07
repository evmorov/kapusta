require_relative "zoo-animal-1"

module Zoo
  class Dog < Zoo::Animal
    def label
      name.to_s + " the dog"
    end

    def bark
      "woof"
    end
  end
end

dog = Zoo::Dog.new("Poppy")
p(Zoo::Dog.superclass == Zoo::Animal, dog.kingdom, dog.label, dog.bark)
