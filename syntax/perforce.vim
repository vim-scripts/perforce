" Vim syntax file
" Language:	Perforce SCM
" Author: Hari Krishna <hari_vim@yahoo.com>
" Last Modified: 12-Apr-2002 @ 18:50
" Created:       16-Mar-2002 @ 20:33
" Version: 0.0.7
"
" Usage:
"   Place this file in syntax director under one of the vim runtime
"     directories. This is automatically be used by the perforce plugin for
"     all the perforce windows. If you want to specifically enable perforce
"     syntax highlighting for any vim buffers, just run the command:
"
"	set ft=perforce
"
"     at command prompt.
"   You can also change the syntax coloring by inserting the following lines
"   in your .vimrc:
"
"	hi link perforceSpecKey           <your_preferred_highlighting_group>
"	hi link perforceComment           <your_preferred_highlighting_group>
"	hi link perforceDate              <your_preferred_highlighting_group>
"	hi link perforceCommands          <your_preferred_highlighting_group>
"	hi link perforceHelpKeys          <your_preferred_highlighting_group>
"	hi link perforceClientRoot        <your_preferred_highlighting_group>
"	hi link perforceKeyName           <your_preferred_highlighting_group>
"	hi link perforceDepotFile         <your_preferred_highlighting_group>
"	hi link perforceLocalFile         <your_preferred_highlighting_group>
"	hi link perforceVerSep            <your_preferred_highlighting_group>
"	hi link perforceVersion           <your_preferred_highlighting_group>
"	hi link perforceSubmitType	  <your_preferred_highlighting_group>
"	hi link perforceViewExclude       <your_preferred_highlighting_group>
"	hi link perforceDepotView         <your_preferred_highlighting_group>
"	hi link perforceClientView        <your_preferred_highlighting_group>
"
"     Replace the <your_preferred_highlighting_group> with whatever group name
"     you want, such as, Comment, Special etc.	
"
" TODO:
"   Don't know how the depot list looks like. 
"   Don't know all the cases of resolve lines, so it may not be complete.
"   Syntax definitions for resolve window. 

" For version 5.x: Clear all syntax items
" For version 6.x: Quit when a syntax file was already loaded
if version < 600
  syntax clear
elseif exists("b:current_syntax")
  finish
endif

" Generic interactive command:
syn match perforceSpecline "^\S\+:.*$" contains=perforceSpecKey
syn match perforceSpecKey "^\S\+\ze:" contained
syn match perforceViewLine "^\t-\?//[^/[:space:]]\+/\f\+ //[^/[:space:]]\+/\f\+.*$" contains=perforceViewExclude,perforceDepotView,perforceClientView
syn match perforceViewExclude "^\t\zs-" contained
syn match perforceDepotView "//[^/[:space:]]\+/\f\+" contained
syn match perforceClientView " \zs//\f\+$" contained


" changes
syn match perforceChangeItem "^Change \d\+ on \d\+/\d\+/\d\+ .*$" contains=perforceChangeNumber,perforceDate,perforceUserAtClient
syn match perforceChangeNumber "Change \zs\d\+\ze " contained


" clients
syn match perforceClientItem "^Client \S\+ \d\+/\d\+/\d\+ .*$" contains=perforceClientName,perforceDate,perforceClientRoot
syn match perforceClientName "Client \zs\S\+\ze " contained
syn match perforceClientRoot "root \zs\f\+\ze " contained


" labels
syn match perforceLabelItem "^Label \S\+ \d\+/\d\+/\d\+ .*$" contains=perforceLabelName,perforceDate,perforceUserName
syn match perforceLabelName "Label \zs\S\+\ze " contained
syn match perforceUserName "'Created by \zs\S\+\ze." contained


" branches
syn match perforceBranchItem "^Branch \S\+ \d\+/\d\+/\d\+ .*$" contains=perforceBranchName,perforceDate
syn match perforceBranchName "Branch \zs\S\+\ze " contained


" depots ???
syn match perforceDepotItem "^Depot \S\+ \d\+/\d\+/\d\+ .*$" contains=perforceDepotName
syn match perforceDepotName "Depot \zs\S\+\ze " contained


" users
syn match perforceUserItem "^\S\+ <\S\+@\S\+> ([^)[:space:]]\+) .*$" contains=perforceUserName,perforceDate
syn match perforceUserName "^\S\+\ze <" contained


" jobs
syn match perforceJobItem "^\S\+ on \d\+/\d\+/\d\+ by .*$" contains=perforceJobName,perforceDate,perforceJobClientName
syn match perforceJobName "^\S\+\ze on" contained
syn match perforceClientName " by \zs[^@[:space:]]\+\ze " contained


" fixes
syn match perforceFixItem "^\S\+ fixed by change \d\+.*$" contains=perforceJobName,perforceChangeNumber,perforceDate,perforceUserAtClient
syn match perforceJobName "^\S\+\ze fixed " contained
syn match perforceChangeNumber "by change \zs\d\+\ze " contained


" opened, files, have, submit etc.
syn match perforceFilelistLine "^//[^/[:space:]]\+/.*#\d\+ - .*$" contains=perforceDepotFileSpec,perforceLocalFile
syn match perforceFilelistLine "^\t\?//[^/[:space:]]\+/.*#\d\+ - .*$" contains=perforceDepotFileSpec,perforceSubmitType,perforceChangeNumber " submit.
syn match perforceFilelistLine "^\t//[^/[:space:]]\+/\f\+\t\+#.*$" contains=perforceDepotFile,perforceSubmitType " change.
syn match perforceChangeNumber " change \zs\d\+\ze " contained
syn match perforceSubmitType " - \zs\S\+\ze\( default\)\? change " contained
syn match perforceSubmitType "# \zs\S\+$" contained " change.
syn match perforceLocalFile " - \zs\f\+$"


" filelog
syn match perforceFilelogLine "^\.\.\. #\d\+ change \d\+ .*$" contains=perforceVerStr,perforceChangeNumber,perforceSubmitType,perforceDate,perforceUserAtClient
syn match perforceSubmitType " \zs\S\+\ze on " contained


" resolve
" What else can be there other than "merging" and "copy from" ?
syn match perforceResolveLine "^\f\+ - \(merging\|copy from\) \f\+.*$" contains=perforceResolveTargetFile,perforceDepotFileSpec
syn match perforceResolveLine "^Diff chunks:.*$" contains=perforceNumChunks,perforceConflicting
" Strictly speaking, we should be able to distinguish between local and depot
"   file names here, but I don't know how.
syn match perforceResolveTargetFile "^\f\+" contained
syn match perforceNumChunks "\d\+" contained
syn match perforceConflicting "[1-9]\d* conflicting" contained


" help.
syn region perforceHelp start=" \{4}\w\+ -- " end="\%$" contains=perforceCommands,perforceHelpKeys
syn region perforceHelp start=" \{4}Most common Perforce client commands:" end="\%$" contains=perforceCommands,perforceHelpKeys
syn region perforceHelp start=" \{4}Perforce client commands:" end="\%$" contains=perforceCommands,perforceHelpKeys
syn region perforceHelp start=" \{4}Environment variables used by Perforce:" end="\%$" contains=perforceCommands,perforceHelpKeys
syn region perforceHelp start=" \{4}File types supported by Perforce:" end="\%$" contains=perforceCommands,perforceHelpKeys
syn region perforceHelp start=" \{3,4}Perforce job views:" end="\%$" contains=perforceCommands,perforceHelpKeys
syn region perforceHelp start=" \{4}Specifying file revisions and revision ranges:" end="\%$" contains=perforceHelpVoid,perforceCommands,perforceHelpKeys
syn region perforceHelp start=" \{4}Perforce client usage:" end="\%$" contains=perforceCommands,perforceHelpKeys
syn region perforceHelp start=" \{4}Perforce views:" end="\%$" contains=perforceCommands,perforceHelpKeys
syn keyword perforceHelpKeys contained simple commands environment filetypes
syn keyword perforceHelpKeys contained jobview revisions usage views
" Don't highlight these.
syn match perforceHelpVoid "@change" contained
syn match perforceHelpVoid "@client" contained
syn match perforceHelpVoid "@label" contained
syn match perforceHelpVoid "#have" contained
" Needed for help to window to sync correctly.
syn sync lines=100


" Common.
syn match perforceUserAtClient " by [^@[:space:]]\+@\S\+" contains=perforceUserName,perforceClientName contained
syn match perforceClientName "@\zs\S\+\ze " contained
syn match perforceUserName " by \zs[^@[:space:]]\+" contained
syn match perforceDepotFileSpec "//[^/[:space:]]\+/\f\+\(#\d\+\)\?" contains=perforceDepotFile,perforceVerStr contained
syn match perforceDepotFile "//[^#[:space:]]\+" contained
syn match perforceComment "^\s*#.*$"
syn match perforceDate "\d\+/\d\+/\d\+" contained
syn match perforceVerStr "#\d\+" contains=perforceVerSep,perforceVersion
syn match perforceVerSep "#" contained
syn match perforceVersion "\d\+" contained
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

hi link perforceLabelName		perforceKeyName
hi link perforceBranchName		perforceKeyName
hi link perforceDepotName		perforceKeyName
hi link perforceJobName			perforceKeyName
hi link perforceClientName		perforceKeyName
hi link perforceUserName		perforceKeyName
hi link perforceChangeNumber		perforceKeyName
hi link perforceResolveTargetFile	perforceDepotFile

hi def link perforceSpecKey           Label
hi def link perforceComment           Comment
hi def link perforceNumChunks         Constant
hi def link perforceConflicting       Error
hi def link perforceDate              Constant
hi def link perforceCommands          Identifier
hi def link perforceHelpKeys          Identifier
hi def link perforceClientRoot        Directory
hi def link perforceKeyName           Special
hi def link perforceDepotFile         Directory
hi def link perforceLocalFile         Directory
hi def link perforceVerSep            Operator
hi def link perforceVersion           Constant
hi def link perforceSubmitType	      Type
hi def link perforceViewExclude       WarningMsg
hi def link perforceDepotView         Directory
hi def link perforceClientView        Directory

let b:current_syntax='perforce'
