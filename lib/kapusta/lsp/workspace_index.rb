# frozen_string_literal: true

require 'uri'
require_relative '../reader'
require_relative 'scope_walker'

module Kapusta
  class LSP
    class WorkspaceIndex
      Entry = Struct.new(:uri, :text, :forms, :walker, keyword_init: true)

      def initialize(roots: [])
        @roots = Array(roots)
        @entries = {}
      end

      def scan!
        @roots.each do |root|
          Dir.glob(File.join(root, '**', '*.kap')).each do |path|
            uri = path_to_uri(path)
            text = File.read(path)
            store(uri, text)
          end
        end
        self
      end

      def refresh(uri, text)
        store(uri, text)
      end

      def remove(uri)
        path = uri_to_path(uri)
        if path && File.file?(path)
          store(uri, File.read(path))
        else
          @entries.delete(uri)
        end
      end

      def entry(uri)
        @entries[uri]
      end

      def entry_count
        @entries.length
      end

      def toplevel_fn_definitions(name)
        result = []
        @entries.each do |uri, entry|
          entry.walker.bindings.each do |b|
            result << [uri, b] if b.kind == :toplevel_fn && b.name == name
          end
        end
        result
      end

      def constant_definitions_with_prefix(prefix)
        result = []
        @entries.each do |uri, entry|
          entry.walker.bindings.each do |b|
            next unless %i[module class].include?(b.kind)

            segs = b.sym.dotted? ? b.sym.segments : [b.sym.name]
            result << [uri, b] if segs == prefix
          end
        end
        result
      end

      def toplevel_fn_occurrences(name)
        result = {}
        @entries.each do |uri, entry|
          occs = entry.walker.bindings.select do |b|
            b.kind == :toplevel_fn && b.name == name
          end
          occs += entry.walker.references.select do |r|
            next false unless r.sym.is_a?(Sym) && !r.sym.dotted? && r.name == name

            r.target.nil? || (r.target.kind == :toplevel_fn && r.target.name == name)
          end
          result[uri] = occs unless occs.empty?
        end
        result
      end

      def toplevel_definition?(name, except_name: nil)
        @entries.any? do |_uri, entry|
          entry.walker.bindings.any? do |b|
            next false unless file_toplevel_binding?(b)
            next false if except_name && b.name == except_name

            b.name == name
          end
        end
      end

      def constant_definition_with_prefix?(prefix, except_prefix: nil)
        @entries.any? do |_uri, entry|
          entry.walker.bindings.any? do |b|
            next false unless %i[module class].include?(b.kind)
            next false if except_prefix && matches_prefix?(b.sym, except_prefix)

            matches_prefix?(b.sym, prefix)
          end
        end
      end

      def constant_occurrences(prefix)
        result = {}
        @entries.each do |uri, entry|
          occs = []
          entry.walker.bindings.each do |b|
            next unless %i[module class].include?(b.kind)

            occs << b if matches_prefix?(b.sym, prefix)
          end
          entry.walker.references.each do |r|
            sym = r.sym
            next unless sym.is_a?(Sym)
            next unless r.target.nil?
            next unless first_segment_capitalized?(sym)

            occs << r if matches_prefix?(sym, prefix)
          end
          result[uri] = occs unless occs.empty?
        end
        result
      end

      private

      def file_toplevel_binding?(binding)
        binding.scope.kind == :file && %i[toplevel_fn local var].include?(binding.kind)
      end

      def matches_prefix?(sym, prefix)
        segs = sym.dotted? ? sym.segments : [sym.name]
        return false if segs.length < prefix.length

        segs[0...prefix.length] == prefix
      end

      def first_segment_capitalized?(sym)
        first = sym.dotted? ? sym.segments.first : sym.name
        first.match?(/\A[A-Z]/)
      end

      def store(uri, text)
        forms = Reader.read_all(text)
        walker = ScopeWalker.analyze(forms)
        @entries[uri] = Entry.new(uri:, text:, forms:, walker:)
      rescue Kapusta::Error
        @entries[uri] = Entry.new(uri:, text:, forms: [], walker: ScopeWalker.analyze([]))
      end

      def path_to_uri(path)
        "file://#{URI::DEFAULT_PARSER.escape(File.expand_path(path))}"
      end

      def uri_to_path(uri)
        return unless uri.is_a?(String)

        parsed = URI.parse(uri)
        return URI::DEFAULT_PARSER.unescape(parsed.path) if parsed.scheme == 'file'

        uri
      rescue URI::InvalidURIError
        nil
      end
    end
  end
end
