# frozen_string_literal: true

require 'json'
require 'uri'
require_relative '../kapusta'
require_relative 'formatter'

module Kapusta
  class LSP
    NOT_INITIALIZED = -32_002
    METHOD_NOT_FOUND = -32_601
    SEVERITY_ERROR = 1
    FULL_SYNC = 1

    def self.start(input: $stdin, output: $stdout, log: $stderr)
      new(input:, output:, log:).run
    end

    def initialize(input:, output:, log:)
      @input = input.binmode
      @output = output.binmode
      @log = log
      @sources = {}
      @initialized = false
      @shutdown = false
    end

    def run
      until (message = read_message).nil?
        handle(message)
      end
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
      @output.write("Content-Length: #{body.bytesize}\r\n\r\n#{body}")
      @output.flush
    end

    def handle(message)
      method = message['method']
      id = message['id']
      params = message['params'] || {}

      return handle_pre_init(method, id, params) unless @initialized || method == 'initialize' || method == 'exit'

      dispatch(method, id, params)
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
        @initialized = true
        reply(id, initialize_result)
      when 'initialized' then nil
      when 'shutdown'
        @shutdown = true
        reply(id, nil)
      when 'exit' then exit(@shutdown ? 0 : 1)
      when 'textDocument/didOpen' then on_did_open(params)
      when 'textDocument/didChange' then on_did_change(params)
      when 'textDocument/didSave' then on_did_save(params)
      when 'textDocument/didClose' then on_did_close(params)
      when 'textDocument/formatting' then reply(id, formatting(params))
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
          documentFormattingProvider: true
        },
        serverInfo: { name: 'kapusta-ls', version: Kapusta::VERSION }
      }
    end

    def on_did_open(params)
      doc = params['textDocument'] || {}
      uri = doc['uri']
      return unless uri

      version = doc['version']
      text = doc['text'] || ''
      store(uri, text, version)
      publish_diagnostics(uri, text, version)
    end

    def on_did_change(params)
      uri = params.dig('textDocument', 'uri')
      version = params.dig('textDocument', 'version')
      changes = params['contentChanges'] || []
      return if uri.nil? || changes.empty?

      text = changes.last['text']
      store(uri, text, version)
      publish_diagnostics(uri, text, version)
    end

    def on_did_save(params)
      uri = params.dig('textDocument', 'uri')
      entry = @sources[uri]
      return unless entry

      publish_diagnostics(uri, entry[:text], entry[:version])
    end

    def on_did_close(params)
      uri = params.dig('textDocument', 'uri')
      return unless uri

      @sources.delete(uri)
      notify('textDocument/publishDiagnostics', { uri:, diagnostics: [] })
    end

    def formatting(params)
      uri = params.dig('textDocument', 'uri')
      entry = @sources[uri]
      return [] unless entry

      formatted = Kapusta::Formatter.format(entry[:text], path: uri_to_path(uri))
      return [] if formatted == entry[:text]

      [{ range: full_range(entry[:text]), newText: formatted }]
    rescue Kapusta::Error
      []
    end

    def store(uri, text, version)
      @sources[uri] = { text:, version: }
    end

    def publish_diagnostics(uri, text, version)
      diagnostics = collect_diagnostics(text, uri_to_path(uri))
      params = { uri:, diagnostics: }
      params[:version] = version unless version.nil?
      notify('textDocument/publishDiagnostics', params)
    end

    def collect_diagnostics(text, path)
      Kapusta.compile(text, path: path || '(buffer)')
      []
    rescue Kapusta::Error => e
      [diagnostic_from(e, text)]
    end

    def diagnostic_from(error, text)
      line = [(error.line || 1) - 1, 0].max
      column = [(error.column || 1) - 1, 0].max

      {
        range: {
          start: { line:, character: column },
          end: { line:, character: column + token_length(text, line, column) }
        },
        severity: SEVERITY_ERROR,
        source: 'kapusta-ls',
        message: error.reason
      }
    end

    def token_length(text, line, column)
      source_line = text.lines[line]
      return 1 unless source_line

      tail = source_line[column..] || ''
      match = tail.match(/\A[^\s()\[\]{}";`,]+/)
      match && match[0].length.positive? ? match[0].length : 1
    end

    def full_range(text)
      lines = text.split("\n", -1)
      end_line = [lines.length - 1, 0].max
      end_character = lines.last ? lines.last.length : 0
      {
        start: { line: 0, character: 0 },
        end: { line: end_line, character: end_character }
      }
    end

    def uri_to_path(uri)
      return unless uri

      parsed = URI.parse(uri)
      return URI::DEFAULT_PARSER.unescape(parsed.path) if parsed.scheme == 'file'

      uri
    rescue URI::InvalidURIError
      uri
    end

    def log(message)
      @log.puts "kapusta-ls: #{message}"
    end
  end
end
