# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'open3'
require 'stringio'
require 'tempfile'

EXAMPLES_DIR = File.expand_path('../examples', __dir__)

def example_list(name)
  File.readlines(File.join(EXAMPLES_DIR, name), chomp: true)
      .reject(&:empty?)
      .map { |example| "#{example}.kap" }
      .freeze
end

MRUBY_RUNTIME_EXAMPLES = example_list('mruby-runtime-examples.txt')

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

def compile_example(name, target: nil)
  path = File.join(EXAMPLES_DIR, name)
  Kapusta.compile(File.read(path), path:, target:)
end

def run_compiled_source(source, path:)
  previous_argv = ARGV.dup
  previous_stdout = $stdout
  ARGV.replace([])
  $stdout = StringIO.new
  TOPLEVEL_BINDING.eval(source, path, 1)
  $stdout.string
ensure
  $stdout = previous_stdout
  ARGV.replace(previous_argv)
end

def run_mruby_source(source, path:)
  stdout, stderr, status = capture_mruby_source(source, path:)

  raise "mruby failed for #{path}:\n#{stderr}" unless status.success?

  stdout
end

def capture_mruby_source(source, path:)
  Tempfile.create([File.basename(path, '.kap'), '.rb']) do |file|
    file.write(source)
    file.close
    Open3.capture3('mruby', file.path)
  end
end

RSpec.describe 'examples' do
  it 'ackermann.kap' do
    expect(run_example('ackermann.kap')).to eq("9\n61\n")
  end

  it 'accumulator.kap' do
    expect(run_example('accumulator.kap')).to eq("22\n")
  end

  it 'account-lockout.kap' do
    expect(run_example('account-lockout.kap')).to eq(<<~OUT)
      :ok
      :locked
      :locked
    OUT
  end

  it 'circle.kap' do
    expect(run_example('circle.kap')).to eq("78.53975\n31.4159\n")
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

  it 'number-of-1-bits.kap' do
    expect(run_example('number-of-1-bits.kap')).to eq("3\n1\n31\n")
  end

  it 'number-of-steps.kap' do
    expect(run_example('number-of-steps.kap')).to eq("6\n4\n12\n")
  end

  it 'convert-temperature.kap' do
    expect(run_example('convert-temperature.kap')).to eq("309.65\n97.7\n395.26\n251.798\n")
  end

  it 'max-achievable.kap' do
    expect(run_example('max-achievable.kap')).to eq("6\n7\n10\n")
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

  it 'zoo-animal-1.kap' do
    expect(run_example('zoo-animal-1.kap')).to eq('')
  end

  it 'zoo-animal-inheritance-2.kap' do
    expect(run_example('zoo-animal-inheritance-2.kap')).to eq(<<~OUT)
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

  it 'pivot-index.kap' do
    expect(run_example('pivot-index.kap')).to eq("3\n-1\n0\n")
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

  it 'underscore-patterns.kap on mruby keeps loose nil and strict fallback separate' do
    path = File.join(EXAMPLES_DIR, 'underscore-patterns.kap')
    ruby = compile_example('underscore-patterns.kap', target: :mruby)

    expect(run_mruby_source(ruby, path:)).to eq(<<~OUT)
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

  it 'single-number.kap' do
    expect(run_example('single-number.kap')).to eq("1\n4\n1\n")
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

  it 'reverse-integer.kap' do
    expect(run_example('reverse-integer.kap')).to eq("321\n-321\n21\n0\n")
  end

  it 'roman-to-integer.kap' do
    expect(run_example('roman-to-integer.kap')).to eq("3\n58\n1994\n")
  end

  it 'best-time-to-buy-sell-stock.kap' do
    expect(run_example('best-time-to-buy-sell-stock.kap')).to eq("5\n0\n2\n")
  end

  it 'majority-element.kap' do
    expect(run_example('majority-element.kap')).to eq("3\n2\n1\n")
  end

  it 'manhattan-distance.kap' do
    expect(run_example('manhattan-distance.kap')).to eq("14\n")
  end

  it 'plus-one.kap' do
    expect(run_example('plus-one.kap')).to eq(<<~OUT)
      [1, 2, 4]
      [4, 3, 2, 2]
      [1, 0]
      [1, 0, 0]
    OUT
  end

  it 'subtract-product-sum.kap' do
    expect(run_example('subtract-product-sum.kap')).to eq("15\n21\n0\n")
  end

  it 'ugly-number.kap' do
    expect(run_example('ugly-number.kap')).to eq("true\ntrue\nfalse\nfalse\ntrue\n")
  end

  it 'macros-unless.kap' do
    expect(run_example('macros-unless.kap')).to eq(<<~OUT)
      "shown"
      "also shown"
    OUT
  end

  it 'macros-swap.kap' do
    expect(run_example('macros-swap.kap')).to eq("2\n1\n")
  end

  it 'macros-when-let.kap' do
    expect(run_example('macros-when-let.kap')).to eq(<<~OUT)
      "got"
      3
      "done"
    OUT
  end

  it 'macros-multi.kap' do
    expect(run_example('macros-multi.kap')).to eq("10\n20\n7\n")
  end

  it 'macros-thrice-if.kap' do
    expect(run_example('macros-thrice-if.kap')).to eq(<<~OUT)
      "tick"
      1
      "tick"
      2
      "tick"
      3
      "final"
      3
    OUT
  end

  it 'macros-dbg.kap' do
    expect(run_example('macros-dbg.kap')).to eq(<<~OUT)
      "dbg"
      6
      "result"
      6
      "dbg"
      50
    OUT
  end

  it 'macros-import.kap' do
    expect(run_example('macros-import.kap')).to eq("8\n")
  end

  it 'macros-import-helpers.kap' do
    expect(run_example('macros-import-helpers.kap')).to eq("60\n")
  end

  it 'macros-import-whole.kap' do
    expect(run_example('macros-import-whole.kap')).to eq("7\n")
  end

  it 'parking-system.kap' do
    expect(run_example('parking-system.kap')).to eq("true\ntrue\nfalse\nfalse\n")
  end

  it 'hit-counter.kap' do
    expect(run_example('hit-counter.kap')).to eq(<<~OUT)
      1
      2
      3
      "alice"
    OUT
  end
end

RSpec.describe 'mruby runtime examples' do
  MRUBY_RUNTIME_EXAMPLES.each do |name|
    it name do
      path = File.join(EXAMPLES_DIR, name)
      ruby = compile_example(name)
      expected = run_example(name)
      expect(run_compiled_source(ruby, path:)).to eq(expected)
      mruby_stdout, _mruby_stderr, mruby_status = capture_mruby_source(ruby, path:)

      if mruby_status.success? && mruby_stdout == expected
        expect(run_mruby_source(ruby, path:)).to eq(expected)
      else
        mruby_ruby = compile_example(name, target: :mruby)

        if mruby_ruby == ruby
          expect(mruby_status).to be_success
        else
          expect(mruby_ruby).not_to match(/^\s*in\b/)
          expect(mruby_ruby).not_to include('^(')
          expect(run_compiled_source(mruby_ruby, path:)).to eq(expected)
          run_mruby_source(mruby_ruby, path:)
        end
      end
    end
  end
end
