if exists('b:did_ftplugin')
  finish
endif
let b:did_ftplugin = 1

setlocal commentstring=;\ %s
setlocal comments=:;
setlocal iskeyword=33,36-39,42-43,45-58,60-63,64-90,94-122,126,_,!,?

setlocal lisp
setlocal lispwords=fn,defn,lambda,hashfn,let,local,var,global,set,tset,
                  \if,when,unless,case,match,where,do,for,each,while,
                  \collect,icollect,fcollect,accumulate,faccumulate,
                  \try,catch,finally,ensure,begin,raise,
                  \class,module,end,require,doto,thread,values,
                  \quasi-list,quasi-vec,quasi-hash,quasi-sym

let b:undo_ftplugin = 'setlocal commentstring< comments< iskeyword< lisp< lispwords<'
