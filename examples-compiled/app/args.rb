module App
  module Args
    def self.parse(argv)
      {:command => argv[0], :target => argv[1]}
    end

    def self.format_command(parsed)
      parsed[:command].to_s + " -> " + parsed[:target].to_s
    end
  end
end
