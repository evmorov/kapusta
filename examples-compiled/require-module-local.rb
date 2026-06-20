require_relative "app/args"
args = App::Args
parsed = args.parse(["deploy", "production"])
p args.format_command(parsed)
