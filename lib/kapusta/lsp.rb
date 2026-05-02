# frozen_string_literal: true

require 'json'
require 'uri'
require_relative '../kapusta'
require_relative 'lsp/definition'
require_relative 'lsp/diagnostics'
require_relative 'lsp/formatting'
require_relative 'lsp/rename'
require_relative 'lsp/workspace_index'

module Kapusta
  class LSP
    NOT_INITIALIZED = -32_002
    METHOD_NOT_FOUND = -32_601
    FULL_SYNC = 1

    def self.debug?
      %w[1 true yes on].include?(ENV['KAPUSTA_LS_DEBUG'].to_s.downcase)
    end

    def self.start(input: $stdin, output: $stdout, log: $stderr)
      server = new(input:, output:, log:)
      install_signal_handlers(log)
      server.run
      debug_log(log, 'run returned, calling exit!(0)')
      exit!(0)
    end

    def self.install_signal_handlers(log)
      %w[TERM INT HUP].each do |sig|
        Signal.trap(sig) do
          debug_log(log, "signal #{sig} received, exiting")
          exit!(0)
        rescue StandardError
          exit!(0)
        end
      rescue ArgumentError
      end
    end

    def self.debug_log(log, message)
      return unless debug?

      log.write("kapusta-ls[debug pid=#{Process.pid}]: #{message}\n")
      log.flush
    rescue StandardError
      nil
    end

    def self.uri_to_path(uri)
      return unless uri.is_a?(String)

      parsed = URI.parse(uri)
      return URI::DEFAULT_PARSER.unescape(parsed.path) if parsed.scheme == 'file'

      uri
    rescue URI::InvalidURIError
      nil
    end

    def initialize(input:, output:, log:)
      @input = input.binmode
      @output = output.binmode
      @log = log
      @debug = LSP.debug?
      @sources = {}
      @workspace_index = WorkspaceIndex.new
      @initialized = false
      @shutdown = false
    end

    def run
      debug('run loop start')
      until (message = read_message).nil?
        handle(message)
      end
      debug('stdin EOF, run loop exiting')
    end

    private

    def read_message
      headers = read_headers
      return if headers.nil?

      raw_length = headers['Content-Length']
      return if raw_length.nil?

      length = Integer(raw_length, 10, exception: false)
      return if length.nil? || length.negative?

      body = @input.read(length)
      return if body.nil?

      JSON.parse(body.force_encoding(Encoding::UTF_8))
    rescue JSON::ParserError => e
      log("parse error: #{e.message}")
      nil
    end

    def read_headers
      headers = {}
      loop do
        line = @input.gets
        return if line.nil?
        break if line.chomp.empty?

        name, value = line.chomp.split(': ', 2)
        headers[name] = value if name && value
      end
      headers
    end

    def write_message(payload)
      body = JSON.generate(payload)
      tag = payload[:id] ? "response id=#{payload[:id]}" : "notify #{payload[:method]}"
      debug("write begin (#{tag}, #{body.bytesize} bytes)")
      @output.write("Content-Length: #{body.bytesize}\r\n\r\n#{body}")
      @output.flush
      debug("write done (#{tag})")
    rescue Errno::EPIPE, IOError => e
      debug("write failed (#{e.class}: #{e.message}), exiting")
      exit!(0)
    end

    def handle(message)
      method = message['method']
      id = message['id']
      params = message['params'] || {}

      debug("dispatch begin method=#{method.inspect} id=#{id.inspect}")
      return handle_pre_init(method, id, params) unless @initialized || method == 'initialize' || method == 'exit'

      dispatch(method, id, params)
      debug("dispatch end method=#{method.inspect} id=#{id.inspect}")
    rescue StandardError => e
      log("#{e.class}: #{e.message}")
      log(e.backtrace.first(5).join("\n"))
      reply_error(id, METHOD_NOT_FOUND, e.message)
    end

    def handle_pre_init(method, id, _params)
      return if id.nil?

      reply_error(id, NOT_INITIALIZED, "received #{method} before initialize")
    end

    def dispatch(method, id, params)
      case method
      when 'initialize'
        on_initialize(params)
        @initialized = true
        reply(id, initialize_result)
      when 'initialized' then nil
      when 'shutdown'
        @shutdown = true
        debug('shutdown received, replying and arming watchdog')
        reply(id, nil)
        arm_shutdown_watchdog
      when 'exit'
        debug("exit notification received (shutdown=#{@shutdown}), calling exit!")
        exit!(@shutdown ? 0 : 1)
      when 'textDocument/didOpen' then on_did_open(params)
      when 'textDocument/didChange' then on_did_change(params)
      when 'textDocument/didSave' then on_did_save(params)
      when 'textDocument/didClose' then on_did_close(params)
      when 'textDocument/formatting' then reply(id, formatting(params))
      when 'textDocument/definition' then reply(id, definition(params))
      when 'textDocument/prepareRename' then reply(id, prepare_rename(params))
      when 'textDocument/rename' then handle_rename(id, params)
      else
        reply_error(id, METHOD_NOT_FOUND, "method not found: #{method}")
      end
    end

    def reply(id, result)
      return if id.nil?

      write_message(jsonrpc: '2.0', id:, result:)
    end

    def reply_error(id, code, message)
      return if id.nil?

      write_message(jsonrpc: '2.0', id:, error: { code:, message: })
    end

    def notify(method, params)
      write_message(jsonrpc: '2.0', method:, params:)
    end

    def initialize_result
      {
        capabilities: {
          textDocumentSync: { openClose: true, change: FULL_SYNC, save: { includeText: false } },
          documentFormattingProvider: true,
          definitionProvider: true,
          renameProvider: { prepareProvider: true }
        },
        serverInfo: { name: 'kapusta-ls', version: Kapusta::VERSION }
      }
    end

    def on_initialize(params)
      folders = params['workspaceFolders'] || []
      roots = folders.filter_map { |f| LSP.uri_to_path(f['uri']) }
      roots << LSP.uri_to_path(params['rootUri']) if params['rootUri']
      roots.compact!
      roots.uniq!
      debug("initialize: roots=#{roots.inspect}")
      @workspace_index = WorkspaceIndex.new(roots:)
      @workspace_index.scan!
      debug("workspace scan complete: #{@workspace_index.entry_count} files")
    rescue StandardError => e
      log("workspace scan failed: #{e.class}: #{e.message}")
    end

    def on_did_open(params)
      doc = params['textDocument'] || {}
      uri = doc['uri']
      return unless uri

      version = doc['version']
      text = doc['text'] || ''
      debug("didOpen: uri=#{uri} version=#{version} bytes=#{text.bytesize}")
      store(uri, text, version)
      @workspace_index.refresh(uri, text)
      publish_diagnostics(uri, text, version)
    end

    def on_did_change(params)
      uri = params.dig('textDocument', 'uri')
      version = params.dig('textDocument', 'version')
      changes = params['contentChanges'] || []
      return if uri.nil? || changes.empty?

      text = changes.last['text']
      debug("didChange: uri=#{uri} version=#{version} bytes=#{text.bytesize}")
      store(uri, text, version)
      @workspace_index.refresh(uri, text)
      publish_diagnostics(uri, text, version)
    end

    def on_did_save(params)
      uri = params.dig('textDocument', 'uri')
      entry = @sources[uri]
      return unless entry

      debug("didSave: uri=#{uri}")
      @workspace_index.refresh(uri, entry[:text])
      publish_diagnostics(uri, entry[:text], entry[:version])
    end

    def on_did_close(params)
      uri = params.dig('textDocument', 'uri')
      return unless uri

      debug("didClose: uri=#{uri}")
      @sources.delete(uri)
      @workspace_index.remove(uri)
      notify('textDocument/publishDiagnostics', { uri:, diagnostics: [] })
    end

    def formatting(params)
      uri = params.dig('textDocument', 'uri')
      entry = @sources[uri]
      return [] unless entry

      Formatting.text_edits(entry[:text], LSP.uri_to_path(uri))
    end

    def definition(params)
      uri = params.dig('textDocument', 'uri')
      pos = params['position'] || {}
      entry = @sources[uri]
      return unless entry

      result = Definition.find(uri, entry[:text], pos['line'] || 0, pos['character'] || 0,
                               workspace_index: @workspace_index)
      debug("definition: uri=#{uri} pos=#{pos.inspect} result=#{result.inspect}")
      result
    end

    def prepare_rename(params)
      uri = params.dig('textDocument', 'uri')
      pos = params['position'] || {}
      entry = @sources[uri]
      unless entry
        debug("prepareRename: no source for uri=#{uri.inspect}; tracked=#{@sources.keys.inspect}")
        return
      end

      result = Rename.prepare(entry[:text], pos['line'] || 0, pos['character'] || 0)
      debug("prepareRename: uri=#{uri} pos=#{pos.inspect} result=#{result.inspect}")
      result
    end

    def handle_rename(id, params)
      uri = params.dig('textDocument', 'uri')
      pos = params['position'] || {}
      new_name = params['newName']
      entry = @sources[uri]
      unless entry
        debug("rename: no source for uri=#{uri.inspect}; tracked=#{@sources.keys.inspect}")
        return reply(id, nil)
      end

      debug("rename: uri=#{uri} pos=#{pos.inspect} newName=#{new_name.inspect}")
      result = Rename.perform(uri, entry[:text], pos['line'] || 0, pos['character'] || 0,
                              new_name, workspace_index: @workspace_index)
      if result[:error]
        debug("rename error: #{result[:error].inspect}")
        notify('window/showMessage', { type: 1, message: "Rename: #{result[:error][:message]}" })
        reply(id, { documentChanges: [] })
      else
        edit = build_workspace_edit(result[:changes])
        debug("rename ok: files=#{result[:changes].keys.length} edits=#{result[:changes].values.sum(&:length)}")
        reply(id, edit)
      end
    end

    def build_workspace_edit(changes_by_uri)
      document_changes = changes_by_uri.map do |uri, edits|
        sorted = edits.sort_by { |e| [-e[:range][:start][:line], -e[:range][:start][:character]] }
        version = @sources.dig(uri, :version)
        {
          textDocument: { uri:, version: },
          edits: sorted
        }
      end
      { documentChanges: document_changes }
    end

    def store(uri, text, version)
      @sources[uri] = { text:, version: }
    end

    def publish_diagnostics(uri, text, version)
      diagnostics = Diagnostics.collect(text, LSP.uri_to_path(uri))
      params = { uri:, diagnostics: }
      params[:version] = version unless version.nil?
      notify('textDocument/publishDiagnostics', params)
    end

    def arm_shutdown_watchdog(seconds: 2)
      Thread.new do
        sleep seconds
        debug("shutdown watchdog firing after #{seconds}s, forcing exit")
        exit!(0)
      end
    end

    def log(message)
      @log.puts "kapusta-ls: #{message}"
      @log.flush
    rescue StandardError
      nil
    end

    def debug(message)
      return unless @debug

      @log.write("kapusta-ls[debug pid=#{Process.pid}]: #{message}\n")
      @log.flush
    rescue StandardError
      nil
    end
  end
end
