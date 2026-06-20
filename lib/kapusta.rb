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
  LOADING_KAPUSTA_FEATURE = Object.new
  private_constant :LOADING_KAPUSTA_FEATURE

  def self.eval(source, path: '(eval)', **_opts)
    install!
    Compiler.run(source, path:)
  end

  def self.dofile(path, **_opts)
    install!
    source = File.read(path)
    self.eval(source, path:)
  end

  def self.compile(source, path: '(eval)', target: nil, **_opts)
    Compiler.compile(source, path:, target:)
  end

  def self.require(feature, relative_to: nil)
    install!
    feature = require_feature_name(feature)
    local_path = resolve_require_path(feature, relative_to:)

    return require_kapusta_file(local_path) if local_path&.end_with?('.kap')
    return Kernel.require(local_path) if local_path

    kap_path = resolve_load_path_kapusta_feature(feature, relative_to:)
    return require_kapusta_file(kap_path) if kap_path

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

  def self.require_feature_name(feature)
    feature.is_a?(Symbol) ? feature.to_s.tr('.', '/') : feature.to_s
  end

  def self.resolve_load_path_kapusta_feature(feature, relative_to:)
    return if local_feature?(feature)

    load_paths = [require_base_dir(relative_to), *$LOAD_PATH].uniq
    load_paths.each do |load_path|
      candidate = existing_kapusta_feature_path(File.expand_path(feature, load_path))
      return candidate if candidate
    end
    nil
  end

  def self.existing_kapusta_feature_path(path)
    candidates = File.extname(path).empty? ? ["#{path}.kap"] : [path]
    candidates.find { |candidate| File.file?(candidate) && candidate.end_with?('.kap') }
  end

  def self.require_kapusta_file(path)
    expanded = File.realpath(path)
    if @loaded_kapusta_features.key?(expanded)
      cached = @loaded_kapusta_features[expanded]
      return false if cached.equal?(LOADING_KAPUSTA_FEATURE)

      return cached
    end

    @loaded_kapusta_features[expanded] = LOADING_KAPUSTA_FEATURE
    value = dofile(expanded)
    @loaded_kapusta_features[expanded] = value
    $LOADED_FEATURES << expanded unless $LOADED_FEATURES.include?(expanded)
    value
  rescue StandardError, ScriptError
    @loaded_kapusta_features.delete(expanded) if expanded
    raise
  end

  private_class_method :resolve_require_path, :local_feature?, :require_base_dir,
                       :existing_feature_path, :require_feature_name,
                       :resolve_load_path_kapusta_feature, :existing_kapusta_feature_path,
                       :require_kapusta_file, :resolve_kap_relative
end
