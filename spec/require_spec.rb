# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

RSpec.describe 'Kapusta require' do
  it 'returns cached final values from .kap relative requires resolved from the current .kap file' do
    Dir.mktmpdir('kapusta-require-local') do |dir|
      app_dir = File.join(dir, 'app')
      other_dir = File.join(dir, 'other')
      FileUtils.mkdir_p([app_dir, other_dir])
      counter_path = File.join(dir, 'loads.txt')

      File.write(File.join(app_dir, 'args.kap'), <<~KAP)
        (ruby #{"File.write(#{counter_path.inspect}, 'x', mode: 'a')".inspect})

        (fn parse [argv]
          (argv.join ","))

        {: parse}
      KAP

      File.write(File.join(app_dir, 'main.kap'), <<~KAP)
        (local args (require "./args"))
        (local again (require "./args"))

        [((. args :parse) ["alpha" "beta"])
         ((. again :parse) ["gamma"])]
      KAP

      result = Dir.chdir(other_dir) do
        Kapusta.dofile(File.join(app_dir, 'main.kap'))
      end

      expect(result).to eq(['alpha,beta', 'gamma'])
      expect(File.read(counter_path)).to eq('x')
    end
  end

  it 'calls functions on required .kap module maps with dotted syntax' do
    Dir.mktmpdir('kapusta-require-local-map-call') do |dir|
      File.write(File.join(dir, 'probe.kap'), <<~KAP)
        (fn parse-size [output]
          (.. "size:" output))

        {: parse-size}
      KAP

      File.write(File.join(dir, 'main.kap'), <<~KAP)
        (local probe (require "./probe"))

        (probe.parse-size "42 120")
      KAP

      expect(Kapusta.dofile(File.join(dir, 'main.kap'))).to eq('size:42 120')
    end
  end

  it 'delegates relative requires to Ruby for .rb files' do
    Dir.mktmpdir('kapusta-require-local-ruby') do |dir|
      mod_name = "KapustaRequireRelativeRubyFeature#{rand(1_000_000)}"
      File.write(File.join(dir, 'feature.rb'), <<~RUBY)
        module #{mod_name}
          VALUE = 7
        end
      RUBY
      File.write(File.join(dir, 'main.kap'), <<~KAP)
        (require "./feature")
        (ruby "#{mod_name}::VALUE")
      KAP

      expect(Kapusta.dofile(File.join(dir, 'main.kap'))).to eq(7)
    end
  end

  it 'returns cached final values from .kap module-path requires' do
    Dir.mktmpdir('kapusta-require-module') do |dir|
      app_dir = File.join(dir, 'app')
      FileUtils.mkdir_p(app_dir)
      counter_path = File.join(dir, 'loads.txt')

      File.write(File.join(app_dir, 'args.kap'), <<~KAP)
        (ruby #{"File.write(#{counter_path.inspect}, 'x', mode: 'a')".inspect})

        (fn parse [argv]
          (argv.join ":"))

        {: parse}
      KAP

      begin
        $LOAD_PATH.unshift(dir)
        first = Kapusta.require(:'app.args')
        second = Kapusta.require(:'app.args')

        expect(first[:parse].call(%w[left right])).to eq('left:right')
        expect(second).to equal(first)
        expect(File.read(counter_path)).to eq('x')
      ensure
        $LOAD_PATH.delete(dir)
      end
    end
  end
end
