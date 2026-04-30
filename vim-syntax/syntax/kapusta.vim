if exists('b:current_syntax')
  finish
endif

syn case match

syn match  kapustaComment ";.*$" contains=kapustaTodo,@Spell
syn keyword kapustaTodo TODO FIXME XXX HACK NOTE contained

syn region kapustaString start=+"+ skip=+\\\\\|\\"+ end=+"+ contains=kapustaStringEscape,@Spell
syn match  kapustaStringEscape "\\\(x\x\+\|\o\{1,3}\|.\|$\)" contained

syn match kapustaNumber "\<-\?\d\+\(_\d\+\)*\(\.\d\+\(_\d\+\)*\)\?\([eE][-+]\?\d\+\)\?\>"
syn match kapustaNumber "\<-\?0x[0-9a-fA-F]\+\>"
syn match kapustaNumber "\<-\?0b[01]\+\>"
syn match kapustaNumber "\<-\?0o\?[0-7]\+\>"

syn keyword kapustaBoolean true false
syn keyword kapustaConstant nil self

syn match kapustaSymbol ":[A-Za-z_!?][-A-Za-z0-9_!?]*"
syn match kapustaSymbol "\<[A-Za-z_!?][-A-Za-z0-9_!?]*:"

syn match kapustaIvar "@@\?[A-Za-z_][A-Za-z0-9_]*"
syn match kapustaGvar "\$[A-Za-z_][A-Za-z0-9_]*"

syn match kapustaAnonArg "\$\d*\>"

syn match kapustaQuote      "`"
syn match kapustaUnquote    ","
syn match kapustaHashFn     "#"

syn keyword kapustaDefine fn defn lambda hashfn let local var global set tset
                          \ class module end require nextgroup=kapustaDefName skipwhite
syn match   kapustaDefName "[A-Za-z_!?][-.A-Za-z0-9_!?]*" contained

syn keyword kapustaSpecial if when unless case match where do
                           \ for each while collect icollect fcollect
                           \ accumulate faccumulate doto thread values
                           \ unpack length
syn keyword kapustaSpecial try catch finally ensure begin raise
syn keyword kapustaSpecial ivar cvar gvar ruby
syn keyword kapustaSpecial quasi-list quasi-list-tail quasi-vec quasi-vec-tail
                           \ quasi-hash quasi-sym quasi-gensym

syn keyword kapustaOperator and or not

syn keyword kapustaBuiltin print p

syn match kapustaOperator "\((\s*\)\@<=[-+*/%]\ze\s"
syn match kapustaOperator "\((\s*\)\@<==\ze\s"
syn match kapustaOperator "\((\s*\)\@<=[<>]=\?\ze\s"
syn match kapustaOperator "\((\s*\)\@<=\.\.\ze\s"

syn match kapustaMethod "\((\s*\)\@<=:\ze\s"
syn match kapustaMethod "\((\s*\)\@<=\.[A-Za-z_!?][-A-Za-z0-9_!?]*\>"

hi def link kapustaComment       Comment
hi def link kapustaTodo          Todo
hi def link kapustaString        String
hi def link kapustaStringEscape  SpecialChar
hi def link kapustaNumber        Number
hi def link kapustaBoolean       Boolean
hi def link kapustaConstant      Constant
hi def link kapustaSymbol        Constant
hi def link kapustaIvar          Identifier
hi def link kapustaGvar          Identifier
hi def link kapustaAnonArg       Identifier
hi def link kapustaQuote         PreProc
hi def link kapustaUnquote       PreProc
hi def link kapustaHashFn        PreProc
hi def link kapustaDefine        Keyword
hi def link kapustaDefName       Function
hi def link kapustaSpecial       Statement
hi def link kapustaOperator      Operator
hi def link kapustaBuiltin       Function
hi def link kapustaMethod        Function

let b:current_syntax = 'kapusta'
