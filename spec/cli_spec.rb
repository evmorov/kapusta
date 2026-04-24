# frozen_string_literal: true

require 'spec_helper'
require 'kapusta/cli'
require 'open3'
require 'rbconfig'
require 'stringio'
require 'tmpdir'

def capture_stdout
  previous_stdout = $stdout
  $stdout = StringIO.new
  yield
  $stdout.string
ensure
  $stdout = previous_stdout
end

def capture_stderr
  previous_stderr = $stderr
  $stderr = StringIO.new
  yield
  $stderr.string
ensure
  $stderr = previous_stderr
end

RSpec.describe Kapusta::CLI do
  it 'compiles a .kap file to runnable Ruby with --compile' do
    path = File.expand_path('../examples/fizzbuzz.kap', __dir__)

    ruby = capture_stdout do
      described_class.start(['--compile', path])
    end

    Dir.mktmpdir do |dir|
      output_path = File.join(dir, 'fizzbuzz.rb')
      File.write(output_path, ruby)

      stdout, stderr, status = Open3.capture3(RbConfig.ruby, output_path)

      expected = "1\n2\nFizz\n4\nBuzz\nFizz\n7\n8\nFizz\nBuzz\n11\nFizz\n13\n14\nFizzBuzz\n16\n17\nFizz\n19\nBuzz\n"
      expect(status.success?).to eq(true), stderr
      expect(stdout).to eq(expected)
    end
  end

  it 'rejects extra positional arguments in compile mode' do
    path = File.expand_path('../examples/fizzbuzz.kap', __dir__)

    error_output = capture_stderr do
      expect { described_class.start(['--compile', path, 'fizzbuzz.rb']) }
        .to raise_error(SystemExit)
    end

    expect(error_output).to include('usage: kapusta')
  end

  it 'passes remaining arguments through to the Kapusta program' do
    path = File.expand_path('../examples/greet.kap', __dir__)

    output = capture_stdout do
      described_class.start([path, 'Ada'])
    end

    expect(output).to eq("Hello, Ada!\n")
  end

  it 'prints the version with -v' do
    output = capture_stdout do
      described_class.start(['-v'])
    end

    expect(output).to eq("kapusta #{Kapusta::VERSION}\n")
  end

  it 'prints the version with --version from the executable' do
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, File.expand_path('../exe/kapusta', __dir__), '--version')

    expect(status.success?).to eq(true), stderr
    expect(stdout).to eq("kapusta #{Kapusta::VERSION}\n")
  end
end
