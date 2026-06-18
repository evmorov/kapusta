# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

RSpec.describe Kapusta::Compiler do
  def capture_stdout
    previous_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = previous_stdout
  end

  it 'calls methods with arguments on receiver expressions' do
    source = '(print ((. ["abc"] 0).include? "b"))'

    expect(capture_stdout { Kapusta.eval(source) }).to eq("true\n")

    ruby = Kapusta.compile(source)
    expect(capture_stdout { TOPLEVEL_BINDING.eval(ruby, '(compiler-spec)', 1) }).to eq("true\n")
  end
end
