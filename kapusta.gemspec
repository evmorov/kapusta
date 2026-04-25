# frozen_string_literal: true

require_relative 'lib/kapusta/version'

Gem::Specification.new do |spec|
  spec.name = 'kapusta'
  spec.version = Kapusta::VERSION
  spec.authors = ['Evgenii Morozov']
  spec.homepage = 'https://github.com/evmorov/kapusta'
  spec.license = 'MIT'

  spec.summary = 'A Lisp for the Ruby runtime'
  spec.description = 'Kapusta is a Lisp for the Ruby runtime.'
  spec.required_ruby_version = '>= 3.1'

  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['bug_tracker_uri'] = "#{spec.homepage}/issues"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").select do |path|
      path.start_with?('bin/', 'docs/', 'examples/', 'exe/', 'lib/', 'spec/') ||
        %w[.rspec Gemfile README.md Rakefile kapfmt kapusta.gemspec].include?(path)
    end
  end
  spec.bindir = 'exe'
  spec.executables = %w[kapfmt kapusta]
  spec.require_paths = ['lib']
end
