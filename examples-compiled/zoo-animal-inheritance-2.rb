def kap_ensure_class(holder, path, super_class)
  segments = path.split('.')
  last = segments.pop
  scope = holder.is_a?(Module) ? holder : Object
  segments.each do |segment|
    scope =
      if scope.const_defined?(segment, false)
        scope.const_get(segment, false)
      else
        mod = Module.new
        scope.const_set(segment, mod)
        mod
      end
  end
  if scope.const_defined?(last, false)
    scope.const_get(last, false)
  else
    klass = Class.new(super_class)
    scope.const_set(last, klass)
    klass
  end
end

private :kap_ensure_class

unless defined?(Kapusta)
  require "kapusta"
end
Kapusta.require("./zoo-animal-1", relative_to: "/Users/evgenii.morozov/projects/kapusta/examples/zoo-animal-inheritance-2.kap")
(-> do
  kap_class_1 = kap_ensure_class(self, "Zoo.Dog", Zoo::Animal)
  kap_class_1.class_eval do
    def label
      self.name.to_s + " the dog"
    end
    def bark
      "woof"
    end
  end
  kap_class_1
end).call
(-> do
  dog = Zoo::Dog.new("Poppy")
  p(Zoo::Dog.superclass == Zoo::Animal, dog.kingdom, dog.label, dog.bark)
end).call
