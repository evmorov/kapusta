# frozen_string_literal: true

module Kapusta
  def self.kebab_to_snake(name)
    name.tr('-', '_')
  end
end
