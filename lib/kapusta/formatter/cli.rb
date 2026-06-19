# frozen_string_literal: true

module Kapusta
  class Formatter
    module CLI
      def initialize(argv)
        @mode = :stdout
        @files = []
        @version = false
        parse_args(argv)
      end

      def run
        return print_version if @version

        validate_args!
        apply_mode(formatted_files)
      rescue Kapusta::Error => e
        warn e.formatted
        1
      end

      private

      def print_version
        puts "kapfmt #{Kapusta::VERSION}"
        0
      end

      def formatted_files
        @files.map { |path| formatted_file(path) }
      end

      def formatted_file(path)
        original = read_source(path)
        validate_kapusta_source(original, path)
        [path, original, format_source(original, path)]
      end

      def apply_mode(formatted)
        case @mode
        when :stdout
          $stdout.write(formatted.first[2])
        when :fix
          fix_files(formatted)
        when :check
          return check_files(formatted)
        end

        0
      end

      def fix_files(formatted)
        formatted.each do |path, _original, rewritten|
          raise Error, 'Cannot use --fix with stdin (-).' if stdin_path?(path)

          File.write(path, rewritten)
        end
      end

      def check_files(formatted)
        dirty = formatted.reject { |_path, original, rewritten| original == rewritten }
        dirty.each do |path, _original, _rewritten|
          warn "Not formatted: #{path}"
        end

        dirty.empty? ? 0 : 1
      end

      def parse_args(argv)
        argv.each do |arg|
          case arg
          when '--fix'
            ensure_mode!(:fix)
          when '--check'
            ensure_mode!(:check)
          when '--version', '-v'
            @version = true
          when '--help', '-h'
            print_help
            exit 0
          else
            @files << arg
          end
        end
      end

      def ensure_mode!(mode)
        raise Error, 'Use at most one of --fix or --check.' if @mode != :stdout && @mode != mode

        @mode = mode
      end

      def validate_args!
        raise Error, 'Usage: kapfmt [--fix] [--check] FILENAME...' if @files.empty?
        raise Error, 'stdin (-) may only be specified once.' if @files.count { |path| stdin_path?(path) } > 1
        raise Error, 'Cannot use --fix with stdin (-).' if @mode == :fix && @files.any? { |path| stdin_path?(path) }

        return unless @mode == :stdout && @files.length != 1

        raise Error, 'Without --fix or --check, kapfmt accepts exactly one file.'
      end

      def read_source(path)
        return File.read(path) unless stdin_path?(path)

        @stdin_read ||= false
        raise Error, 'stdin (-) may only be specified once.' if @stdin_read

        @stdin_read = true
        $stdin.read
      end

      def stdin_path?(path)
        path == STDIN_PATH
      end

      def print_help
        puts 'Usage: kapfmt [--fix] [--check] FILENAME...'
        puts
        puts 'Formats Kapusta source using the built-in Kapusta reader and pretty-printer.'
      end
    end
  end
end
