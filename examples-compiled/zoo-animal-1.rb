module Zoo
  class Animal
    def initialize(name)
      @name = name
    end

    def name
      @name
    end

    def kingdom
      "animalia"
    end

    def label
      name.to_s + " the animal"
    end
  end
end
