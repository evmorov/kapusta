# Kapusta

Kapusta is a Lisp for the Ruby runtime.

It is inspired by [Fennel](https://fennel-lang.org). Kapusta aims to bring the simplicity and joy of Lisp to Ruby. Where Fennel uses Lua's stdlib and runtime, Kapusta uses Ruby's.

For more information about Kapusta, see the official Fennel documentation and tutorials, but replace Lua with Ruby.

## Features

1. Compiles to readable Ruby.
2. Compiled `.rb` files don't depend on Kapusta. Run with plain `ruby`, or load `.kap` files at runtime via `require 'kapusta'`.
3. Two-way Ruby interop.

## Install

```
gem install kapusta
```

It installs three executables:

1. `kapusta`
2. `kapfmt`
3. `kapusta-ls`

## Use

```
kapusta examples/fizzbuzz.kap
```

or

```
exe/kapusta examples/fizzbuzz.kap
```

or

```
kapusta --compile examples/fizzbuzz.kap > examples/fizzbuzz.rb
ruby examples/fizzbuzz.rb
```

For mruby-compatible output, such as DragonRuby, use:

```
kapusta --compile --target=mruby examples/match.kap > examples/match-mruby.rb
```

## Use from Ruby

Ruby can require a `.kap` file and use it directly.

```
require 'kapusta'
Kapusta.require('./bank-account', relative_to: __FILE__)
account = BankAccount.new('Ada', 100)
```

See `examples/bank-account.kap` and `examples/use_bank_account.rb`.

## Examples

See [`examples/`](https://github.com/evmorov/kapusta/tree/main/examples/) and [`examples-compiled/`](https://github.com/evmorov/kapusta/tree/main/examples-compiled/).

```fennel
(fn ack [m n]
  (if (= m 0) (+ n 1)
      (= n 0) (ack (- m 1) 1)
      (ack (- m 1) (ack m (- n 1)))))

(print (ack 2 3))
(print (ack 3 3))
```

Compiles to:

```ruby
def ack(m, n)
  if m == 0
    n + 1
  elsif n == 0
    ack(m - 1, 1)
  else
    ack(m - 1, ack(m, n - 1))
  end
end
p ack(2, 3)
p ack(3, 3)
```

## Comparison with Fennel

Kapusta keeps most core Fennel forms. The main differences come from Ruby's runtime and object model.

| Fennel                                | Kapusta                                               |
|---------------------------------------|-------------------------------------------------------|
| Lua stdlib                            | Ruby stdlib                                           |
| `:foo` is a Lua string                | `:foo` is a Ruby symbol                               |
| `(. xs 1)` is the first element       | `(. xs 0)` is the first element                       |
| `string.format`, `table.insert`, etc. | use Ruby methods and stdlib instead                   |
| `values` uses Lua multiple returns    | `values` lowers to a Ruby array, usually destructured |
| `(print x)` is Lua's `print` (bare)   | `(print x)` is Ruby's `p` (inspect-style)             |
| `with-open`, `tail!`                  | not provided                                          |

Kapusta-specific additions:

- `module` and `class` for Ruby host structure, including file-header forms
- `(end)` closes a bodyless file-header
- `(defn name ...)` or `(fn class.name ..)`
- `ivar` or `@var` / `cvar` or `@@var` / `gvar` or `$var`
- `try` / `catch` / `finally` plus `raise` for exceptions
- `(ruby "...")` raw host escape hatch
- pass Ruby keyword arguments by ending a call with a symbol-keyed hash: `(File.open path "r" {:encoding "UTF-8"})`
- pass a Ruby block by ending a call with a `(fn ...)` or `#(...)` literal: `(File.open path "r" (fn [io] (: io :read)))`

## Format

```
kapfmt --fix examples/fizzbuzz.kap
```

## LSP

Use `kapusta-ls` in the editor of your choice.

## Syntax highlight

For Vim, you can use [`vim-syntax/`](https://github.com/evmorov/kapusta/tree/main/vim-syntax/).

## License

[MIT](LICENSE)
