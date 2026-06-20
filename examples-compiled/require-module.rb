require_relative "app/args"
parsed = App::Args.parse(["deploy", "production"])
p App::Args.format_command(parsed)
