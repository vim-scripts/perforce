" Vim syntax file
" Language:	Perforce SCM
" Author: Hari Krishna <hari_vim@yahoo.com>
" Last Modified: 16-Mar-2002 @ 20:33
" Created:       16-Mar-2002 @ 20:33
" Version: 0.0.1
" TODO:
"   perforceOpenType is not working.
"   perforceDepotView is not working.
"   matching the listings should be more detailed (date, client etc.). 
"   Syntax for help window. 
"   The names shouldn't be String, it is same as constant. 
"   Don't know how the depot list looks like. 

" For version 5.x: Clear all syntax items
" For version 6.x: Quit when a syntax file was already loaded
if version < 600
  syntax clear
elseif exists("b:current_syntax")
  finish
endif

syn match perforceSpecline "^\S\+:.*$" contains=perforceSpecKey
syn match perforceChangeItem "^Change \d\+ on \d\+/\d\+/\d\+ .*$" contains=perforceChangeNumber,perforceDate,perforceChangeUser,perforceChangeClient
syn match perforceClientItem "^Client \S\+ \d\+/\d\+/\d\+ .*$" contains=perforceClientName,perforceDate,perforceClientRoot
syn match perforceLabelItem "^Label \S\+ \d\+/\d\+/\d\+ .*$" contains=perforceLabelName,perforceDate,perforceLabelUser
syn match perforceBranchItem "^Branch \S\+ \d\+/\d\+/\d\+ .*$" contains=perforceBranchName,perforceDate
syn match perforceDepotItem "^Depot \S\+ \d\+/\d\+/\d\+ .*$" contains=perforceDepotName
syn match perforceUserItem "^\S\+ <\S\+@\S\+> ([^)]\+) .*$" contains=perforceUserName,perforceDate
syn match perforceJobItem "^\S\+ on \d\+/\d\+/\d\+ by .*$" contains=perforceJobName,perforceDate,perforceJobClientName
syn match perforceFixItem "^\S\+ fixed by change \d\+.*$" contains=perforceFixJobName,perforceFixChangeNumber,perforceDate,perforceChangeUser,perforceChangeClient
syn match perforceDepotFileLine "^\s\+\f\+.*$" contains=perforceDepotFileSpec,perforceOpenType
syn match perforceDepotFileSpec "//depot/\f\+#\d\+" contains=perforceDepotFile,perforceVerSep,perforceVersion contained
syn match perforceChangeFilesLine "^\t//depot/\f\+\t\+#.*$" contains=perforceDepotFile,perforceChangeSubmitType
syn match perforceComment "^\s*#.*$"
syn match perforceViewLine "^\t-\?//depot/\f\+\s\+//\f\+.*$" contains=perforceViewExclude,perforceDepotView,perforceClientView

syn match perforceSpecKey "^\S\+\ze:" contained
syn match perforceChangeNumber "Change \zs\d\+\ze " contained
syn match perforceDate "\d\+/\d\+/\d\+" contained
syn match perforceChangeUser " by \zs\S\+\ze@" contained
syn match perforceChangeClient "@\zs\S\+\ze" contained
syn match perforceClientName "Client \zs\S\+\ze " contained
syn match perforceClientRoot "root \zs\f\+\ze " contained
syn match perforceUserName "^\S\+\ze <" contained
syn match perforceLabelName "Label \zs\S\+\ze " contained
syn match perforceLabelUser "'Created by \zs\S\+\ze." contained
syn match perforceBranchName "Branch \zs\S\+\ze " contained
syn match perforceDepotName "Depot \zs\S\+\ze " contained
syn match perforceJobName "^\S\+\ze on" contained
syn match perforceFixJobName "^\S\+\ze fixed by" contained
syn match perforceFixChangeNumber "by change \zs\d\+\ze on" contained
syn match perforceJobClientName " by \zs\S\+\ze " contained
syn match perforceOpenType "#\d\+ - \zs\S\+\ze " contained
syn match perforceDepotFile "\f\+\ze\s\+#" contained
syn match perforceVerSep "#" contained
syn match perforceVersion "\d\+" contained
syn match perforceChangeSubmitType "# \zs\w\+$" contained
syn match perforceViewExclude "^\t\zs-\ze" contained
syn match perforceDepotView "^\t-\?\zs//depot/\f\+" contained
syn match perforceClientView "\s\+\zs//\f\+$" contained
syn keyword perforceCommands contained add admin branch branches change changes client
syn keyword perforceCommands contained clients counter counters delete depot
syn keyword perforceCommands contained dirs edit filelog files fix fixes
syn keyword perforceCommands contained help info integrate integrated job
syn keyword perforceCommands contained labelsync lock logger obliterate
syn keyword perforceCommands contained reopen resolve resolved revert review
syn keyword perforceCommands contained triggers typemap unlock user users
syn keyword perforceCommands contained verify where reviews set submit sync
syn keyword perforceCommands contained opened passwd print protect rename
syn keyword perforceCommands contained jobs jobspec label labels flush fstat
syn keyword perforceCommands contained group groups have depots describe diff
syn keyword perforceCommands contained diff2

hi link perforceLabelUser         perforceUser
hi link perforceChangeUser        perforceUser
hi link perforceUserName          perforceUser
hi link perforceChangeClient      perforceClient
hi link perforceClientName        perforceClient
hi link perforceJobClientName     perforceClient
hi link perforceLabelName         perforceName
hi link perforceBranchName        perforceName
hi link perforceDepotName         perforceName
hi link perforceJobName           perforceName
hi link perforceFixJobName        perforceName
hi link perforceChangeNumber      perforceName
hi link perforceFixChangeNumber   perforceName

hi def link perforceSpecKey           Statement
hi def link perforceComment           Comment
hi def link perforceDate              Constant
hi def link perforceUser              String
hi def link perforceClient            String
hi def link perforceClientRoot        Directory
hi def link perforceName              String
hi def link perforceOpenType          Type
hi def link perforceDepotFile         Directory
hi def link perforceVerSep            Operator
hi def link perforceVersion           Constant
hi def link perforceChangeSubmitType  Type
hi def link perforceViewExclude       Special
hi def link perforceDepotView         Directory
hi def link perforceClientView        Directory
