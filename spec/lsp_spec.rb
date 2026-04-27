# frozen_string_literal: true

require 'spec_helper'
require 'kapusta/lsp'
require 'json'
require 'stringio'

RSpec.describe Kapusta::LSP do
  def frame(payload)
    body = JSON.generate(payload)
    "Content-Length: #{body.bytesize}\r\n\r\n#{body}"
  end

  def parse_responses(stdout)
    messages = []
    rest = stdout.dup
    while (m = rest.match(/\AContent-Length: (\d+)\r\n\r\n/))
      len = Integer(m[1], 10)
      messages << JSON.parse(rest[m[0].length, len])
      rest = rest[(m[0].length + len)..]
    end
    messages
  end

  def run(*frames)
    input = StringIO.new(frames.join)
    output = StringIO.new
    log = StringIO.new
    described_class.new(input:, output:, log:).run
    parse_responses(output.string)
  end

  it 'advertises diagnostics and formatting capabilities on initialize' do
    responses = run(frame(jsonrpc: '2.0', id: 1, method: 'initialize', params: {}))
    capabilities = responses.first.dig('result', 'capabilities')

    expect(capabilities).to include('textDocumentSync', 'documentFormattingProvider')
  end

  it 'publishes diagnostics for invalid source' do
    responses = run(
      frame(jsonrpc: '2.0', id: 1, method: 'initialize', params: {}),
      frame(jsonrpc: '2.0', method: 'textDocument/didOpen',
            params: { textDocument: { uri: 'file:///x.kap', version: 1, text: '(let [x 1] (+ x ()))' } })
    )
    diagnostics = responses.last.dig('params', 'diagnostics')

    expect(diagnostics).not_to be_empty
  end

  it 'publishes no diagnostics for valid source' do
    responses = run(
      frame(jsonrpc: '2.0', id: 1, method: 'initialize', params: {}),
      frame(jsonrpc: '2.0', method: 'textDocument/didOpen',
            params: { textDocument: { uri: 'file:///x.kap', version: 1, text: '(print "hi")' } })
    )

    expect(responses.last.dig('params', 'diagnostics')).to be_empty
  end

  it 'returns a TextEdit for formatting' do
    responses = run(
      frame(jsonrpc: '2.0', id: 1, method: 'initialize', params: {}),
      frame(jsonrpc: '2.0', method: 'textDocument/didOpen',
            params: { textDocument: { uri: 'file:///x.kap', version: 1, text: "(fn  greet  [x]  (print  x))\n" } }),
      frame(jsonrpc: '2.0', id: 2, method: 'textDocument/formatting',
            params: { textDocument: { uri: 'file:///x.kap' } })
    )
    edits = responses.find { |m| m['id'] == 2 }['result']

    expect(edits).to be_an(Array).and(be_one)
    expect(edits.first).to include('range', 'newText')
  end

  it 'rejects requests sent before initialize' do
    responses = run(
      frame(jsonrpc: '2.0', id: 1, method: 'textDocument/formatting',
            params: { textDocument: { uri: 'file:///x.kap' } })
    )

    expect(responses.first.dig('error', 'code')).to eq(-32_002)
  end
end
