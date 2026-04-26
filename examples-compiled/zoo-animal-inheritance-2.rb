require_relative "./zoo-animal-1"
(-> do
  module Zoo
    class Dog < Zoo::Animal
      def label
        self.name.to_s + " the dog"
      end
      def bark
        "woof"
      end
    end
  end
  Zoo::Dog
end).call
(-> do
  dog = Zoo::Dog.new("Poppy")
  p(Zoo::Dog.superclass == Zoo::Animal, dog.kingdom, dog.label, dog.bark)
end).call
