module RequireLocalArgs
  def self.parse(argv)
    {:command => argv[0], :options => argv.drop(1)}
  end

  def self.usage
    "usage: kapusta <command> [options]"
  end
end
