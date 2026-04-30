# frozen_string_literal: true

module Kapusta
  # rubocop:disable Style/FormatStringToken
  module Errors
    MESSAGES = {
      accumulate_no_iterator: 'expected initial value and iterator binding table',
      auto_gensym_outside_quasiquote: 'auto-gensym %{name}# outside quasiquote',
      bad_multisym: 'bad multisym: %{path}',
      bad_set_target: 'bad set target: %{target}',
      bad_shorthand: 'bad shorthand',
      bind_table_dots: 'unable to bind table ...',
      cannot_call_constant: 'cannot call constant %{name}; reference it without parentheses',
      cannot_call_literal: 'cannot call literal value %{value}',
      cannot_emit_form: 'cannot emit form: %{form}',
      cannot_set_method_binding: 'cannot set method binding: %{name}',
      case_no_patterns: 'expected at least one pattern/body pair',
      case_no_subject: 'missing subject',
      case_odd_patterns: 'expected even number of pattern/body pairs',
      case_unsupported: 'case/match clauses use patterns this compiler cannot translate',
      could_not_destructure_literal: 'could not destructure literal',
      could_not_read_number: 'could not read number "%{token}"',
      counted_no_range: 'expected range to include start and stop',
      destructure_unsupported: 'destructure pattern this compiler cannot translate: %{pattern}',
      dot_no_args: 'expected table argument',
      each_no_binding: 'expected binding table',
      empty_call: 'expected a function, macro, or special to call',
      end_outside_header: 'end outside class or module',
      end_with_args: 'end takes no arguments',
      unclosed_header: 'class or module not closed with (end)',
      expected_var: 'expected var %{name}',
      fn_no_params: 'expected parameters table',
      global_arity: 'expected name and value',
      global_non_symbol_name: 'unable to bind %{type} %{value}',
      icollect_no_iterator: 'expected iterator binding table',
      if_no_body: 'expected condition and body',
      import_macros_cycle: 'import-macros cycle detected for module %{module}',
      import_macros_destructure_invalid: 'import-macros expects a hash literal as first argument',
      import_macros_macro_not_found: 'import-macros: macro %{macro} not exported by module %{module}',
      import_macros_module_invalid: 'import-macros expects a symbol or string module name',
      import_macros_module_no_exports: 'import-macros: module %{module} has no export table',
      import_macros_module_not_found: 'import-macros: module %{module} not found',
      invalid_class_name: 'invalid class name: %{name}',
      invalid_module_name: 'invalid module name: %{name}',
      let_no_body: 'expected body expression',
      let_odd_bindings: 'expected even number of name/value bindings',
      local_arity: '%{form}: expected name and value',
      macro_name_must_be_symbol: 'macro name must be a symbol',
      macro_params_must_be_vector: 'macro params must be a vector',
      macro_unsafe_bind: 'macro tried to bind %{name} without gensym',
      macros_entry_must_be_fn: 'macros entry value must be a fn form, got %{form}',
      macros_entry_params_must_be_vector: 'macros entry params must be a vector',
      macros_expects_hash: 'macros expects a hash literal',
      nested_quasiquote: 'nested quasiquote is not supported',
      odd_forms_in_hash: 'odd number of forms in hash',
      rest_not_last: 'expected rest argument before last parameter',
      shadowed_special: 'local %{name} was overshadowed by a special form or macro',
      target_requires_compile: '--target requires --compile',
      tset_no_value: 'tset: expected table, key, and value arguments',
      unclosed_delimiter: "unclosed opening delimiter '%{char}'",
      undefined_symbol: 'undefined symbol: %{name}',
      unexpected_closing_delimiter: "unexpected closing delimiter '%{char}'",
      unexpected_eof: 'unexpected eof',
      unexpected_vararg: 'unexpected vararg',
      unknown_special_form: 'unknown special form: %{name}',
      unknown_target: 'unknown target %{target}; only mruby is supported',
      unquote_outside_quasiquote: 'unquote outside quasiquote',
      unquote_splice_outside_list: 'unquote-splice must appear inside a quoted list/vec',
      unterminated_string: 'unterminated string',
      vararg_not_last: 'expected vararg as last parameter',
      vararg_with_operator: 'tried to use vararg with operator',
      when_no_body: '%{form}: expected body'
    }.freeze

    def self.format(code, **args)
      template = MESSAGES.fetch(code) { raise ArgumentError, "unknown error code: #{code.inspect}" }
      args.empty? ? template.dup : (template % args)
    end
  end
  # rubocop:enable Style/FormatStringToken
end
