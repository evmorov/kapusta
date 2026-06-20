search = require_relative "search-pipeline"
p search[:run].call(search[:plan].call("kapusta"))
