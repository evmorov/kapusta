# Kapusta

Kapusta is a Lisp for the Ruby runtime.

It is inspired by [Fennel](https://fennel-lang.org). It is not intended to be production-ready like Clojure: that would be a lot of work, and Ruby is already a rich, elegant language.

Instead, Kapusta aims to bring some of the simplicity and joy of Lisp to Ruby. Where Lua is intentionally minimal, and Fennel follows that design for good reason, Kapusta exists mostly for fun. You can use it for small apps, LeetCode, DragonRuby, or maybe even Rails.

For more information about Kapusta, see the official Fennel documentation and tutorials.

## Usage

```
gem install kapusta
kapfmt --fix examples/fizzbuzz.kap
kapusta examples/fizzbuzz.kap
```

or

```
exe/kapusta examples/fizzbuzz.kap
```

or

```
exe/kapusta --compile examples/fizzbuzz.kap > examples/fizzbuzz.rb
ruby examples/fizzbuzz.rb
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
| `with-open`, `tail!`                  | not provided                                          |

Kapusta-specific additions:

- `module` and `class` for Ruby host structure, including file-header forms
- `ivar` / `cvar` / `gvar` escape hatches
- `try` / `catch` / `finally` plus `raise` for exceptions
- `(ruby "...")` raw host escape hatch
- a trailing symbol-keyed hash is emitted as Ruby keyword arguments
- a final function literal argument is emitted as a Ruby block

## Examples

See `examples/`.

## Formatting

```
exe/kapfmt
```

## Syntax highlight

For Vim you can use https://git.sr.ht/~m15a/vim-fennel-syntax
