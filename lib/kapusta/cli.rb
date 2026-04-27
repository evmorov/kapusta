# frozen_string_literal: true

require_relative '../kapusta'
require 'optparse'

module Kapusta
  class CLI
    Options = Struct.new(:compile, :help, :version, keyword_init: true)

    def self.start(argv = ARGV)
      args = argv.dup
      options = parse_options(args)

      if options.help
        $stdout.puts usage
        return
      end

      if options.version
        $stdout.puts "kapusta #{Kapusta::VERSION}"
        return
      end

      if options.compile
        compile_file(args)
      else
        run_file(args)
      end
    rescue Kapusta::Error => e
      warn e.formatted
      exit 1
    end

    def self.parse_options(args)
      options = Options.new(compile: false, help: false, version: false)

      OptionParser.new do |parser|
        parser.banner = usage
        parser.on('-c', '--compile', 'Compile .kap to Ruby') { options.compile = true }
        parser.on('-h', '--help', 'Show this help') { options.help = true }
        parser.on('-v', '--version', 'Show version') { options.version = true }
      end.order!(args)

      options
    end

    def self.compile_file(args)
      path = args.shift
      abort usage unless path
      abort usage unless args.empty?

      $stdout.write(Kapusta.compile(File.read(path), path:))
    end

    def self.run_file(args)
      path = args.shift
      abort usage unless path

      previous_argv = ARGV.dup
      ARGV.replace(args)
      Kapusta.dofile(path)
    ensure
      ARGV.replace(previous_argv) if previous_argv
    end

    def self.usage
      'usage: kapusta [--compile|-c] <file.kap> | kapusta <file.kap> [args...]'
    end
  end
end
