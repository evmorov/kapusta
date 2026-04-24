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
  it 'compiles a .kap file to stdout with --compile' do
    path = File.expand_path('../examples/fizzbuzz.kap', __dir__)

    output = capture_stdout do
      described_class.start(['--compile', path])
    end

    expect(output).to include('kap_print_values("FizzBuzz")')
    expect(output).to include("n = 1\n")
    expect(output).to include('while n.public_send')
    expect(output).to include("if d3_q && d5_q\n")
    expect(output).to include("elsif d3_q\n")
    expect(output).not_to include('kap_n')
    expect(output).not_to include('(-> do')
    expect(output).not_to include('Kapusta::Compiler::Runtime')
    expect(output).not_to include('module Kapusta')
    expect(output).not_to include('def kap_get_path')
  end

  it 'keeps simple class methods and calls readable in compile mode' do
    path = File.expand_path('../examples/scopes.kap', __dir__)

    output = capture_stdout do
      described_class.start(['--compile', path])
    end

    expect(output).to include("class ScopeCounter\n")
    expect(output).to include('define_method(:add!) do |n|')
    expect(output).to include('a = ScopeCounter.new')
    expect(output).to include('kap_print_values(a.add!(5))')
    expect(output).to include('$last_total = kap_get_cvar(self, "total")')
    expect(output).to include('kap_print_values($last_total)')
    expect(output).not_to include('kap_send_call(a, :add!')
    expect(output).not_to include('kap_ensure_class')
    expect(output).not_to include('kap_set_gvar("last-total"')
    expect { RubyVM::InstructionSequence.compile(output) }.not_to raise_error
  end

  it 'rejects extra positional arguments in compile mode' do
    path = File.expand_path('../examples/fizzbuzz.kap', __dir__)

    error_output = capture_stderr do
      expect { described_class.start(['--compile', path, 'fizzbuzz.rb']) }
        .to raise_error(SystemExit)
    end

    expect(error_output).to include('usage: kapusta')
  end

  it 'emits standalone Ruby that runs with plain ruby' do
    source_path = File.expand_path('../examples/fizzbuzz.kap', __dir__)

    Dir.mktmpdir do |dir|
      output_path = File.join(dir, 'fizzbuzz.rb')
      ruby = Kapusta.compile(File.read(source_path), path: source_path)
      File.write(output_path, ruby)

      stdout, stderr, status = Open3.capture3(RbConfig.ruby, output_path)

      expect(status.success?).to eq(true), stderr
      expect(stdout).to include("FizzBuzz\n")
    end
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
