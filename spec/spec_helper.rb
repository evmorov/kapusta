# frozen_string_literal: true

require 'bundler/setup'
require 'kapusta'

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.example_status_persistence_file_path = '.rspec_status'
  config.order = :random

  Kernel.srand config.seed
end
