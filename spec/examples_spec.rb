# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'stringio'

EXAMPLES_DIR = File.expand_path('../examples', __dir__)

def run_example(name, argv: [])
  previous_argv = ARGV.dup
  previous_stdout = $stdout
  ARGV.replace(argv)
  $stdout = StringIO.new
  Kapusta.dofile(File.join(EXAMPLES_DIR, name))
  $stdout.string
ensure
  $stdout = previous_stdout
  ARGV.replace(previous_argv)
end

def run_ruby_example(name)
  previous_stdout = $stdout
  $stdout = StringIO.new
  load File.join(EXAMPLES_DIR, name)
  $stdout.string
ensure
  $stdout = previous_stdout
end

RSpec.describe 'examples' do
  it 'ackermann.kap' do
    expect(run_example('ackermann.kap')).to eq("9\n61\n")
  end

  it 'accumulator.kap' do
    expect(run_example('accumulator.kap')).to eq("22\n")
  end

  it 'anagram.kap' do
    expect(run_example('anagram.kap')).to eq("true\ntrue\nfalse\n")
  end

  it 'anonymous-greeter.kap' do
    expect(run_example('anonymous-greeter.kap')).to eq(<<~OUT)
      "Hello, anonymous!"
      "Hello, Ada!"
    OUT
  end

  it 'bank-account.kap' do
    expect(run_example('bank-account.kap')).to eq('')
  end

  it 'use_bank_account.rb' do
    expect(run_ruby_example('use_bank_account.rb')).to eq(<<~OUT)
      Owner:   Ada
      Balance: 120
    OUT
  end

  it 'calc.kap' do
    expect(run_example('calc.kap')).to eq("14\n")
  end

  it 'binary-search.kap' do
    expect(run_example('binary-search.kap')).to eq("3\nnil\n")
  end

  it 'binary-to-decimal.kap' do
    expect(run_example('binary-to-decimal.kap')).to eq("11\n0\n42\n")
  end

  it 'blocks-and-kwargs.kap' do
    path = File.expand_path('../tmp/blocks-and-kwargs.txt', EXAMPLES_DIR)
    FileUtils.rm_f(path)

    expect(run_example('blocks-and-kwargs.kap')).to eq(<<~'OUT')
      "Ada\nLin"
      2
    OUT
    expect(File.exist?(path)).to eq(false)
  end

  it 'block-sort.kap' do
    expect(run_example('block-sort.kap')).to eq(<<~OUT)
      "3, 2, 1"
    OUT
  end

  it 'counter.kap' do
    expect(run_example('counter.kap')).to eq("12\n")
  end

  it 'contains-duplicate.kap' do
    expect(run_example('contains-duplicate.kap')).to eq("true\nfalse\ntrue\n")
  end

  it 'climbing-stairs.kap' do
    expect(run_example('climbing-stairs.kap')).to eq("2\n3\n8\n89\n")
  end

  it 'maximum-subarray.kap' do
    expect(run_example('maximum-subarray.kap')).to eq("6\n1\n23\n")
  end

  it 'happy-number.kap' do
    expect(run_example('happy-number.kap')).to eq("true\nfalse\ntrue\n")
  end

  it 'move-zeroes.kap' do
    expect(run_example('move-zeroes.kap')).to eq(<<~OUT)
      [1, 3, 12, 0, 0]
      [0]
      [1, 2, 3]
    OUT
  end

  it 'doto.kap' do
    expect(run_example('doto.kap')).to eq(<<~OUT)
      "1, 2, 3"
    OUT
  end

  it 'doto-hygiene.kap' do
    expect(run_example('doto-hygiene.kap')).to eq(<<~OUT)
      "[99]"
    OUT
  end

  it 'describe.kap' do
    expect(run_example('describe.kap')).to eq(<<~OUT)
      -3
      "negative"
      0
      "zero"
      1
      "one"
      2
      "many"
      99
      "many"
    OUT
  end

  it 'destructure.kap' do
    expect(run_example('destructure.kap')).to eq(<<~OUT)
      6
      "Ada"
      36
    OUT
  end

  it 'egg-count.kap' do
    expect(run_example('egg-count.kap')).to eq("4\n")
  end

  it 'even-squares.kap' do
    expect(run_example('even-squares.kap')).to eq(<<~OUT)
      "4, 16, 36"
    OUT
  end

  it 'exceptions.kap' do
    expect(run_example('exceptions.kap')).to eq(<<~OUT)
      "seen: 12"
      12
      "seen: oops"
      "bad: oops"
    OUT
  end

  it 'factorial.kap' do
    expect(run_example('factorial.kap')).to eq(<<~OUT)
      0
      1
      1
      1
      5
      120
      6
      720
      10
      3628800
    OUT
  end

  it 'files.kap' do
    path = File.expand_path('../tmp/file-io-example.txt', EXAMPLES_DIR)
    FileUtils.rm_f(path)

    expect(run_example('files.kap')).to eq(<<~'OUT')
      "Ada\nLin"
      2
    OUT
    expect(File.exist?(path)).to eq(false)
  end

  it 'fib.kap' do
    expect(run_example('fib.kap')).to eq("55\n")
  end

  it 'fizzbuzz.kap' do
    expected = <<~OUT
      1
      2
      "Fizz"
      4
      "Buzz"
      "Fizz"
      7
      8
      "Fizz"
      "Buzz"
      11
      "Fizz"
      13
      14
      "FizzBuzz"
      16
      17
      "Fizz"
      19
      "Buzz"
    OUT
    expect(run_example('fizzbuzz.kap')).to eq(expected)
  end

  it 'gcd.kap' do
    expect(run_example('gcd.kap')).to eq("12\n6\n")
  end

  it 'greet.kap' do
    expect(run_example('greet.kap', argv: ['Ada'])).to eq(<<~OUT)
      "Hello, Ada!"
    OUT
  end

  it 'hashfn.kap' do
    expect(run_example('hashfn.kap')).to eq("5\n21\n")
  end

  it 'inheritance.kap' do
    expect(run_example('inheritance.kap')).to eq(<<~OUT)
      true
      "animalia"
      "Poppy the dog"
      "woof"
    OUT
  end

  it 'leap-year.kap' do
    expect(run_example('leap-year.kap')).to eq("true\n")
  end

  it 'length-of-last-word.kap' do
    expect(run_example('length-of-last-word.kap')).to eq("5\n4\n6\n")
  end

  it 'min-max.kap' do
    expect(run_example('min-max.kap')).to eq(<<~OUT)
      1
      9
    OUT
  end

  it 'module-header.kap' do
    expect(run_example('module-header.kap')).to eq(<<~OUT)
      "Hello, Ada!"
    OUT
  end

  it 'pipeline.kap' do
    expect(run_example('pipeline.kap')).to eq(<<~OUT)
      "BLUE"
      "RED"
    OUT
  end

  it 'points.kap' do
    expect(run_example('points.kap')).to eq(<<~OUT)
      "origin"
      "y-axis"
      "x-axis"
      "point"
    OUT
  end

  it 'primes.kap' do
    expect(run_example('primes.kap')).to eq("2\n3\n5\n7\n11\n13\n17\n19\n23\n29\n")
  end

  it 'raindrops.kap' do
    expect(run_example('raindrops.kap')).to eq(<<~OUT)
      "PlingPlang"
    OUT
  end

  it 'record.kap' do
    expect(run_example('record.kap')).to eq(<<~OUT)
      "Ada / engineer / ruby, lisp"
    OUT
  end

  it 'regex.kap' do
    first = { 'year' => '2026', 'month' => '04', 'day' => '23' }
    last = { 'year' => '1999', 'month' => '12', 'day' => '31' }
    expected = [
      "2026-04-23 -> #{first}".inspect,
      'hello -> '.inspect,
      "1999-12-31 -> #{last}".inspect
    ].map { |line| "#{line}\n" }.join
    expect(run_example('regex.kap')).to eq(expected)
  end

  it 'ruby-eval.kap' do
    expect(run_example('ruby-eval.kap')).to eq(<<~OUT)
      "10-20-30"
    OUT
  end

  it 'kwargs.kap' do
    expect(run_example('kwargs.kap')).to eq(<<~OUT)
      "Ada has 3 tasks"
    OUT
  end

  it 'match.kap' do
    expect(run_example('match.kap')).to eq(<<~OUT)
      "Ada: 9"
      "Lin: no score"
      "unknown"
    OUT
  end

  it 'packet-router.kap' do
    expect(run_example('packet-router.kap')).to eq(<<~OUT)
      "score:9"
      "other"
      "city:nil"
      5
      0
      "ping:7"
    OUT
  end

  it 'or-patterns.kap' do
    expect(run_example('or-patterns.kap')).to eq(<<~OUT)
      "1:2"
      "2:1"
      "other"
    OUT
  end

  it 'underscore-patterns.kap' do
    expect(run_example('underscore-patterns.kap')).to eq(<<~OUT)
      5
      nil
      5
      "fallback"
    OUT
  end

  it 'scopes.kap' do
    expect(run_example('scopes.kap')).to eq("5\n9\n9\n9\n")
  end

  it 'pcall.kap' do
    expected = <<~'OUT'
      true
      12
      false
      ArgumentError
      false
      "invalid value for Integer(): \"oops\""
    OUT
    expect(run_example('pcall.kap')).to eq(expected)
  end

  it 'palindrome.kap' do
    expect(run_example('palindrome.kap')).to eq("true\ntrue\nfalse\n")
  end

  it 'pangram.kap' do
    expect(run_example('pangram.kap')).to eq("true\nfalse\n")
  end

  it 'safe-lookup.kap' do
    expect(run_example('safe-lookup.kap')).to eq(<<~OUT)
      "Ada"
      nil
    OUT
  end

  it 'shapes.kap' do
    expect(run_example('shapes.kap')).to eq("78.5\n9\n8\n0\n")
  end

  it 'squares.kap' do
    expect(run_example('squares.kap')).to eq("1\n4\n9\n16\n25\n")
  end

  it 'stack.kap' do
    expect(run_example('stack.kap')).to eq(<<~OUT)
      -3
      0
      -2
      true
    OUT
  end

  it 'sum.kap' do
    expect(run_example('sum.kap')).to eq("100\n")
  end

  it 'tset.kap' do
    person = { name: 'Ada', city: 'Amsterdam' }
    expect(run_example('tset.kap')).to eq("#{person.inspect}\n#{'Amsterdam'.inspect}\n")
  end

  it 'two-sum.kap' do
    expect(run_example('two-sum.kap')).to eq("[0, 1]\n[1, 2]\nnil\n")
  end

  it 'two-sum-hash.kap' do
    expect(run_example('two-sum-hash.kap')).to eq("[0, 1]\n[1, 2]\nnil\n")
  end

  it 'baseball-game.kap' do
    expect(run_example('baseball-game.kap')).to eq("30\n27\n")
  end

  it 'valid-parentheses-1.kap' do
    expect(run_example('valid-parentheses-1.kap')).to eq('')
  end

  it 'valid-parentheses-2.kap' do
    expect(run_example('valid-parentheses-2.kap')).to eq("true\ntrue\ntrue\nfalse\nfalse\n")
  end

  it 'threading.kap' do
    expect(run_example('threading.kap')).to eq(<<~OUT)
      "[Ada Lovelace]!"
      "<Ada!>"
      nil
      "ATSUPAK"
      nil
    OUT
  end

  it 'tic-tac-toe.kap' do
    expect(run_example('tic-tac-toe.kap')).to eq(<<~OUT)
      "X"
      "O"
      "X"
      "draw"
    OUT
  end
end
