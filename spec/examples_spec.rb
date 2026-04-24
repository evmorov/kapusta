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
    expect(run_example('anonymous-greeter.kap')).to eq("Hello, anonymous!\nHello, Ada!\n")
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

    expect(run_example('blocks-and-kwargs.kap')).to eq("Ada\nLin\n2\n")
    expect(File.exist?(path)).to eq(false)
  end

  it 'block-sort.kap' do
    expect(run_example('block-sort.kap')).to eq("3, 2, 1\n")
  end

  it 'counter.kap' do
    expect(run_example('counter.kap')).to eq("12\n")
  end

  it 'contains-duplicate.kap' do
    expect(run_example('contains-duplicate.kap')).to eq("true\nfalse\ntrue\n")
  end

  it 'doto.kap' do
    expect(run_example('doto.kap')).to eq("1, 2, 3\n")
  end

  it 'doto-hygiene.kap' do
    expect(run_example('doto-hygiene.kap')).to eq("[99]\n")
  end

  it 'describe.kap' do
    expect(run_example('describe.kap')).to eq("-3\tnegative\n0\tzero\n1\tone\n2\tmany\n99\tmany\n")
  end

  it 'destructure.kap' do
    expect(run_example('destructure.kap')).to eq("6\nAda\t36\n")
  end

  it 'egg-count.kap' do
    expect(run_example('egg-count.kap')).to eq("4\n")
  end

  it 'even-squares.kap' do
    expect(run_example('even-squares.kap')).to eq("4, 16, 36\n")
  end

  it 'exceptions.kap' do
    expect(run_example('exceptions.kap')).to eq("seen: 12\n12\nseen: oops\nbad: oops\n")
  end

  it 'factorial.kap' do
    expect(run_example('factorial.kap')).to eq("0\t1\n1\t1\n5\t120\n6\t720\n10\t3628800\n")
  end

  it 'files.kap' do
    path = File.expand_path('../tmp/file-io-example.txt', EXAMPLES_DIR)
    FileUtils.rm_f(path)

    expect(run_example('files.kap')).to eq("Ada\nLin\n2\n")
    expect(File.exist?(path)).to eq(false)
  end

  it 'fib.kap' do
    expect(run_example('fib.kap')).to eq("55\n")
  end

  it 'fizzbuzz.kap' do
    expected = "1\n2\nFizz\n4\nBuzz\nFizz\n7\n8\nFizz\nBuzz\n11\nFizz\n13\n14\nFizzBuzz\n16\n17\nFizz\n19\nBuzz\n"
    expect(run_example('fizzbuzz.kap')).to eq(expected)
  end

  it 'gcd.kap' do
    expect(run_example('gcd.kap')).to eq("12\n6\n")
  end

  it 'greet.kap' do
    expect(run_example('greet.kap', argv: ['Ada'])).to eq("Hello, Ada!\n")
  end

  it 'hashfn.kap' do
    expect(run_example('hashfn.kap')).to eq("5\n21\n")
  end

  it 'inheritance.kap' do
    expect(run_example('inheritance.kap')).to eq("true\tanimalia\tPoppy the dog\twoof\n")
  end

  it 'leap-year.kap' do
    expect(run_example('leap-year.kap')).to eq("true\n")
  end

  it 'min-max.kap' do
    expect(run_example('min-max.kap')).to eq("1\t9\n")
  end

  it 'module-header.kap' do
    expect(run_example('module-header.kap')).to eq("Hello, Ada!\n")
  end

  it 'pipeline.kap' do
    expect(run_example('pipeline.kap')).to eq("BLUE\nRED\n")
  end

  it 'points.kap' do
    expect(run_example('points.kap')).to eq("origin\ny-axis\nx-axis\npoint\n")
  end

  it 'primes.kap' do
    expect(run_example('primes.kap')).to eq("2\n3\n5\n7\n11\n13\n17\n19\n23\n29\n")
  end

  it 'raindrops.kap' do
    expect(run_example('raindrops.kap')).to eq("PlingPlang\n")
  end

  it 'record.kap' do
    expect(run_example('record.kap')).to eq("Ada / engineer / ruby, lisp\n")
  end

  it 'regex.kap' do
    expected = <<~OUT
      2026-04-23 -> {"year"=>"2026", "month"=>"04", "day"=>"23"}
      hello -> nil
      1999-12-31 -> {"year"=>"1999", "month"=>"12", "day"=>"31"}
    OUT
    expect(run_example('regex.kap')).to eq(expected)
  end

  it 'ruby-eval.kap' do
    expect(run_example('ruby-eval.kap')).to eq("10-20-30\n")
  end

  it 'kwargs.kap' do
    expect(run_example('kwargs.kap')).to eq("Ada has 3 tasks\n")
  end

  it 'match.kap' do
    expect(run_example('match.kap')).to eq("Ada: 9\nLin: no score\nunknown\n")
  end

  it 'packet-router.kap' do
    expect(run_example('packet-router.kap')).to eq("score:9\nother\ncity:nil\n5\n0\nping:7\n")
  end

  it 'or-patterns.kap' do
    expect(run_example('or-patterns.kap')).to eq("1:2\n2:1\nother\n")
  end

  it 'underscore-patterns.kap' do
    expect(run_example('underscore-patterns.kap')).to eq("5\nnil\n5\nfallback\n")
  end

  it 'scopes.kap' do
    expect(run_example('scopes.kap')).to eq("5\n9\n9\n9\n")
  end

  it 'pcall.kap' do
    expected = <<~OUT
      true
      12
      false
      ArgumentError
      false
      invalid value for Integer(): "oops"
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
    expect(run_example('safe-lookup.kap')).to eq("Ada\nnil\n")
  end

  it 'shapes.kap' do
    expect(run_example('shapes.kap')).to eq("78.5\n9\n8\n0\n")
  end

  it 'squares.kap' do
    expect(run_example('squares.kap')).to eq("1\n4\n9\n16\n25\n")
  end

  it 'stack.kap' do
    expect(run_example('stack.kap')).to eq('')
  end

  it 'sum.kap' do
    expect(run_example('sum.kap')).to eq("100\n")
  end

  it 'tset.kap' do
    expect(run_example('tset.kap')).to eq("{:name=>\"Ada\", :city=>\"Amsterdam\"}\nAmsterdam\n")
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
    expect(run_example('threading.kap')).to eq("[Ada Lovelace]!\t<Ada!>\tnil\tATSUPAK\tnil\n")
  end

  it 'tic-tac-toe.kap' do
    expect(run_example('tic-tac-toe.kap')).to eq("X\nO\nX\ndraw\n")
  end
end

RSpec.describe Kapusta do
  it 'exposes a gem version' do
    expect(Kapusta::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end

  it 'defaults classes to Object when the superclass is omitted' do
    source = <<~KAP
      (let [klass (class Stack
                    (fn initialize []
                      nil))]
        (values (= Stack.superclass Object)
                (= (Stack.new.class) Stack)
                (= klass Stack)))
    KAP

    expect(Kapusta.eval(source)).to eq([true, true, true])
  end

  it 'still accepts an explicit superclass vector' do
    source = <<~KAP
      (let [klass (class KapustaError [StandardError])]
        (values (= KapustaError.superclass StandardError)
                (= klass KapustaError)))
    KAP

    expect(Kapusta.eval(source)).to eq([true, true])
  end

  it 'preserves nested arithmetic precedence' do
    source = <<~KAP
      (values (/ (+ 3 5) 2)
              (* (+ 1 2) (- 10 4))
              (% (+ 10 5) 4))
    KAP

    expect(Kapusta.eval(source)).to eq([4, 18, 3])
  end

  it 'supports postfix zero-arg method calls on non-symbol expressions' do
    source = <<~KAP
      (values [1 2].inspect
              (+ 1 2).inspect
              "Listen".downcase.chars.sort.join)
    KAP

    expect(Kapusta.eval(source)).to eq(['[1, 2]', '3', 'eilnst'])
  end
end

RSpec.describe 'errors' do
  it 'raises on unclosed list' do
    expect { Kapusta.eval('(fn hello [name] (.. "Hi " name "!")') }
      .to raise_error(Kapusta::Reader::Error, /unclosed opening delimiter '\('/)
  end
end
