require_relative "require-local-args"
parsed = RequireLocalArgs.parse(["serve", "--port", "3000"])
options = parsed[:options]
p parsed[:command]
p options.join(" ")
p RequireLocalArgs.usage
