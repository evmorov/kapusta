# frozen_string_literal: true

module Kapusta
  def self.kebab_to_snake(name)
    name.tr('-', '_')
  end

  def self.copy_position(target, source)
    return target unless target.respond_to?(:line=) && source.respond_to?(:line)

    target.line ||= source.line
    target.column ||= source.column
    target
  end
end
