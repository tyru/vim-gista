let s:save_cpo = &cpo
set cpo&vim

let s:V = gista#vital()
let s:D = s:V.import('Data.Dict')
let s:A = s:V.import('ArgumentParser')

let s:registry = {}

function! gista#command#is_registered(name) abort
  return index(keys(s:registry), a:name) != -1
endfunction
function! gista#command#register(name, command, complete, ...) abort
  try
    call gista#util#validate#key_not_exists(
          \ a:name, s:registry,
          \ 'A command "%value" has already been registered',
          \)
    let s:registry[a:name] = {
          \ 'command': type(a:command) == type('')
          \   ? function(a:command)
          \   : a:command,
          \ 'complete': type(a:complete) == type('')
          \   ? function(a:complete)
          \   : a:complete,
          \}
  catch /^vim-gista: ValidationError/
    call gista#util#prompt#error(v:exception)
  endtry
endfunction
function! gista#command#unregister(name) abort
  try
    call gista#util#validate#key_exists(
          \ a:name, s:registry,
          \ 'A command "%value" has not been registered yet',
          \)
    unlet s:registry[a:name]
  catch /^vim-gista: ValidationError/
    call gista#util#prompt#error(v:exception)
  endtry
endfunction

function! s:get_parser() abort
  if !exists('s:parser') || g:gista#develop
    let s:parser = s:A.new({
          \ 'name': 'Gista',
          \ 'description': [
          \   'A gist manipulation command',
          \ ],
          \})
    call s:parser.add_argument(
          \ 'action', [
          \   'An action name of vim-gista. The following actions are available:',
          \   '- login  : Login to a specified username of a specified API',
          \   '- logout : Logout from a specified API',
          \   '- get    : Get and open a gist',
          \   '- list   : Fetch and display a list of gist entries',
          \ ], {
          \   'terminal': 1,
          \   'complete': function('s:complete_action'),
          \})
    call s:parser.add_argument(
          \ '--apiname', [
          \   'A temporary API name used only in this command execution',
          \ ], {
          \   'complete': function('gista#api#complete_apiname'),
          \})
    call s:parser.add_argument(
          \ '--username', [
          \   'Temporary login as USERNAME only in this command execution',
          \ ], {
          \   'complete': function('gista#api#complete_username'),
          \   'conflicts': ['anonymous'],
          \})
    call s:parser.add_argument(
          \ '--anonymous', [
          \   'Temporary logout only in this command execution',
          \ ], {
          \   'conflicts': ['username'],
          \})
    function! s:parser.hooks.pre_validate(options) abort
      if !has_key(a:options, 'apiname')
        let a:options.apiname = gista#meta#get_apiname()
      endif
    endfunction
    function! s:parser.hooks.pre_complete(options) abort
      if !has_key(a:options, 'apiname')
        let a:options.apiname = gista#meta#get_apiname()
      endif
    endfunction
    function! s:parser.hooks.post_validate(options) abort
      if get(a:options, 'anonymous')
        let a:options.username = ''
        unlet a:options.anonymous
      endif
    endfunction
    call s:parser.hooks.validate()
  endif
  return s:parser
endfunction
function! s:complete_action(arglead, cmdline, cursorpos, ...) abort
  let available_commands = ['login', 'logout'] + keys(s:registry)
  return filter(available_commands, 'v:val =~# "^" . a:arglead')
endfunction
function! gista#command#command(...) abort
  let parser  = s:get_parser()
  let options = call(parser.parse, a:000, parser)
  if !empty(options)
    let bang  = a:1
    let range = a:2
    let args  = join(options.__unknown__)
    let name  = get(options, 'action', '')
    if name ==# 'login'
      call gista#command#login#command(
            \ bang, range, args,
            \ s:D.pick(options, ['apiname', 'username']),
            \)
    elseif name ==# 'logout'
      call gista#command#logout#command(
            \ bang, range, args,
            \ s:D.pick(options, ['apiname']),
            \)
    elseif gista#command#is_registered(name)
      let session = gista#api#session(options)
      try
        call session.enter()
        " perform a specified command
        call s:registry[name].command(bang, range, args)
      finally
        call session.exit()
      endtry
    else
      echo parser.help()
    endif
  endif
endfunction
function! gista#command#complete(arglead, cmdline, cursorpos, ...) abort
  let bang    = a:cmdline =~# '\v^Gista!'
  let cmdline = substitute(a:cmdline, '\C^Gista!\?\s', '', '')
  let cmdline = substitute(cmdline, '[^ ]\+$', '', '')
  let parser  = s:get_parser()
  let options = call(parser.parse, [bang, [0, 0], cmdline], parser)
  if !empty(options)
    let name = get(options, 'action', '')
    if name ==# 'login'
      return gista#command#login#complete(
            \ a:arglead, cmdline, a:cursorpos,
            \ s:D.pick(options, ['apiname', 'username']),
            \)
    elseif name ==# 'logout'
      return gista#command#logout#complete(
            \ a:arglead, cmdline, a:cursorpos,
            \ s:D.pick(options, ['apiname']),
            \)
    elseif gista#command#is_registered(name)
      let session = gista#api#session(options)
      try
        call session.enter()
        " perform a specified command
        return s:registry[name].complete(a:arglead, cmdline, a:cursorpos)
      finally
        call session.exit()
      endtry
    endif
  endif
  return parser.complete(a:arglead, a:cmdline, a:cursorpos)
endfunction

" Register commands
call gista#command#register('open',
      \ 'gista#command#open#command',
      \ 'gista#command#open#complete',
      \)
call gista#command#register('json',
      \ 'gista#command#json#command',
      \ 'gista#command#json#complete',
      \)
call gista#command#register('browse',
      \ 'gista#command#browse#command',
      \ 'gista#command#browse#complete',
      \)
call gista#command#register('list',
      \ 'gista#command#list#command',
      \ 'gista#command#list#complete',
      \)
call gista#command#register('post',
      \ 'gista#command#post#command',
      \ 'gista#command#post#complete',
      \)
call gista#command#register('patch',
      \ 'gista#command#patch#command',
      \ 'gista#command#patch#complete',
      \)
call gista#command#register('star',
      \ 'gista#command#star#command',
      \ 'gista#command#star#complete',
      \)
call gista#command#register('unstar',
      \ 'gista#command#unstar#command',
      \ 'gista#command#unstar#complete',
      \)
call gista#command#register('fork',
      \ 'gista#command#fork#command',
      \ 'gista#command#fork#complete',
      \)

let &cpo = s:save_cpo
unlet! s:save_cpo
" vim:set et ts=2 sts=2 sw=2 tw=0 fdm=marker:
