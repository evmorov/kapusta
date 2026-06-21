module App
  module Args
    class << self
      def parse(argv)
        {:command => argv[0], :target => argv[1]}
      end

      def format_command(parsed)
        parsed[:command].to_s + " -> " + parsed[:target].to_s
      end
    end
  end
end
