# frozen_string_literal: true

require 'bundler/setup'
require 'kapusta'

module SilenceConstantRedefinitionWarnings
  def warn(message, category: nil)
    return if /already initialized constant|previous definition of/.match?(message)

    super
  end
end
Warning.singleton_class.prepend(SilenceConstantRedefinitionWarnings)

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.example_status_persistence_file_path = '.rspec_status'
  config.order = :random

  Kernel.srand config.seed
end
