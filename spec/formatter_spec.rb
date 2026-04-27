# frozen_string_literal: true

require 'spec_helper'
require 'kapusta/formatter'
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

def with_stdin(input)
  previous_stdin = $stdin
  $stdin = StringIO.new(input)
  yield
ensure
  $stdin = previous_stdin
end

RSpec.describe Kapusta::Formatter do
  repo_root = File.expand_path('..', __dir__)
  example_idempotence_paths = Dir.glob(File.join(repo_root, 'examples/**/*.kap')).map do |path|
    path.delete_prefix("#{repo_root}/")
  end.freeze

  it 'formats source with the built-in printer even without fnlfmt in PATH' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'sample.kap')
      File.write(path, <<~KAP)
        (fn fetch-post [id] (let [uri (URI.join (ivar base-uri) (.. "/posts/" id)) body (Net.HTTP.get uri) post (JSON.parse body {:symbolize-names true}) {: title : author} post] (values title author)))
      KAP

      previous_path = ENV.fetch('PATH', nil)
      ENV['PATH'] = ''

      output = capture_stdout do
        expect(described_class.new([path]).run).to eq(0)
      end

      expect(output).to eq(<<~KAP)
        (fn fetch-post [id]
          (let [uri (URI.join (ivar base-uri) (.. "/posts/" id))
                body (Net.HTTP.get uri)
                post (JSON.parse body {:symbolize-names true})
                {: title : author} post]
            (values title author)))
      KAP
    ensure
      ENV['PATH'] = previous_path
    end
  end

  it 'rewrites files in place with --fix' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'sample.kap')
      File.write(path, <<~KAP)
        (let [words ["red" "green" "blue" "black" "olive"]](-> words (: :select (fn [w] (< (length w) 5))) (: :map (fn [w] (w.upcase))) (: :sort) (: :each (fn [w] (puts w)))))
      KAP

      expect(described_class.new(['--fix', path]).run).to eq(0)
      expect(File.read(path)).to eq(<<~KAP)
        (let [words ["red" "green" "blue" "black" "olive"]]
          (-> words
              (: :select (fn [w] (< (length w) 5)))
              (: :map (fn [w] (w.upcase)))
              (: :sort)
              (: :each (fn [w] (puts w)))))
      KAP
    end
  end

  it 'reports dirty files with --check' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'sample.kap')
      File.write(path, '(fn tick [](set (ivar n) (+ (ivar n) 1))(ivar n))')

      error_output = capture_stderr do
        expect(described_class.new(['--check', path]).run).to eq(1)
      end

      expect(error_output).to include("Not formatted: #{path}")
    end
  end

  it 'reads stdin when the input path is -' do
    output = with_stdin("(let [name (or (. ARGV 0) \"world\")](puts (.. \"Hello, \" name \"!\")))\n") do
      capture_stdout do
        expect(described_class.new(['-']).run).to eq(0)
      end
    end

    expect(output).to eq(<<~KAP)
      (let [name (or (. ARGV 0) "world")]
        (puts (.. "Hello, " name "!")))
    KAP
  end

  it 'checks stdin when the input path is -' do
    error_output = with_stdin("(fn tick [](set (ivar n) (+ (ivar n) 1))(ivar n))\n") do
      capture_stderr do
        expect(described_class.new(['--check', '-']).run).to eq(1)
      end
    end

    expect(error_output).to include('Not formatted: -')
  end

  it 'rejects --fix with stdin' do
    error_output = with_stdin("(+ 1 2)\n") do
      capture_stderr do
        expect(described_class.new(['--fix', '-']).run).to eq(1)
      end
    end

    expect(error_output).to include('Cannot use --fix with stdin (-).')
  end

  it 'prints the version with -v' do
    output = capture_stdout do
      expect(described_class.new(['-v']).run).to eq(0)
    end

    expect(output).to eq("kapfmt #{Kapusta::VERSION}\n")
  end

  it 'prints the version with --version from the executable' do
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, File.expand_path('../exe/kapfmt', __dir__), '--version')

    expect(status.success?).to eq(true), stderr
    expect(stdout).to eq("kapfmt #{Kapusta::VERSION}\n")
  end

  it 'preserves top-level comments and comments inside forms' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'sample.kap')
      File.write(path, <<~KAP)
        ; entry point
        (fn main [] ; inline body comment
          (print 1))
      KAP

      output = capture_stdout do
        expect(described_class.new([path]).run).to eq(0)
      end

      expect(output).to eq(<<~KAP)
        ; entry point
        (fn main []
          ; inline body comment
          (print 1))
      KAP
    end
  end

  it 'normalizes end-of-line comments into standalone indented comments' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'sample.kap')
      File.write(path, <<~KAP)
        (let [words ["red" "green" "blue"]] ; source data
          (-> words ; start pipeline
              (: :select (fn [w] (< (length w) 5))) ; keep short words
              (: :map (fn [w] (w.upcase)))))
      KAP

      output = capture_stdout do
        expect(described_class.new([path]).run).to eq(0)
      end

      expect(output).to eq(<<~KAP)
        (let [words ["red" "green" "blue"]]
          ; source data
          (-> words
              ; start pipeline
              (: :select (fn [w] (< (length w) 5)))
              ; keep short words
              (: :map (fn [w] (w.upcase)))))
      KAP
    end
  end

  it 'preserves comments in multiline collections' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'sample.kap')
      File.write(path, <<~KAP)
        (let [profile {:name "Ada"
                       ; active user
                       :active true}
              ; next binding
              role "Engineer"]
          (print profile role))
      KAP

      output = capture_stdout do
        expect(described_class.new([path]).run).to eq(0)
      end

      expect(output).to eq(<<~KAP)
        (let [
               profile
               {:name "Ada"
                ; active user
                :active true}
               ; next binding
               role
               "Engineer"]
          (print profile role))
      KAP
    end
  end

  it 'preserves indented comments in nested bodies' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'sample.kap')
      File.write(path, <<~KAP)
        (fn classify [score]
          (if (> score 90)
            ; fast path for top scores
            :great
            :ok))
      KAP

      output = capture_stdout do
        expect(described_class.new([path]).run).to eq(0)
      end

      expect(output).to eq(<<~KAP)
        (fn classify [score]
          (if (> score 90)
            ; fast path for top scores
            :great
            :ok))
      KAP
    end
  end

  it 'formats let bindings with hanging pair alignment' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'sample.kap')
      File.write(path, <<~KAP)
        (let [[a b c] [1 2 3] {: name : age} {:name "Ada" :age 36}]
          (print (+ a b c))
          (print name age))
      KAP

      output = capture_stdout do
        expect(described_class.new([path]).run).to eq(0)
      end

      expect(output).to eq(<<~KAP)
        (let [[a b c] [1 2 3]
              {: name : age} {:name "Ada" :age 36}]
          (print (+ a b c))
          (print name age))
      KAP
    end
  end

  it 'preserves nil-valued let bindings before function bindings' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'sample.kap')
      File.write(path, <<~KAP)
        (let [name nil get-input (fn [] "Dave")]
          (print (get-input)))
      KAP

      output = capture_stdout do
        expect(described_class.new([path]).run).to eq(0)
      end

      expect(output).to eq(<<~KAP)
        (let [name nil
              get-input (fn [] "Dave")]
          (print (get-input)))
      KAP
    end
  end

  example_idempotence_paths.each do |relative_path|
    it "keeps #{relative_path} unchanged" do
      path = File.expand_path("../#{relative_path}", __dir__)
      source = File.read(path)

      formatted = described_class.new([]).send(:format_source, source)

      expect(formatted).to eq(source)
    end
  end
end
