# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'rbconfig'

ERRORS_DIR = File.expand_path('../examples-errors', __dir__)
KAPUSTA_BIN = File.expand_path('../exe/kapusta', __dir__)
KAPFMT_BIN = File.expand_path('../exe/kapfmt', __dir__)

def run_error_example(name)
  k_out, k_err, k_status = Open3.capture3(RbConfig.ruby, KAPUSTA_BIN, name, chdir: ERRORS_DIR)
  f_out, f_err, f_status = Open3.capture3(RbConfig.ruby, KAPFMT_BIN, name, chdir: ERRORS_DIR)

  raise "kapusta unexpectedly succeeded for #{name}" if k_status.success?
  raise "kapfmt unexpectedly succeeded for #{name}" if f_status.success?
  raise "kapusta wrote to stdout for #{name}: #{k_out.inspect}" unless k_out.empty?
  raise "kapfmt wrote to stdout for #{name}: #{f_out.inspect}" unless f_out.empty?
  raise "kapusta and kapfmt disagree for #{name}:\n  kapusta: #{k_err}  kapfmt: #{f_err}" unless k_err == f_err

  k_err
end

RSpec.describe 'examples-errors' do
  it 'accumulate-missing-iterator.kap' do
    expect(run_error_example('accumulate-missing-iterator.kap'))
      .to eq("accumulate-missing-iterator.kap:5:3: expected initial value and iterator binding table\n")
  end

  it 'auto-gensym-outside-quasiquote.kap' do
    expect(run_error_example('auto-gensym-outside-quasiquote.kap'))
      .to eq("auto-gensym-outside-quasiquote.kap: auto-gensym x# outside quasiquote\n")
  end

  it 'bad-multisym.kap' do
    expect(run_error_example('bad-multisym.kap'))
      .to eq("bad-multisym.kap:1:8: bad multisym: unbound.foo\n")
  end

  it 'bad-set-target.kap' do
    expect(run_error_example('bad-set-target.kap'))
      .to eq("bad-set-target.kap:2:1: bad set target: 1\n")
  end

  it 'bad-shorthand.kap' do
    expect(run_error_example('bad-shorthand.kap'))
      .to eq("bad-shorthand.kap:2:14: bad shorthand\n")
  end

  it 'call-empty-form.kap' do
    expect(run_error_example('call-empty-form.kap'))
      .to eq("call-empty-form.kap:7:8: expected a function, macro, or special to call\n")
  end

  it 'call-literal-number.kap' do
    expect(run_error_example('call-literal-number.kap'))
      .to eq("call-literal-number.kap:6:14: cannot call literal value 1\n")
  end

  it 'cannot-set-method-binding.kap' do
    expect(run_error_example('cannot-set-method-binding.kap'))
      .to eq("cannot-set-method-binding.kap:2:1: cannot set method binding: foo\n")
  end

  it 'case-no-patterns.kap' do
    expect(run_error_example('case-no-patterns.kap'))
      .to eq("case-no-patterns.kap:3:5: expected at least one pattern/body pair\n")
  end

  it 'case-no-subject.kap' do
    expect(run_error_example('case-no-subject.kap'))
      .to eq("case-no-subject.kap:1:1: missing subject\n")
  end

  it 'case-odd-pattern-body.kap' do
    expect(run_error_example('case-odd-pattern-body.kap'))
      .to eq("case-odd-pattern-body.kap:2:3: expected even number of pattern/body pairs\n")
  end

  it 'case-unsupported.kap' do
    expect(run_error_example('case-unsupported.kap'))
      .to eq("case-unsupported.kap:1:1: case/match clauses use patterns this compiler cannot translate\n")
  end

  it 'destructure-literal-number.kap' do
    expect(run_error_example('destructure-literal-number.kap'))
      .to eq("destructure-literal-number.kap:5:3: could not destructure literal\n")
  end

  it 'destructure-literal-table.kap' do
    expect(run_error_example('destructure-literal-table.kap'))
      .to eq("destructure-literal-table.kap:4:1: could not destructure literal\n")
  end

  it 'destructure-rest-as-table.kap' do
    expect(run_error_example('destructure-rest-as-table.kap'))
      .to eq("destructure-rest-as-table.kap:6:3: unable to bind table ...\n")
  end

  it 'dot-without-table.kap' do
    expect(run_error_example('dot-without-table.kap'))
      .to eq("dot-without-table.kap:5:15: expected table argument\n")
  end

  it 'each-not-binding-table.kap' do
    expect(run_error_example('each-not-binding-table.kap'))
      .to eq("each-not-binding-table.kap:6:3: expected binding table\n")
  end

  it 'faccumulate-missing-iterator.kap' do
    expect(run_error_example('faccumulate-missing-iterator.kap'))
      .to eq("faccumulate-missing-iterator.kap:7:3: expected initial value and iterator binding table\n")
  end

  it 'fcollect-missing-range.kap' do
    expect(run_error_example('fcollect-missing-range.kap'))
      .to eq("fcollect-missing-range.kap:6:3: expected range to include start and stop\n")
  end

  it 'fn-non-symbol-param.kap' do
    expect(run_error_example('fn-non-symbol-param.kap'))
      .to eq("fn-non-symbol-param.kap:4:1: destructure pattern this compiler cannot translate: [1 2]\n")
  end

  it 'fn-without-params.kap' do
    expect(run_error_example('fn-without-params.kap'))
      .to eq("fn-without-params.kap:4:11: expected parameters table\n")
  end

  it 'for-missing-stop.kap' do
    expect(run_error_example('for-missing-stop.kap'))
      .to eq("for-missing-stop.kap:6:3: expected range to include start and stop\n")
  end

  it 'global-non-symbol-name.kap' do
    expect(run_error_example('global-non-symbol-name.kap'))
      .to eq("global-non-symbol-name.kap:6:1: unable to bind integer 1\n")
  end

  it 'global-without-value.kap' do
    expect(run_error_example('global-without-value.kap'))
      .to eq("global-without-value.kap:6:1: expected name and value\n")
  end

  it 'icollect-missing-iterator.kap' do
    expect(run_error_example('icollect-missing-iterator.kap'))
      .to eq("icollect-missing-iterator.kap:6:3: expected iterator binding table\n")
  end

  it 'if-no-body.kap' do
    expect(run_error_example('if-no-body.kap'))
      .to eq("if-no-body.kap:8:5: expected condition and body\n")
  end

  it 'import-macros-missing-module.kap' do
    expect(run_error_example('import-macros-missing-module.kap'))
      .to eq("import-macros-missing-module.kap:4:1: import-macros: module nonexistent-module not found\n")
  end

  it 'import-macros-macro-not-found.kap' do
    message = 'import-macros: macro missing not exported by module missing-macro-helper'
    expect(run_error_example('import-macros-macro-not-found.kap'))
      .to eq("import-macros-macro-not-found.kap:1:1: #{message}\n")
  end

  it 'import-macros-no-exports.kap' do
    expect(run_error_example('import-macros-no-exports.kap'))
      .to eq("import-macros-no-exports.kap:1:1: import-macros: module no-exports-helper has no export table\n")
  end

  it 'import-macros-module-invalid.kap' do
    expect(run_error_example('import-macros-module-invalid.kap'))
      .to eq("import-macros-module-invalid.kap:1:1: import-macros expects a symbol or string module name\n")
  end

  it 'invalid-class-name.kap' do
    expect(run_error_example('invalid-class-name.kap'))
      .to eq("invalid-class-name.kap: invalid class name: lowercase\n")
  end

  it 'invalid-module-name.kap' do
    expect(run_error_example('invalid-module-name.kap'))
      .to eq("invalid-module-name.kap: invalid module name: lowercase\n")
  end

  it 'let-odd-bindings.kap' do
    expect(run_error_example('let-odd-bindings.kap'))
      .to eq("let-odd-bindings.kap:2:3: expected even number of name/value bindings\n")
  end

  it 'let-without-body-form.kap' do
    expect(run_error_example('let-without-body-form.kap'))
      .to eq("let-without-body-form.kap:4:5: expected body expression\n")
  end

  it 'local-with-extra-args.kap' do
    expect(run_error_example('local-with-extra-args.kap'))
      .to eq("local-with-extra-args.kap:6:3: local: expected name and value\n")
  end

  it 'local-without-value.kap' do
    expect(run_error_example('local-without-value.kap'))
      .to eq("local-without-value.kap:6:3: local: expected name and value\n")
  end

  it 'macro-name-must-be-symbol.kap' do
    expect(run_error_example('macro-name-must-be-symbol.kap'))
      .to eq("macro-name-must-be-symbol.kap: macro name must be a symbol\n")
  end

  it 'macro-params-must-be-vector.kap' do
    expect(run_error_example('macro-params-must-be-vector.kap'))
      .to eq("macro-params-must-be-vector.kap:1:12: macro params must be a vector\n")
  end

  it 'macro-unsafe-bind.kap' do
    expect(run_error_example('macro-unsafe-bind.kap'))
      .to eq("macro-unsafe-bind.kap:13:8: macro tried to bind unsafe without gensym\n")
  end

  it 'macro-vararg-with-operator.kap' do
    expect(run_error_example('macro-vararg-with-operator.kap'))
      .to eq("macro-vararg-with-operator.kap:5:3: tried to use vararg with operator\n")
  end

  it 'macros-entry-must-be-fn.kap' do
    expect(run_error_example('macros-entry-must-be-fn.kap'))
      .to eq("macros-entry-must-be-fn.kap: macros entry value must be a fn form, got 1\n")
  end

  it 'macros-entry-params-must-be-vector.kap' do
    expect(run_error_example('macros-entry-params-must-be-vector.kap'))
      .to eq("macros-entry-params-must-be-vector.kap:1:19: macros entry params must be a vector\n")
  end

  it 'macros-expects-hash.kap' do
    expect(run_error_example('macros-expects-hash.kap'))
      .to eq("macros-expects-hash.kap: macros expects a hash literal\n")
  end

  it 'match-no-patterns.kap' do
    expect(run_error_example('match-no-patterns.kap'))
      .to eq("match-no-patterns.kap:3:5: expected at least one pattern/body pair\n")
  end

  it 'match-no-subject.kap' do
    expect(run_error_example('match-no-subject.kap'))
      .to eq("match-no-subject.kap:1:1: missing subject\n")
  end

  it 'mismatched-brackets.kap' do
    expect(run_error_example('mismatched-brackets.kap'))
      .to eq("mismatched-brackets.kap:4:19: unexpected closing delimiter ')'\n")
  end

  it 'nested-quasiquote.kap' do
    expect(run_error_example('nested-quasiquote.kap'))
      .to eq("nested-quasiquote.kap: nested quasiquote is not supported\n")
  end

  it 'odd-forms-in-hash.kap' do
    expect(run_error_example('odd-forms-in-hash.kap'))
      .to eq("odd-forms-in-hash.kap:1:9: odd number of forms in hash\n")
  end

  it 'only-rest-param.kap' do
    expect(run_error_example('only-rest-param.kap'))
      .to eq("only-rest-param.kap:4:1: expected rest argument before last parameter\n")
  end

  it 'quote-runtime.kap' do
    expect(run_error_example('quote-runtime.kap'))
      .to eq("quote-runtime.kap:6:1: cannot emit form: `hello\n")
  end

  it 'rest-not-last.kap' do
    expect(run_error_example('rest-not-last.kap'))
      .to eq("rest-not-last.kap:6:3: expected rest argument before last parameter\n")
  end

  it 'set-immutable-let.kap' do
    expect(run_error_example('set-immutable-let.kap'))
      .to eq("set-immutable-let.kap:2:3: expected var counter\n")
  end

  it 'set-immutable-local.kap' do
    expect(run_error_example('set-immutable-local.kap'))
      .to eq("set-immutable-local.kap:8:3: expected var counter\n")
  end

  it 'shadow-special-fn.kap' do
    expect(run_error_example('shadow-special-fn.kap'))
      .to eq("shadow-special-fn.kap:6:3: local fn was overshadowed by a special form or macro\n")
  end

  it 'shadow-special-if.kap' do
    expect(run_error_example('shadow-special-if.kap'))
      .to eq("shadow-special-if.kap:4:1: local if was overshadowed by a special form or macro\n")
  end

  it 'symbol-starting-with-digit.kap' do
    expect(run_error_example('symbol-starting-with-digit.kap'))
      .to eq("symbol-starting-with-digit.kap:6:10: could not read number \"5var\"\n")
  end

  it 'tset-missing-value.kap' do
    expect(run_error_example('tset-missing-value.kap'))
      .to eq("tset-missing-value.kap:5:5: tset: expected table, key, and value arguments\n")
  end

  it 'unbalanced-parens.kap' do
    expect(run_error_example('unbalanced-parens.kap'))
      .to eq("unbalanced-parens.kap:4:1: unclosed opening delimiter '('\n")
  end

  it 'unclosed-table.kap' do
    expect(run_error_example('unclosed-table.kap'))
      .to eq("unclosed-table.kap:4:21: unexpected closing delimiter ']'\n")
  end

  it 'undefined-symbol.kap' do
    expect(run_error_example('undefined-symbol.kap'))
      .to eq("undefined-symbol.kap:1:8: undefined symbol: missing-symbol\n")
  end

  it 'unexpected-eof.kap' do
    expect(run_error_example('unexpected-eof.kap'))
      .to eq("unexpected-eof.kap:1:2: unexpected eof\n")
  end

  it 'unexpected-vararg.kap' do
    expect(run_error_example('unexpected-vararg.kap'))
      .to eq("unexpected-vararg.kap:2:10: unexpected vararg\n")
  end

  it 'unknown-special-form.kap' do
    expect(run_error_example('unknown-special-form.kap'))
      .to eq("unknown-special-form.kap:1:1: unknown special form: catch\n")
  end

  it 'unquote-outside-quote.kap' do
    expect(run_error_example('unquote-outside-quote.kap'))
      .to eq("unquote-outside-quote.kap:5:10: cannot emit form: ,x\n")
  end

  it 'unquote-splice-outside-list.kap' do
    expect(run_error_example('unquote-splice-outside-list.kap'))
      .to eq("unquote-splice-outside-list.kap: unquote-splice must appear inside a quoted list/vec\n")
  end

  it 'unterminated-string.kap' do
    expect(run_error_example('unterminated-string.kap'))
      .to eq("unterminated-string.kap:1:8: unterminated string\n")
  end

  it 'vararg-not-last.kap' do
    expect(run_error_example('vararg-not-last.kap'))
      .to eq("vararg-not-last.kap:1:1: expected vararg as last parameter\n")
  end

  it 'var-without-value.kap' do
    expect(run_error_example('var-without-value.kap'))
      .to eq("var-without-value.kap:6:3: var: expected name and value\n")
  end

  it 'when-no-body.kap' do
    expect(run_error_example('when-no-body.kap'))
      .to eq("when-no-body.kap:4:3: when: expected body\n")
  end
end
