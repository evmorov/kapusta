# frozen_string_literal: true

require_relative 'kapusta/version'
require_relative 'kapusta/error'
require_relative 'kapusta/errors'
require_relative 'kapusta/support'
require_relative 'kapusta/ast'
require_relative 'kapusta/reader'
require_relative 'kapusta/env'
require_relative 'kapusta/compiler'

module Kapusta
  @loaded_kapusta_features = {}

  def self.eval(source, path: '(eval)', **_opts)
    install!
    Compiler.run(source, path:)
  end

  def self.dofile(path, **_opts)
    install!
    source = File.read(path)
    self.eval(source, path:)
  end

  def self.compile(source, path: '(eval)', **_opts)
    Compiler.compile(source, path:)
  end

  def self.require(feature, relative_to: nil)
    install!
    feature = feature.to_s
    local_path = resolve_require_path(feature, relative_to:)

    return require_kapusta_file(local_path) if local_path&.end_with?('.kap')
    return Kernel.require(local_path) if local_path

    Kernel.require(feature)
  end

  def self.install!
    return if @installed

    @installed = true
    Kernel.module_eval do
      def require_relative(path)
        location = caller_locations(1, 1).first
        kap_path = Kapusta.send(:resolve_kap_relative, path, location)
        return Kapusta.send(:require_kapusta_file, kap_path) if kap_path

        base_file = location&.absolute_path || location&.path
        target = base_file ? File.expand_path(path, File.dirname(base_file)) : path
        Kernel.require(target)
      end
    end
  end

  def self.resolve_kap_relative(path, location)
    return unless path.is_a?(String) && location

    base_file = location.absolute_path || location.path
    return unless base_file

    full = File.expand_path(path, File.dirname(File.expand_path(base_file)))
    candidates = full.end_with?('.kap') ? [full] : ["#{full}.kap"]
    candidates.find { |c| File.file?(c) }
  end

  def self.resolve_require_path(feature, relative_to:)
    return unless local_feature?(feature)

    path =
      if File.absolute_path?(feature)
        feature
      else
        File.expand_path(feature, require_base_dir(relative_to))
      end
    existing_feature_path(path)
  end

  def self.local_feature?(feature)
    feature.start_with?('./', '../') || File.absolute_path?(feature)
  end

  def self.require_base_dir(relative_to)
    return Dir.pwd if relative_to.nil? || relative_to.start_with?('(')

    File.dirname(File.expand_path(relative_to))
  end

  def self.existing_feature_path(path)
    candidates =
      if File.extname(path).empty?
        [path, "#{path}.kap", "#{path}.rb"]
      else
        [path]
      end

    candidates.find { |candidate| File.file?(candidate) }
  end

  def self.require_kapusta_file(path)
    expanded = File.realpath(path)
    return false if @loaded_kapusta_features[expanded]

    @loaded_kapusta_features[expanded] = true
    dofile(expanded)
    $LOADED_FEATURES << expanded unless $LOADED_FEATURES.include?(expanded)
    true
  rescue StandardError, ScriptError
    @loaded_kapusta_features.delete(expanded) if expanded
    raise
  end

  private_class_method :resolve_require_path, :local_feature?, :require_base_dir,
                       :existing_feature_path, :require_kapusta_file, :resolve_kap_relative
end
