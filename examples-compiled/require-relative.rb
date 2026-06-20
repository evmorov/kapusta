require_relative "./require-relative-args"
require_relative "./require-relative-args"
parsed = RequireRelativeArgs.parse(["serve", "--port", "3000"])
options = parsed[:options]
p parsed[:command]
p options.join(" ")
p RequireRelativeArgs.usage
