# frozen_string_literal: true

require 'spec_helper'
require 'kapusta/lsp'
require 'json'
require 'stringio'
require 'tmpdir'

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

  def frame_initialize(folders = [])
    workspace_folders = folders.map { |uri| { uri:, name: 'tmp' } }
    frame(jsonrpc: '2.0', id: 1, method: 'initialize',
          params: { workspaceFolders: workspace_folders })
  end

  def frame_did_open(uri, text, version: 1)
    frame(jsonrpc: '2.0', method: 'textDocument/didOpen',
          params: { textDocument: { uri:, version:, text: } })
  end

  def frame_rename(uri:, line:, character:, new_name:, id: 2)
    frame(jsonrpc: '2.0', id:, method: 'textDocument/rename',
          params: { textDocument: { uri: }, position: { line:, character: }, newName: new_name })
  end

  def frame_prepare_rename(uri:, line:, character:, id: 2)
    frame(jsonrpc: '2.0', id:, method: 'textDocument/prepareRename',
          params: { textDocument: { uri: }, position: { line:, character: } })
  end

  def frame_definition(uri:, line:, character:, id: 2)
    frame(jsonrpc: '2.0', id:, method: 'textDocument/definition',
          params: { textDocument: { uri: }, position: { line:, character: } })
  end

  def frame_formatting(uri:, id: 2)
    frame(jsonrpc: '2.0', id:, method: 'textDocument/formatting',
          params: { textDocument: { uri: } })
  end

  def cursor_at(text, marker)
    idx = text.index(marker) or raise "marker #{marker.inspect} not found in text"
    prefix = text[0...idx]
    last_nl = prefix.rindex("\n")
    { line: prefix.count("\n"), character: last_nl ? idx - last_nl - 1 : idx }
  end

  def result_for(responses, id = 2)
    responses.find { |m| m['id'] == id }
  end

  def with_workspace(files)
    Dir.mktmpdir do |dir|
      uris = files.to_h do |name, text|
        path = File.join(dir, name)
        File.write(path, text)
        [name, "file://#{File.expand_path(path)}"]
      end
      root_uri = "file://#{File.expand_path(dir)}"
      yield(root_uri, uris)
    end
  end

  it 'advertises diagnostics and formatting capabilities on initialize' do
    responses = run(frame_initialize)
    capabilities = responses.first.dig('result', 'capabilities')

    expect(capabilities).to include('textDocumentSync', 'documentFormattingProvider')
    expect(capabilities['definitionProvider']).to be(true)
  end

  it 'publishes diagnostics for invalid source' do
    responses = run(
      frame_initialize,
      frame_did_open('file:///x.kap', '(let [x 1] (+ x ()))')
    )

    expect(responses.last.dig('params', 'diagnostics')).not_to be_empty
  end

  it 'publishes no diagnostics for valid source' do
    responses = run(
      frame_initialize,
      frame_did_open('file:///x.kap', '(print "hi")')
    )

    expect(responses.last.dig('params', 'diagnostics')).to be_empty
  end

  it 'returns a TextEdit for formatting' do
    responses = run(
      frame_initialize,
      frame_did_open('file:///x.kap', "(fn  greet  [x]  (print  x))\n"),
      frame_formatting(uri: 'file:///x.kap')
    )
    edits = result_for(responses)['result']

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

  it 'renames a let binding within a single file' do
    text = '(let [x 1] (+ x x))'
    responses = run(
      frame_initialize,
      frame_did_open('file:///x.kap', text),
      frame_rename(uri: 'file:///x.kap', **cursor_at(text, 'x'), new_name: 'y')
    )
    changes = result_for(responses)['result']['documentChanges']

    expect(changes.length).to eq(1)
    expect(changes.first['edits'].map { |e| e['newText'] }).to eq(%w[y y y])
  end

  it 'renames a let binding referenced inside an accumulate iterator with multiple binders' do
    text = "(let [xs [1 2 3]\n      total (accumulate [s 0 _ x (ipairs xs)] (+ s x))]\n  (print total))\n"
    idx = text.index('(ipairs xs)') + 'ipairs '.length + 1
    prefix = text[0...idx]
    last_nl = prefix.rindex("\n")
    position = { line: prefix.count("\n"), character: last_nl ? idx - last_nl - 1 : idx }
    responses = run(
      frame_initialize,
      frame_did_open('file:///x.kap', text),
      frame_rename(uri: 'file:///x.kap', **position, new_name: 'ys')
    )
    changes = result_for(responses)['result']['documentChanges']

    expect(changes.length).to eq(1)
    expect(changes.first['edits'].map { |e| e['newText'] }).to eq(%w[ys ys])
  end

  it 'renames a for-loop counter referenced inside &until' do
    text = "(for [d 2 10 &until (>= d 5)] (print d))\n"
    responses = run(
      frame_initialize,
      frame_did_open('file:///x.kap', text),
      frame_rename(uri: 'file:///x.kap', **cursor_at(text, 'd'), new_name: 'k')
    )
    edits = result_for(responses)['result']['documentChanges'].first['edits']

    expect(edits.map { |e| e['newText'] }).to eq(%w[k k k])
  end

  it 'renames a top-level fn across files' do
    text_a = "(fn greet [n] (print n))\n(greet \"x\")\n"
    text_b = "(greet 42)\n"
    with_workspace('a.kap' => text_a, 'b.kap' => text_b) do |root_uri, uri|
      responses = run(
        frame_initialize([root_uri]),
        frame_did_open(uri['a.kap'], text_a),
        frame_rename(uri: uri['a.kap'], **cursor_at(text_a, 'greet'), new_name: 'hello')
      )
      changes = result_for(responses)['result']['documentChanges']

      expect(changes.map { |c| c['textDocument']['uri'] }).to include(uri['a.kap'], uri['b.kap'])
    end
  end

  it 'renames a module constant rewriting only the matching segment in dotted references' do
    text_a = "(module Foo (fn bar [] 1))\n"
    text_b = "(Foo.bar)\n(Foo.new)\n"
    with_workspace('a.kap' => text_a, 'b.kap' => text_b) do |root_uri, uri|
      responses = run(
        frame_initialize([root_uri]),
        frame_did_open(uri['a.kap'], text_a),
        frame_rename(uri: uri['a.kap'], **cursor_at(text_a, 'Foo'), new_name: 'Bar')
      )
      b_edits = result_for(responses)['result']['documentChanges']
                .find { |c| c['textDocument']['uri'] == uri['b.kap'] }['edits']

      expect(b_edits.map { |e| [e['range']['start']['character'], e['range']['end']['character'], e['newText']] })
        .to contain_exactly([1, 4, 'Bar'], [1, 4, 'Bar'])
    end
  end

  it 'returns null from prepareRename on a dotted method segment' do
    text = '(Foo.bar 1)'
    responses = run(
      frame_initialize,
      frame_did_open('file:///x.kap', text),
      frame_prepare_rename(uri: 'file:///x.kap', **cursor_at(text, 'bar'))
    )

    expect(result_for(responses)['result']).to be_nil
  end

  it 'renames a constant when the workspace contains hash patterns and the .. special form' do
    text_a = "(class Foo)\n"
    text_b = "(let [{:x x} {:x 1}] (print (.. \"value=\" x)))\n(Foo.new)\n"
    with_workspace('a.kap' => text_a, 'b.kap' => text_b) do |root_uri, uri|
      responses = run(
        frame_initialize([root_uri]),
        frame_did_open(uri['a.kap'], text_a),
        frame_rename(uri: uri['a.kap'], **cursor_at(text_a, 'Foo'), new_name: 'Bar')
      )
      response = result_for(responses)

      expect(response['error']).to be_nil
      uris = response['result']['documentChanges'].map { |c| c['textDocument']['uri'] }
      expect(uris).to include(uri['a.kap'], uri['b.kap'])
    end
  end

  it 'does not offer rename for method definitions after a bodyless class header' do
    text = "(class Counter)\n(fn initialize [start] start)\n"
    responses = run(
      frame_initialize,
      frame_did_open('file:///x.kap', text),
      frame_prepare_rename(uri: 'file:///x.kap', **cursor_at(text, 'initialize'))
    )

    expect(result_for(responses)['result']).to be_nil
  end

  it 'does not let class methods shadow top-level function references' do
    text = "(fn helper [] 2)\n(class Foo (fn helper [] 1))\n(fn main [] (helper))\n"
    responses = run(
      frame_initialize,
      frame_did_open('file:///x.kap', text),
      frame_rename(uri: 'file:///x.kap', **cursor_at(text, 'helper'), new_name: 'renamed')
    )
    edits = result_for(responses)['result']['documentChanges'].first['edits']

    expect(edits.map { |e| e['range']['start']['line'] }).to contain_exactly(0, 2)
  end

  it 'rejects top-level rename when the new name exists elsewhere in the workspace' do
    text_a = "(fn foo [] 1)\n"
    text_b = "(foo)\n"
    text_c = "(fn bar [] 2)\n"
    with_workspace('a.kap' => text_a, 'b.kap' => text_b, 'c.kap' => text_c) do |root_uri, uri|
      responses = run(
        frame_initialize([root_uri]),
        frame_did_open(uri['a.kap'], text_a),
        frame_rename(uri: uri['a.kap'], **cursor_at(text_a, 'foo'), new_name: 'bar')
      )

      expect(result_for(responses).dig('error', 'message')).to include('already defined')
    end
  end

  it 'rejects constant rename when the new constant prefix exists' do
    text_a = "(class Foo)\n"
    text_b = "(class Bar)\n"
    with_workspace('a.kap' => text_a, 'b.kap' => text_b) do |root_uri, uri|
      responses = run(
        frame_initialize([root_uri]),
        frame_did_open(uri['a.kap'], text_a),
        frame_rename(uri: uri['a.kap'], **cursor_at(text_a, 'Foo'), new_name: 'Bar')
      )

      expect(result_for(responses).dig('error', 'message')).to include('already defined')
    end
  end

  it 'jumps to a let binder from a usage in the same file' do
    text = '(let [x 1] (+ x x))'
    responses = run(
      frame_initialize,
      frame_did_open('file:///x.kap', text),
      frame_definition(uri: 'file:///x.kap', line: 0, character: 14)
    )
    result = result_for(responses)['result']

    expect(result).to eq(
      'uri' => 'file:///x.kap',
      'range' => {
        'start' => { 'line' => 0, 'character' => 6 },
        'end' => { 'line' => 0, 'character' => 7 }
      }
    )
  end

  it 'jumps to a top-level fn definition across files' do
    text_a = "(fn greet [n] (print n))\n"
    text_b = "(greet 42)\n"
    with_workspace('a.kap' => text_a, 'b.kap' => text_b) do |root_uri, uri|
      responses = run(
        frame_initialize([root_uri]),
        frame_did_open(uri['b.kap'], text_b),
        frame_definition(uri: uri['b.kap'], **cursor_at(text_b, 'greet'))
      )
      result = result_for(responses)['result']

      expect(result).to be_an(Array).and(be_one)
      expect(result.first['uri']).to eq(uri['a.kap'])
      expect(result.first['range']['start']).to eq('line' => 0, 'character' => 4)
    end
  end

  it 'jumps to a module definition from a dotted reference across files' do
    text_a = "(module Foo (fn bar [] 1))\n"
    text_b = "(Foo.bar)\n"
    with_workspace('a.kap' => text_a, 'b.kap' => text_b) do |root_uri, uri|
      responses = run(
        frame_initialize([root_uri]),
        frame_did_open(uri['b.kap'], text_b),
        frame_definition(uri: uri['b.kap'], **cursor_at(text_b, 'Foo'))
      )
      result = result_for(responses)['result']

      expect(result).to be_an(Array).and(be_one)
      expect(result.first['uri']).to eq(uri['a.kap'])
      expect(result.first['range']['start']).to eq('line' => 0, 'character' => 8)
    end
  end

  it 'jumps to a macro definition from a call site in the same file' do
    text = "(macro unless [c & body] `(if (not ,c) (do ,(unpack body))))\n(unless false (print 1))\n"
    with_workspace('a.kap' => text) do |root_uri, uri|
      responses = run(
        frame_initialize([root_uri]),
        frame_did_open(uri['a.kap'], text),
        frame_definition(uri: uri['a.kap'], line: 1, character: 1)
      )
      result = result_for(responses)['result']

      expect(result).to eq(
        'uri' => uri['a.kap'],
        'range' => {
          'start' => { 'line' => 0, 'character' => 7 },
          'end' => { 'line' => 0, 'character' => 13 }
        }
      )
    end
  end

  it 'jumps from a call site through (import-macros) to the macro definition file' do
    text_a = "(macro swap! [a b] `(let [tmp# ,a] (set ,a ,b) (set ,b tmp#)))\n"
    text_b = "(import-macros {: swap!} :a)\n(var x 1)\n(var y 2)\n(swap! x y)\n"
    with_workspace('a.kap' => text_a, 'b.kap' => text_b) do |root_uri, uri|
      responses = run(
        frame_initialize([root_uri]),
        frame_did_open(uri['b.kap'], text_b),
        frame_definition(uri: uri['b.kap'], line: 3, character: 1)
      )
      result = result_for(responses)['result']

      expect(result['uri']).to eq(uri['a.kap'])
      expect(result['range']['start']).to eq('line' => 0, 'character' => 7)
    end
  end

  it 'returns null definition when the symbol has no known binding' do
    text = "(foo)\n"
    responses = run(
      frame_initialize,
      frame_did_open('file:///x.kap', text),
      frame_definition(uri: 'file:///x.kap', **cursor_at(text, 'foo'))
    )

    expect(result_for(responses)['result']).to be_nil
  end

  it 'renames a macro definition and its call sites within a file' do
    text = "(macro swap! [a b]\n  `(let [tmp# ,a]\n     (set ,a ,b)\n     (set ,b tmp#)))\n(swap! x y)\n"
    with_workspace('a.kap' => text) do |root_uri, uri|
      responses = run(
        frame_initialize([root_uri]),
        frame_did_open(uri['a.kap'], text),
        frame_rename(uri: uri['a.kap'], **cursor_at(text, 'swap!'), new_name: 'flip!')
      )
      changes = result_for(responses)['result']['documentChanges']

      expect(changes.length).to eq(1)
      edits = changes.first['edits']
      expect(edits.map { |e| e['newText'] }).to eq(%w[flip! flip!])
    end
  end

  it 'renames a macro across files when imported via shorthand destructure' do
    text_a = "(macro swap! [a b]\n  `(let [tmp# ,a] (set ,a ,b) (set ,b tmp#)))\n"
    text_b = "(import-macros {: swap!} :a)\n(var x 1)\n(var y 2)\n(swap! x y)\n"
    with_workspace('a.kap' => text_a, 'b.kap' => text_b) do |root_uri, uri|
      responses = run(
        frame_initialize([root_uri]),
        frame_did_open(uri['a.kap'], text_a),
        frame_rename(uri: uri['a.kap'], **cursor_at(text_a, 'swap!'), new_name: 'flip!')
      )
      changes = result_for(responses)['result']['documentChanges']

      uris = changes.map { |c| c['textDocument']['uri'] }
      expect(uris).to include(uri['a.kap'], uri['b.kap'])

      b_edits = changes.find { |c| c['textDocument']['uri'] == uri['b.kap'] }['edits']
      expect(b_edits.map { |e| e['newText'] }).to all(eq('flip!'))
      expect(b_edits.length).to eq(2)
    end
  end

  it 'renames a macro across files when starting from an imported call site' do
    text_a = "(macro swap! [a b]\n  `(let [tmp# ,a] (set ,a ,b) (set ,b tmp#)))\n"
    text_b = "(import-macros {: swap!} :a)\n(var x 1)\n(var y 2)\n(swap! x y)\n"
    with_workspace('a.kap' => text_a, 'b.kap' => text_b) do |root_uri, uri|
      responses = run(
        frame_initialize([root_uri]),
        frame_did_open(uri['b.kap'], text_b),
        frame_rename(uri: uri['b.kap'],
                     line: 3, character: cursor_at(text_b.lines[3], 'swap!')[:character],
                     new_name: 'flip!')
      )
      changes = result_for(responses)['result']['documentChanges']

      uris = changes.map { |c| c['textDocument']['uri'] }
      expect(uris).to include(uri['a.kap'], uri['b.kap'])
    end
  end

  it 'renames a user macro that shadows a core special form name' do
    text = "(macro unless [c & body] `(if (not ,c) (do ,(unpack body))))\n" \
           "(unless false (print \"x\"))\n(unless true (print \"y\"))\n"
    with_workspace('a.kap' => text) do |root_uri, uri|
      responses = run(
        frame_initialize([root_uri]),
        frame_did_open(uri['a.kap'], text),
        frame_rename(uri: uri['a.kap'], **cursor_at(text, 'unless'), new_name: 'except')
      )
      edits = result_for(responses)['result']['documentChanges'].first['edits']

      expect(edits.map { |e| e['newText'] }).to eq(%w[except except except])
    end
  end

  it 'offers prepareRename on a macro call site shadowing a special form' do
    text = "(macro unless [c & body] `(if (not ,c) (do ,(unpack body))))\n(unless false 1)\n"
    with_workspace('a.kap' => text) do |root_uri, uri|
      responses = run(
        frame_initialize([root_uri]),
        frame_did_open(uri['a.kap'], text),
        frame_prepare_rename(uri: uri['a.kap'], line: 1, character: 1)
      )
      result = result_for(responses)['result']

      expect(result).to include('range', 'placeholder')
      expect(result['placeholder']).to eq('unless')
      expect(result['range']['start']).to eq('line' => 1, 'character' => 1)
      expect(result['range']['end']).to eq('line' => 1, 'character' => 7)
    end
  end

  it 'returns null prepareRename for an unshadowed special form call' do
    text = "(unless false 1)\n"
    responses = run(
      frame_initialize,
      frame_did_open('file:///x.kap', text),
      frame_prepare_rename(uri: 'file:///x.kap', line: 0, character: 1)
    )

    expect(result_for(responses)['result']).to be_nil
  end

  it 'renames only the targeted import when multiple macros are destructured together' do
    text_a = "(macro foo [x] `,x)\n(macro bar [x] `,x)\n"
    text_b = "(import-macros {: foo : bar} :a)\n(foo 1)\n(bar 2)\n"
    with_workspace('a.kap' => text_a, 'b.kap' => text_b) do |root_uri, uri|
      responses = run(
        frame_initialize([root_uri]),
        frame_did_open(uri['a.kap'], text_a),
        frame_rename(uri: uri['a.kap'], **cursor_at(text_a, 'foo'), new_name: 'qux')
      )
      changes = result_for(responses)['result']['documentChanges']
      b_edits = changes.find { |c| c['textDocument']['uri'] == uri['b.kap'] }['edits']

      expect(b_edits.map { |e| e['newText'] }).to all(eq('qux'))
      expect(b_edits.length).to eq(2)
      expect(b_edits.flat_map { |e| [e['range']['start']['line'], e['range']['end']['line']] })
        .to all(satisfy { |n| [0, 1].include?(n) })
    end
  end

  it 'propagates a macro rename to multiple importing files' do
    text_a = "(macro tap [x] `(do (print ,x) ,x))\n"
    text_b = "(import-macros {: tap} :a)\n(tap 1)\n"
    text_c = "(import-macros {: tap} :a)\n(tap 2)\n(tap 3)\n"
    with_workspace('a.kap' => text_a, 'b.kap' => text_b, 'c.kap' => text_c) do |root_uri, uri|
      responses = run(
        frame_initialize([root_uri]),
        frame_did_open(uri['a.kap'], text_a),
        frame_rename(uri: uri['a.kap'], **cursor_at(text_a, 'tap'), new_name: 'spy')
      )
      changes = result_for(responses)['result']['documentChanges']

      expect(changes.map { |c| c['textDocument']['uri'] })
        .to contain_exactly(uri['a.kap'], uri['b.kap'], uri['c.kap'])

      changes.each do |c|
        expect(c['edits'].map { |e| e['newText'] }).to all(eq('spy'))
      end

      c_edits = changes.find { |c| c['textDocument']['uri'] == uri['c.kap'] }['edits']
      expect(c_edits.length).to eq(3)
    end
  end

  it 'jumps to itself when invoked on a macro definition name' do
    text = "(macro tap [x] `(do (print ,x) ,x))\n"
    with_workspace('a.kap' => text) do |root_uri, uri|
      responses = run(
        frame_initialize([root_uri]),
        frame_did_open(uri['a.kap'], text),
        frame_definition(uri: uri['a.kap'], **cursor_at(text, 'tap'))
      )
      result = result_for(responses)['result']

      expect(result).to eq(
        'uri' => uri['a.kap'],
        'range' => {
          'start' => { 'line' => 0, 'character' => 7 },
          'end' => { 'line' => 0, 'character' => 10 }
        }
      )
    end
  end

  it 'jumps through (import-macros) to a fn-defined macro template in a .kapm module' do
    text_helper = "(fn scaled [x] `(* ,x 10))\n{: scaled}\n"
    text_user = "(import-macros {: scaled} :import-helpers)\n(print (scaled 3))\n"
    with_workspace('import-helpers.kapm' => text_helper,
                   'macros-import-helpers.kap' => text_user) do |root_uri, uri|
      responses = run(
        frame_initialize([root_uri]),
        frame_did_open(uri['macros-import-helpers.kap'], text_user),
        frame_definition(uri: uri['macros-import-helpers.kap'],
                         **cursor_at(text_user.lines[1], 'scaled').merge(line: 1))
      )
      result = result_for(responses)['result']

      expect(result['uri']).to eq(uri['import-helpers.kapm'])
      expect(result['range']['start']).to eq('line' => 0, 'character' => 4)
    end
  end

  it 'returns null definition for a special-form call with no shadowing macro' do
    text = "(unless false 1)\n"
    responses = run(
      frame_initialize,
      frame_did_open('file:///x.kap', text),
      frame_definition(uri: 'file:///x.kap', line: 0, character: 1)
    )

    expect(result_for(responses)['result']).to be_nil
  end

  it 'rejects macro rename when the new name conflicts with an existing macro definition' do
    text_a = "(macro swap! [a b] `(do ,a ,b))\n(macro flip! [a b] `(do ,b ,a))\n"
    with_workspace('a.kap' => text_a) do |root_uri, uri|
      responses = run(
        frame_initialize([root_uri]),
        frame_did_open(uri['a.kap'], text_a),
        frame_rename(uri: uri['a.kap'], **cursor_at(text_a, 'swap!'), new_name: 'flip!')
      )

      expect(result_for(responses).dig('error', 'message')).to include('already defined')
    end
  end

  it 'renames an @ivar across methods within a class' do
    text = "(class C)\n(fn one [] (set @counter 1))\n(fn two [] @counter)\n"
    responses = run(
      frame_initialize,
      frame_did_open('file:///x.kap', text),
      frame_rename(uri: 'file:///x.kap', **cursor_at(text, 'counter'), new_name: 'total')
    )
    changes = result_for(responses)['result']['documentChanges']

    expect(changes.length).to eq(1)
    edits = changes.first['edits']
    expect(edits.map { |e| e['newText'] }).to eq(%w[total total])
    expect(edits.map { |e| [e['range']['start']['line'], e['range']['start']['character']] })
      .to contain_exactly([1, 17], [2, 12])
  end

  it 'renames @ivar without touching a same-named fn parameter or value reference' do
    text = "(class C)\n(fn init [val] (set @counter val))\n"
    responses = run(
      frame_initialize,
      frame_did_open('file:///x.kap', text),
      frame_rename(uri: 'file:///x.kap', **cursor_at(text, 'counter'), new_name: 'total')
    )
    changes = result_for(responses)['result']['documentChanges']

    expect(changes.length).to eq(1)
    edits = changes.first['edits']
    expect(edits.length).to eq(1)
    expect(edits.first['newText']).to eq('total')
    expect(edits.first['range']['start']).to eq('line' => 1, 'character' => 21)
  end

  it 'renames a $gvar within a file' do
    text = "(set $last 1)\n(print $last)\n"
    responses = run(
      frame_initialize,
      frame_did_open('file:///x.kap', text),
      frame_rename(uri: 'file:///x.kap', **cursor_at(text, 'last'), new_name: 'latest')
    )
    changes = result_for(responses)['result']['documentChanges']

    expect(changes.length).to eq(1)
    edits = changes.first['edits']
    expect(edits.map { |e| e['newText'] }).to eq(%w[latest latest])
  end

  it 'keeps @x and @@x in separate sigil namespaces' do
    text = "(class C)\n(set @@flag 1)\n(fn show [] (set @flag 2))\n"
    ivar_position = { line: 2, character: 18 }
    responses = run(
      frame_initialize,
      frame_did_open('file:///x.kap', text),
      frame_rename(uri: 'file:///x.kap', **ivar_position, new_name: 'mark')
    )
    changes = result_for(responses)['result']['documentChanges']

    expect(changes.length).to eq(1)
    edits = changes.first['edits']
    expect(edits.length).to eq(1)
    expect(edits.first['newText']).to eq('mark')
    expect(edits.first['range']['start']).to eq('line' => 2, 'character' => 18)
  end

  it 'jumps to the first @@cvar binding from a later use site' do
    text = "(class C)\n(set @@total 0)\n(fn add [] (set @@total (+ @@total 1)))\n"
    use_index = text.rindex('@@total') + 2
    prefix = text[0...use_index]
    last_nl = prefix.rindex("\n")
    pos = { line: prefix.count("\n"), character: last_nl ? use_index - last_nl - 1 : use_index }

    responses = run(
      frame_initialize,
      frame_did_open('file:///x.kap', text),
      frame_definition(uri: 'file:///x.kap', **pos)
    )
    result = result_for(responses)['result']

    expect(result).to eq(
      'uri' => 'file:///x.kap',
      'range' => {
        'start' => { 'line' => 1, 'character' => 7 },
        'end' => { 'line' => 1, 'character' => 12 }
      }
    )
  end

  it 'escapes file URIs built during workspace scans' do
    Dir.mktmpdir do |dir|
      nested = File.join(dir, 'space dir')
      Dir.mkdir(nested)
      File.write(File.join(nested, 'a b#c.kap'), "(fn greet [] 1)\n")

      index = Kapusta::LSP::WorkspaceIndex.new(roots: [nested]).scan!
      uri = index.toplevel_fn_occurrences('greet').keys.first

      expect(uri).to include('space%20dir')
      expect(uri).to include('a%20b%23c.kap')
    end
  end
end
