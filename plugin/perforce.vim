" perforce.vim: Interface with perforce SCM through p4.
" Author: Hari Krishna <hari_vim at yahoo dot com>
" Last Change: 21-Oct-2003 @ 19:37
" Created:     Sometime before 20-Apr-2001
" Requires:    Vim-6.2, genutils.vim(1.9), multvals.vim(3.3)
" Version:     2.0.39
" Licence: This program is free software; you can redistribute it and/or
"          modify it under the terms of the GNU General Public License.
"          See http://www.gnu.org/copyleft/gpl.txt 
" Acknowledgements:
"     Tom Slee (tslee at ianywhere dot com) for his idea of creating a status
"	bar with the p4 fstat information (see
"	  http://www.vim.org/script.php?script_id=167).
" Download From:
"     http://www.vim.org//script.php?script_id=240
" Usage:
"     For detailed help, see ":help perforce" or doc/perforce.txt. 
"
" Summary Of Features:
"   See help for details and most up to date information.
"
"   Command Line:
"     Short commands for most used perforce operations:
"
"       PE (edit), PR (revert), PA (add), PD (diff), PD2 (diff2),
"       PP (print), PG (get), PO (opened), PH (help),
"
"     Long commands each corresponding to one of the p4 operations:
"
"       PAdd, PBranch, PBranches, PChange, PChanges, PClient, PClients,
"       PDelete, PDepot, PDepots, PDescribe, PDiff, PDiff2, PEdit, PFiles,
"       PFstat, PGet, PGroup, PGroups, PHave, PHelp, PIntegrate, PJob, PJobs,
"       PJobspec, PLabel, PLabels, PLabelsync, PLock, POpened, PPrint,
"       PReopen, PResolve, PRevert, PSubmit, PSync, PUnlock, PUser, PUsers,
"       PWhere
"
"     Special commands which don't have an equivalent p4 command:
"
"       E (command to open a file from a different codeline),
"       PRefreshActivePane (to refresh the current p4 window),
"       PRefreshFileStatus (to refresh the current file status),
"       PFSettings (to display and change the values of different settings).
"
"   Commandline Mode Maps:
"       <C-X><C-P> - to insert the current file from a different codeline.
"	<C-X><C-I> - to get the current list item on the command line (in the
"		     relevant p4 windows only)
"
"   Normal Mode Maps:
"       O    - open/edit current item (all list views),
"       <2-LeftMouse> or
"       <CR> - describe current item (all list views).
"       D    - delete current item (in file list),
"              diff current file (in filelog).
"       S    - sync to the current version (in filelog) .
"       o    - list opened files in the current change list(in changes list).
"       C    - describe current change list (in filelog or changes list).
"              open current change (in file list).
"       P    - print properties of the current file (in file list).
"       R    - revert current file (in file list).
"       S    - submit current change (in changes list).
"
"   Menus:
"       "Perforce" menu group in the main and Popup menus if enabled.
"
"   Settings:
"       p4CmdPath, p4Port, p4User, p4Client, p4Password, p4DefaultOptions,
"       p4ClientRoot, p4EnableRuler, p4RulerWidth, p4EnableActiveStatus,
"       p4ASIgnoreDefPattern, p4ASIgnoreUsrPattern, p4OptimizeActiveStatus,
"       p4UseGUIDialogs, p4PromptToCheckout, p4DefaultListSize,
"       p4DefaultDiffOptions, p4EnableMenu, p4UseExpandedMenu,
"       p4EnablePopupMenu, p4UseExpandedPopupMenu, p4Presets,
"       p4MaxLinesInDialog, p4CheckOutDefault, p4SortSettings, p4TempDir,
"       p4SplitCommand, p4UseVimDiff2
"
"
" TODO: {{{
"   - If there is a call to confirm() when it is in silent!, the message
"     doesn't show up.
"   - After pressing A to start autocheckout the cursor is wrongly placed.
"
"   - I can have another scriptOrigin type that allows passing the
"     argumentString as it is from the handlers to PFIF().
"   - Verify that the buffers/autocommands are not leaking.
" TODO }}}
"
" BEGIN NOTES {{{
"   - Now that we increase the level of escaping in the ParseOptions(), we
"     need to be careful in reparsing the options (by not using
"     scriptOrigin=2). When you CreateArgString() using these escaped
"     arguments as if they were typed in by user, they get sent to p4 as they
"     are, with incorrect number of back-slashes.
"   - When issuing sub-commands, we should remember to use the s:p4Options
"     that was passed to the main command, or the user will see incorrect
"     behavior or at the worst, errors.
"   - The p4FullCmd now can have double-quotes surrounding each of the
"     individual arguments, if the shell is cmd.exe or command.com, so while
"     manipulating it directly, we need to use "\?.
"   - With the new mode of scriptOrigin=2, the changes done to the s:p4*
"     variables will not get reflected in the s:p4WinName, unless there is
"     some other relevant processing done in PFIF.
"   - With the new mode of scriptOrigin=2, there is no reason to use
"     scriptOrigin=1 in most of the calls from handlers.
"   - The s:PFSetupBufAutoCommand and its cousines expect the buffer name to
"     be plain with no escaping, as they do their own escaping.
"   - Wherever we normally expect a depot name, we should use the s:p4Depot
"     instead of hardcoded 'depot'. We should also consider the client name
"     here.
"   - If checktime is called from inside an autocommand execution (which is
"     the case for auto checkout), the checktime may be delayed until the
"     execution is over. So we can't reset s:currentCommand immediately. I am
"     currently creating a CursorHold autocommand for this.
"   - We need to pass special characters such as <space>, *, ?, [, (, &, |, ', $
"     and " to p4 without getting interpreted by the shell. We may have to use
"     appropriate quotes around the characters when the shell treats them
"     specially. Windows+native is the least bothersome of all as it doesn't
"     treat most of the characters specially and the arguments can be
"     sorrounded in double-quotes and embedded double-quotes can be easily
"     passed in by just doubling them.
"   - I am aware of the following unique ways in which external commands are
"     executed (not sure if this is same for all of the variations possible: 
"     ":[{range}][read|write]!cmd | filter" and "system()"):
"     For :! command 
"	On Windoze+native:
"     	  cmd /c <command>
"     	On Windoze+sh:
"     	  sh -c "<command>"
"     	On Unix+sh:
"	  sh -c (<command>) 
"   - By the time we parse arguments, we protect all the back-slashes, which
"     means that we would never see a single-slash.
"   - Using back-slashes on Cygwin vim is unique and causes E303. This is
"     because it thinks it is on UNIX where it is not a special character, but
"     underlying Windows obviously treats it special and so it bails out.
"   - Using back-slashes on Windows+sh also seems to be different. Somewhere in
"     the execution line (most probably the path from CreateProcess() to sh,
"     as it doesn't happen in all other type sof interfaces) consumes one
"     level of bach-slashes. If it is even number it becomes half, and if it
"     is odd then the last unparied back-slash is left as it is.
"   - Some test cases for special character handling:
"     - PF fstat a\b
"     - PF fstat a\ b
"     - PF fstat a&b
"     - PF fstat a\&b
"     - PF fstat a\#b
"     - PF fstat a\|b
"   - Careful using PFIF(1) from within script, as it doesn't redirect the
"     call to the corresponding handler (if any).
" END NOTES }}} 

if exists("loaded_perforce")
  finish
endif
if v:version < 602
  echomsg "You need Vim 6.2 to run this version of perforce.vim."
  finish
endif
let loaded_perforce=1


" We need these scripts at the time of initialization itself.
if !exists("loaded_multvals")
  runtime plugin/multvals.vim
endif
if !exists("loaded_genutils")
  runtime plugin/genutils.vim
endif

" Make sure line-continuations won't cause any problem. This will be restored
"   at the end
let s:save_cpo = &cpo
set cpo&vim


" Call this any time to reconfigure the environment. This re-performs the same
"   initializations that the script does during the vim startup, without
"   loosing what is already configured.
command! -nargs=0 PFInitialize :call <SID>Initialize()

""" BEGIN: Initializations {{{

" Determine the script id.
function! s:MyScriptId()
  map <SID>xx <SID>xx
  let s:sid = maparg("<SID>xx")
  unmap <SID>xx
  return substitute(s:sid, "xx$", "", "")
endfunction
let s:myScriptId = s:MyScriptId()
delfunction s:MyScriptId " This is not needed anymore.

function! s:Initialize() " {{{

" User Options {{{

if !exists("s:p4CmdPath") " The first-time only, initialize with defaults.
  let s:p4CmdPath = "p4"
  let s:clientRoot = ""
  let s:defaultListSize='100'
  let s:defaultDiffOptions=''
  let s:p4Client = $P4CLIENT
  if exists("$P4USER") && $P4USER != ''
    let s:p4User = $P4USER
  elseif OnMS() && exists("$USERNAME")
    let s:p4User = $USERNAME
  elseif exists("$LOGNAME")
    let s:p4User = $LOGNAME
  elseif exists("$USERNAME") " Happens if you are on cygwin too.
    let s:p4User = $USERNAME
  else
    let s:p4User = ''
  endif
  let s:p4Port = $P4PORT
  let s:p4Password = $P4PASSWD
  let s:p4Depot = 'depot'
  let s:p4Presets = ""
  let s:defaultOptions = ""
  let s:useGUIDialogs = 0
  let s:promptToCheckout = 1
  let s:maxLinesInDialog = 1
  let s:activeStatusEnabled = 1
  let s:ignoreDefPattern = '\c\%(\<t\%(e\)\?mp\/.*\|^.*\.tmp$\|^.*\.log$\|^.*\.diff\?$\|^.*\.out$\|^.*\.buf$\|^.*\.bak$\)\C'
  let s:ignoreUsrPattern = ''
  let s:optimizeActiveStatus = 1
  let s:rulerEnabled = 1
  let s:rulerWidth = 25
  let s:menuEnabled = 0
  let s:popupMenuEnabled = 0
  let s:useExpandedMenu = 1
  let s:useExpandedPopupMenu = 0
  let s:checkOutDefault = 2
  let s:sortSettings = 1
  " Probably safer than reading $TEMP.
  let s:tempDir = substitute(tempname(), '[/\\][^/\\]\+$', '', '')
  let s:splitCommand = "split"
  let s:enableFileChangedShell = 1
  let s:useVimDiff2 = 0
  let s:p4HideOnBufHidden = 0
  let s:autoread = 1
  if OnMS()
    let s:fileLauncher = 'start rundll32 url.dll,FileProtocolHandler'
  else
    let s:fileLauncher = ''
  endif
endif

function! s:CondDefSetting(globalName, settingName, ...)
  let assgnmnt = (a:0 != 0) ? a:1 : a:globalName
  if exists(a:globalName)
    exec "let" a:settingName "=" assgnmnt
    exec "unlet" a:globalName
  endif
endfunction
 
call s:CondDefSetting('g:p4CmdPath', 's:p4CmdPath')
call s:CondDefSetting('g:p4ClientRoot', 's:clientRoot', 'CleanupFileName(g:p4ClientRoot)')
call s:CondDefSetting('g:p4DefaultListSize', 's:defaultListSize')
call s:CondDefSetting('g:p4DefaultDiffOptions', 's:defaultDiffOptions')
call s:CondDefSetting('g:p4Client', 's:p4Client')
call s:CondDefSetting('g:p4User', 's:p4User')
call s:CondDefSetting('g:p4Port', 's:p4Port')
call s:CondDefSetting('g:p4Password', 's:p4Password')
if exists('g:p4Depot') && g:p4Depot != ''
  call s:CondDefSetting('g:p4Depot', 's:p4Depot')
endif
call s:CondDefSetting('g:p4Presets', 's:p4Presets')
call s:CondDefSetting('g:p4DefaultOptions', 's:defaultOptions')
call s:CondDefSetting('g:p4UseGUIDialogs', 's:useGUIDialogs')
call s:CondDefSetting('g:p4PromptToCheckout', 's:promptToCheckout')
call s:CondDefSetting('g:p4MaxLinesInDialog', 's:maxLinesInDialog')
call s:CondDefSetting('g:p4EnableActiveStatus', 's:activeStatusEnabled')
call s:CondDefSetting('g:p4ASIgnoreDefPattern', 's:ignoreDefPattern')
call s:CondDefSetting('g:p4ASIgnoreUsrPattern', 's:ignoreUsrPattern')
call s:CondDefSetting('g:p4OptimizeActiveStatus', 's:optimizeActiveStatus')
call s:CondDefSetting('g:p4EnableRuler', 's:rulerEnabled')
call s:CondDefSetting('g:p4RulerWidth', 's:rulerWidth')
call s:CondDefSetting('g:p4EnableMenu', 's:menuEnabled')
call s:CondDefSetting('g:p4EnablePopupMenu', 's:popupMenuEnabled')
call s:CondDefSetting('g:p4UseExpandedMenu', 's:useExpandedMenu')
call s:CondDefSetting('g:p4UseExpandedPopupMenu', 's:useExpandedPopupMenu')
call s:CondDefSetting('g:p4CheckOutDefault', 's:checkOutDefault')
call s:CondDefSetting('g:p4SortSettings', 's:sortSettings')
call s:CondDefSetting('g:p4TempDir', 's:tempDir',
      \ 'isdirectory(g:p4TempDir) ? g:p4TempDir : s:tempDir')
call s:CondDefSetting('g:p4SplitCommand', 's:splitCommand')
call s:CondDefSetting('g:p4EnableFileChangedShell', 's:enableFileChangedShell')
call s:CondDefSetting('g:p4UseVimDiff2', 's:useVimDiff2')
call s:CondDefSetting('g:p4HideOnBufHidden', 's:p4HideOnBufHidden')
call s:CondDefSetting('g:p4Autoread', 's:autoread')
call s:CondDefSetting('g:p4FileLauncher', 's:fileLauncher')
delfunction s:CondDefSetting

" This is a one time initialization. Assume the user already has his preferred
"   rulerformat set (he is anyway going to do it through his .vimrc file which
"   should already be sourced).
if s:rulerEnabled
  " Take care of rerunning this code, as the reinitialization can happen any
  "   time.
  if !exists("s:orgRulerFormat")
    let s:orgRulerFormat = &rulerformat
  else
    let &rulerformat = s:orgRulerFormat
  endif

  if &rulerformat != ""
    if match(&rulerformat, '^%\d\+') == 0
      let orgWidth = substitute(&rulerformat, '^%\(\d\+\)(.*$',
	    \ '\1', '')
      let orgRuler = substitute(&rulerformat, '^%\d\+(\(.*\)%)$', '\1', '')
    else
      let orgWidth = strlen(&rulerformat) " Approximate.
      let orgRuler = &rulerformat
    endif
  else
    let orgWidth = 20
    let orgRuler = '%l,%c%V%=%5(%p%%%)'
  endif
  let &rulerformat = '%' . (orgWidth + s:rulerWidth) .  '(%{' . s:myScriptId .
	\ 'P4RulerStatus()}%=' . orgRuler . '%)'
else
  if exists("s:orgRulerFormat")
    let &rulerformat = s:orgRulerFormat
  else
    set rulerformat&
  endif
endif


if s:enableFileChangedShell
  call DefFCShellInstall()
else
  call DefFCShellUninstall()
endif

aug P4ClientRoot
  au!
  if s:clientRoot == ""
    if s:activeStatusEnabled
      au VimEnter * call <SID>GetClientInfo() | au! P4ClientRoot
    else
      let s:clientRoot=fnamemodify(".", ":p")
    endif
  endif
aug END

aug P4Active
  au!
  if s:activeStatusEnabled
    au BufRead * call <SID>GetFileStatus(expand('<abuf>') + 0, 0)
  endif
aug END

" User Options }}}

""" The following are some shortcut commands. Some of them are enhanced such
"""   as the help window or the filelog window.

" Command definitions {{{

command! -nargs=* -complete=file PP :call <SID>printHdlr(0, 0, <f-args>)
command! -nargs=* -complete=file PPrint :call <SID>printHdlr(0, 0, <f-args>)
command! -nargs=* -complete=file PD :call <SID>diffHdlr(0, 0, <f-args>)
command! -nargs=* -complete=file PDiff :call <SID>diffHdlr(0, 0, <f-args>)
command! -nargs=* -complete=file PEdit :call <SID>PFIF(0, 20, "edit", <f-args>)
command! -nargs=* -complete=file PE :call <SID>PFIF(0, 20, "edit", <f-args>)
command! -nargs=* -complete=file PReopen
      \ :call <SID>PFIF(0, 20, "reopen", <f-args>)
command! -nargs=* -complete=file PAdd :call <SID>PFIF(0, 20, "add", <f-args>)
command! -nargs=* -complete=file PA :call <SID>PFIF(0, 20, "add", <f-args>)
command! -nargs=* -complete=file PDelete
      \ :call <SID>PFIF(0, 20, "delete", <f-args>)
command! -nargs=* -complete=file PLock :call <SID>PFIF(0, 20, "lock", <f-args>)
command! -nargs=* -complete=file PUnlock
      \ :call <SID>PFIF(0, 20, "unlock", <f-args>)
command! -nargs=* -complete=file PRevert
      \ :call <SID>PFIF(0, 20, "revert", <f-args>)
command! -nargs=* -complete=file PR :call <SID>PFIF(0, 20, "revert", <f-args>)
command! -nargs=* -complete=file PSync :call <SID>PFIF(0, 20, "sync", <f-args>)
command! -nargs=* -complete=file PG :call <SID>PFIF(0, 20, "get", <f-args>)
command! -nargs=* -complete=file PGet :call <SID>PFIF(0, 20, "get", <f-args>)
command! -nargs=* -complete=file POpened
      \ :call <SID>PFIF(0, 0, "opened", <f-args>)
command! -nargs=* -complete=file PO :call <SID>PFIF(0, 0, "opened", <f-args>)
command! -nargs=* -complete=file PHave :call <SID>PFIF(0, 0, "have", <f-args>)
command! -nargs=* -complete=file PWhere :call <SID>PFIF(0, 0, "where", <f-args>)
command! -nargs=* PDescribe :call <SID>describeHdlr(0, 0, <f-args>)
command! -nargs=* -complete=file PFiles :call <SID>PFIF(0, 0, "files", <f-args>)
command! -nargs=* -complete=file PLabelsync
      \ :call <SID>PFIF(0, 0, "labelsync", <f-args>)
command! -nargs=* -complete=file PFilelog :call <SID>filelogHdlr(0, 0, <f-args>)
command! -nargs=* -complete=file PIntegrate
      \ :call <SID>PFIF(0, 0, "integrate", <f-args>)
command! -nargs=* -complete=file PD2 :call <SID>diff2Hdlr(0, 0, <f-args>)
command! -nargs=* -complete=file PDiff2 :call <SID>diff2Hdlr(0, 0, <f-args>)
command! -nargs=* -complete=file PFstat :call <SID>PFIF(0, 0, "fstat", <f-args>)
command! -nargs=* PH :call <SID>helpHdlr(0, 0, <f-args>)
command! -nargs=* PHelp :call <SID>helpHdlr(0, 0, <f-args>)


""" Some list view commands.
command! -nargs=* -complete=file PChanges :call <SID>changesHdlr(0, 0, <f-args>)
command! -nargs=* PBranches :call <SID>PFIF(0, 0, "branches", <f-args>)
command! -nargs=* -complete=file PLabels :call <SID>labelsHdlr(0, 0, <f-args>)
command! -nargs=* PClients :call <SID>clientsHdlr(0, 0, <f-args>)
command! -nargs=* PUsers :call <SID>PFIF(0, 0, "users", <f-args>)
command! -nargs=* -complete=file PJobs :call <SID>PFIF(0, 0, "jobs", <f-args>)
command! -nargs=* PDepots :call <SID>PFIF(0, 0, "depots", <f-args>)
command! -nargs=* PGroups :call <SID>PFIF(0, 0, "groups", <f-args>)


""" The following support some p4 operations that normally involve some
"""   interaction with the user (they are more than just shortcuts).

command! -nargs=* -complete=file PChange :call <SID>changeHdlr(0, 0, <f-args>)
command! -nargs=* PBranch :call <SID>PFIF(0, 0, "branch", <f-args>)
command! -nargs=* PLabel :call <SID>PFIF(0, 0, "label", <f-args>)
command! -nargs=* PClient :call <SID>PFIF(0, 0, "client", <f-args>)
command! -nargs=* PUser :call <SID>PFIF(0, 0, "user", <f-args>)
command! -nargs=* PJob :call <SID>PFIF(0, 0, "job", <f-args>)
command! -nargs=* PJobspec :call <SID>PFIF(0, 0, "jobspec", <f-args>)
command! -nargs=* PDepot :call <SID>PFIF(0, 0, "depot", <f-args>)
command! -nargs=* PGroup :call <SID>PFIF(0, 0, "group", <f-args>)
command! -nargs=* -complete=file PSubmit :call <SID>submitHdlr(0, 0, <f-args>)
command! -nargs=* -complete=file PResolve :call <SID>resolveHdlr(0, 0, <f-args>)

" Some built-in commands.
command! -nargs=? -complete=file PVDiff :call <SID>PFIF(0, 0, "vdiff", <f-args>)
command! -nargs=? -complete=file PVDiff2
      \ :call <SID>PFIF(0, 0, "vdiff2", <f-args>)

""" Other utility commands.

command! -nargs=* -complete=file E :call <SID>PFOpenAltFile(0, <f-args>)
command! -nargs=* -complete=file ES :call <SID>PFOpenAltFile(2, <f-args>)
command! -nargs=* PSwitch :call <SID>PSwitch(<f-args>)
command! -nargs=* PSwitchPortClientUser :call <SID>SwitchPortClientUser()
command! -nargs=0 PRefreshActivePane :call <SID>PRefreshActivePane()
command! -nargs=0 PRefreshFileStatus :call <SID>GetFileStatus(0, 1)
command! -nargs=0 PToggleCkOut :call <SID>ToggleCheckOutPrompt(1)
command! -nargs=0 PFSettings :call <SID>PFSettings()
command! -nargs=0 PDiffOff :call CleanDiffOptions()
command! -nargs=? PWipeoutBufs :call <SID>WipeoutP4Buffers(<f-args>)
command! -nargs=* -complete=file -range=% PF
      \ <line1>,<line2>call <SID>PFIF(0, -1, <f-args>)
command! -nargs=* -complete=file PFRaw :call <SID>PFRaw(0, <f-args>)
command! -nargs=* -complete=file -range=% PW
      \ :<line1>,<line2>call <SID>PW(0, <f-args>)
command! -nargs=0 PLastMessage :call <SID>LastMessage()
command! -nargs=1 PExecCmd :call <SID>PExecCmd(<q-args>)

" Some generic mappings.
if maparg('<C-X><C-P>', 'c') == ""
  cnoremap <C-X><C-P> <C-R>=<SID>PFOpenAltFile(1)<CR>
endif

" New normal mode mappings.
if (! exists("no_plugin_maps") || ! no_plugin_maps) &&
      \ (! exists("no_perforce_maps") || ! no_execmap_maps)
  nnoremap <silent> <Leader>prap :PRefreshActivePane<cr>
  nnoremap <silent> <Leader>prfs :PRefreshFileStatus<cr>
endif

" Command definitions }}}


" CreateMenu {{{
function! s:CreateMenu(sub, expanded)
  if ! a:expanded
    let fileGroup = '.'
  else
    let fileGroup = '.&File.'
  endif
  exec 'amenu <silent> ' . a:sub . '&Perforce' . fileGroup . '&Add :PA<CR>'
  exec 'amenu <silent> ' . a:sub . '&Perforce' . fileGroup . 'S&ync :PSync<CR>'
  exec 'amenu <silent> ' . a:sub . '&Perforce' . fileGroup . '&Edit :PE<CR>'
  exec 'amenu <silent> ' . a:sub . '&Perforce' . fileGroup . '-Sep1- :'
  exec 'amenu <silent> ' . a:sub . '&Perforce' . fileGroup .
        \ '&Delete :PDelete<CR>'
  exec 'amenu <silent> ' . a:sub . '&Perforce' . fileGroup . '&Revert :PR<CR>'
  exec 'amenu <silent> ' . a:sub . '&Perforce' . fileGroup . '-Sep2- :'
  exec 'amenu <silent> ' . a:sub . '&Perforce' . fileGroup . 'Loc&k :PLock<CR>'
  exec 'amenu <silent> ' . a:sub . '&Perforce' . fileGroup .
        \ 'U&nlock :PUnlock<CR>'
  exec 'amenu <silent> ' . a:sub . '&Perforce' . fileGroup . '-Sep3- :'
  exec 'amenu <silent> ' . a:sub . '&Perforce' . fileGroup . '&Diff :PD<CR>'
  exec 'amenu <silent> ' . a:sub . '&Perforce' . fileGroup . 'Diff&2 :PD2<CR>'
  exec 'amenu <silent> ' . a:sub . '&Perforce' . fileGroup .
        \ 'Revision\ &History :PFilelog<CR>'
  exec 'amenu <silent> ' . a:sub . '&Perforce' . fileGroup . 'Propert&ies ' .
        \ ':PFstat -C<CR>'
  exec 'amenu <silent> ' . a:sub . '&Perforce' . fileGroup . '&Print :PP<CR>'
  exec 'amenu <silent> ' . a:sub . '&Perforce' . fileGroup . '-Sep4- :'
  if a:expanded
    exec 'amenu <silent> ' . a:sub . '&Perforce.&File.' .
          \ 'Resol&ve.Accept\ &Their\ Changes<Tab>resolve\ -at ' .
          \ ':PResolve -at<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&File.' .
          \ 'Resol&ve.Accept\ &Your\ Changes<Tab>resolve\ -ay :PResolve -ay<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&File.' .
          \ 'Resol&ve.&Automatic\ Resolve<Tab>resolve\ -am :PResolve -am<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&File.' .
          \ 'Resol&ve.&Safe\ Resolve<Tab>resolve\ -as :PResolve -as<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&File.' .
          \ 'Resol&ve.&Force\ Resolve<Tab>resolve\ -af :PResolve -af<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&File.' .
          \ 'Resol&ve.S&how\ Integrations<Tab>resolve\ -n :PResolve -n<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&File.-Sep5- :'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&File.Sa&ve\ Current\ Spec ' .
	  \':PExecCmd W<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&File.Save\ and\ &Quit\ ' .
	  \'Current\ Spec :PExecCmd WQ<CR>'
  endif

  if ! a:expanded
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Opened\ Files :PO<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Refresh\ Active\ Pane ' .
          \ ':PRefreshActivePane<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.-Sep6- :'
  else
    exec 'amenu <silent> ' . a:sub .
          \ '&Perforce.&View.&BranchSpecs :PBranches<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&View.&Changelist.' .
          \ '&Pending\ Changelists :PChanges -s pending<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&View.&Changelist.' .
          \ '&Submitted\ Changelists :PChanges -s submitted<CR>'
    exec 'amenu <silent> ' . a:sub .
          \ '&Perforce.&View.Cl&ientSpecs :PClients<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&View.&Jobs :PJobs<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&View.&Labels :PLabels<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&View.&Users :PUsers<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&View.&Depots :PDepots<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&View.&Opened\ Files :PO<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&View.&Refresh\ Active\ Pane ' .
          \ ':PRefreshActivePane<CR>'
  endif

  if a:expanded
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Settings.' .
          \ '&Switch\ Port\ Client\ User :call <SID>SwitchPortClientUser()<CR>'
    let nSets = MvNumberOfElements(s:p4Presets, ',')
    if nSets > 0
      let index = 0
      while index < nSets
        let nextSet = MvElementAt(s:p4Presets, ',', index)
        exec 'amenu <silent> ' . a:sub . '&Perforce.&Settings.&' . index . '\ '
              \ . escape(nextSet, ' .') . ' :PSwitch ' . index . '<CR>'
        let index = index + 1
      endwhile
    endif
  endif

  if ! a:expanded
    exec 'amenu <silent> ' . a:sub .
          \ '&Perforce.New\ &Submission\ Template :PSubmit<CR>'
  else
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Changelist.&New :PChange<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Changelist.' .
          \ '&Edit\ Current\ Changelist :PExecCmd PItemOpen<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Changelist.' .
          \ 'Descri&be\ Current\ Changelist :PExecCmd PItemDescribe<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Changelist.' .
          \ '&Delete\ Current\ Changelist :PExecCmd PItemDelete<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Changelist.' .
          \ 'New\ &Submission\ Template :PSubmit<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Changelist.-Sep- :'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Changelist.' .
          \ 'View\ &Pending\ Changelists :PChanges -s pending<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Changelist.' .
          \ '&View\ Submitted\ Changelists :PChanges -s submitted<CR>'
  endif

  if ! a:expanded
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Branch :PBranch<CR>'
  else
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Branch.&New :PBranch<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Branch.' .
          \ '&Edit\ Current\ BranchSpec :PExecCmd PItemOpen<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Branch.' .
          \ 'Descri&be\ Current\ BranchSpec :PExecCmd PItemDescribe<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Branch.' .
          \ '&Delete\ Current\ BranchSpec :PExecCmd PItemDelete<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Branch.-Sep- :'
    exec 'amenu <silent> ' . a:sub .
          \ '&Perforce.&Branch.&View\ BranchSpecs :PBranches<CR>'
  endif

  if ! a:expanded
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Label :PLabel<CR>'
  else
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Label.&New :PLabel<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Label.' .
          \ '&Edit\ Current\ LabelSpec :PExecCmd PItemOpen<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Label.' .
          \ 'Descri&be\ Current\ LabelSpec :PExecCmd PItemDescribe<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Label.' .
          \ '&Delete\ Current\ LabelSpec :PExecCmd PItemDelete<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Label.-Sep1- :'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Label.' .
          \ '&Sync\ Client\ ' . s:p4Client . '\ to\ Current\ Label ' .
          \ ':PExecCmd PLabelsSyncClient<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Label.' .
          \ '&Replace\ Files\ in\ Current\ Label\ with\ Client\ ' . s:p4Client .
          \ '\ files ' . ':PExecCmd PLabelsSyncLabel<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Label.-Sep2- :'
    exec 'amenu <silent> ' . a:sub .
          \ '&Perforce.&Label.&View\ Labels :PLabels<CR>'
  endif

  if ! a:expanded
    exec 'amenu <silent> ' . a:sub . '&Perforce.Cl&ient :PClient<CR>'
  else
    exec 'amenu <silent> ' . a:sub .
          \ '&Perforce.Cl&ient.&New :PClient +P<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.Cl&ient.' .
          \ '&Edit\ Current\ ClientSpec :PExecCmd PItemOpen<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.Cl&ient.' .
          \ 'Descri&be\ Current\ ClientSpec :PExecCmd PItemDescribe<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.Cl&ient.' .
          \ '&Delete\ Current\ ClientSpec :PExecCmd PItemDelete<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.' .
          \ 'Cl&ient.&Edit\ ' . escape(s:p4Client, ' ') . ' :PClient<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.Cl&ient.-Sep- :'
    exec 'amenu <silent> ' . a:sub . '&Perforce.Cl&ient.&Switch\ to\ Current' .
          \ '\ Client :exec "PSwitch ' . s:p4Port .
          \ ' " . <SID>GetCurrentItem()<CR>'
    exec 'amenu <silent> ' . a:sub .
          \ '&Perforce.Cl&ient.&View\ ClientSpecs :PClients<CR>'
  endif

  if ! a:expanded
    exec 'amenu <silent> ' . a:sub . '&Perforce.&User :PUser<CR>'
  else
    exec 'amenu <silent> ' . a:sub .
          \ '&Perforce.&User.&New :PUser +P<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&User.' .
          \ '&Edit\ Current\ UserSpec :PExecCmd PItemOpen<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&User.' .
          \ 'Descri&be\ Current\ UserSpec :PExecCmd PItemDescribe<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&User.' .
          \ '&Delete\ Current\ UserSpec :PExecCmd PItemDelete<CR>'
    exec 'amenu <silent> ' . a:sub .
          \ '&Perforce.&User.&Edit\ ' . escape(s:p4User, ' ') . ' :PUser<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&User.-Sep- :'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&User.&Switch\ to\ Current' .
          \ '\ User :exec "PSwitch ' . s:p4Port . ' ' . s:p4Client .
          \ ' " . <SID>GetCurrentItem()<CR>'
    exec 'amenu <silent> ' . a:sub .
          \ '&Perforce.&User.&View\ Users :PUsers<CR>'
  endif

  if ! a:expanded
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Job :PJob<CR>'
  else
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Job.&New :PJob<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Job.' .
          \ '&Edit\ Current\ JobSpec :PExecCmd PItemOpen<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Job.' .
          \ 'Descri&be\ Current\ JobSpec :PExecCmd PItemDescribe<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Job.' .
          \ '&Delete\ Current\ JobSpec :PExecCmd PItemDelete<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Job.-Sep1- :'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Job.&Edit\ Job&Spec ' .
	  \ ':PJobspec<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Job.-Sep2- :'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Job.&View\ Jobs :PJobs<CR>'
  endif

  if a:expanded
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Depot.&New :PDepot<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Depot.' .
          \ '&Edit\ Current\ DepotSpec :PExecCmd PItemOpen<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Depot.' .
          \ 'Descri&be\ Current\ DepotSpec :PExecCmd PItemDescribe<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Depot.' .
          \ '&Delete\ Current\ DepotSpec :PExecCmd PItemDelete<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Depot.-Sep- :'
    exec 'amenu <silent> ' . a:sub .
          \ '&Perforce.&Depot.&View\ Depots :PDepots<CR>'
  endif

  if ! a:expanded
    exec 'amenu <silent> ' . a:sub .
          \ '&Perforce.Open\ Current\ File\ From\ A&nother\ Branch :E<CR>'
  else
    exec 'amenu <silent> ' . a:sub .
          \ '&Perforce.&Tools.Open\ Current\ File\ From\ A&nother\ Branch ' .
	  \ ':E<CR>'
  endif

  if ! a:expanded
    exec 'amenu <silent> ' . a:sub . '&Perforce.-Sep7- :'
    exec 'amenu <silent> ' . a:sub . '&Perforce.Sa&ve\ Current\ Spec ' .
	  \':PExecCmd W<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.Save\ and\ &Quit\ ' .
	  \'Current\ Spec :PExecCmd WQ<CR>'
  endif

  exec 'amenu <silent> ' . a:sub . '&Perforce.-Sep8- :'
  exec 'amenu <silent> ' . a:sub . '&Perforce.Re-Initial&ze :PFInitialize<CR>'
  if ! a:expanded
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Help :PH<CR>'
  else
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Help.&General :PH<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Help.&Simple :PH simple<CR>'
    exec 'amenu <silent> ' . a:sub .
          \ '&Perforce.&Help.&Commands :PH commands<CR>'
    exec 'amenu <silent> ' . a:sub .
          \ '&Perforce.&Help.&Environment :PH environment<CR>'
    exec 'amenu <silent> ' . a:sub .
          \ '&Perforce.&Help.&Filetypes :PH filetypes<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Help.&Jobview :PH jobview<CR>'
    exec 'amenu <silent> ' . a:sub .
          \ '&Perforce.&Help.&Revisions :PH revisions<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Help.&Usage :PH usage<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Help.&Views :PH views<CR>'
  endif
endfunction " }}}

"
" Add menu entries if user wants.
"

silent! unmenu Perforce
silent! unmenu! Perforce
if s:menuEnabled
  call s:CreateMenu('', s:useExpandedMenu)
endif

silent! unmenu PopUp.Perforce
silent! unmenu! PopUp.Perforce
if s:popupMenuEnabled
  call s:CreateMenu('PopUp.', s:useExpandedPopupMenu)
endif
let v:errmsg='' " The above unmenu's could have set this variable.

function! s:ToggleCheckOutPrompt(interactive)
  aug P4CheckOut
  au!
  if s:promptToCheckout
    let s:promptToCheckout = 0
  else
    let s:promptToCheckout = 1
    au FileChangedRO * nested :call <SID>CheckOutFile()
  endif
  aug END
  if a:interactive
    echomsg "PromptToCheckout is now " . ((s:promptToCheckout) ? "enabled." :
	  \ "disabled.")
  endif
endfunction

let s:promptToCheckout = ! s:promptToCheckout
call s:ToggleCheckOutPrompt(0)

" Delete unnecessary stuff.
delfunction s:CreateMenu

endfunction " s:Initialize }}}
 
" Do the actual initialization.
call s:Initialize()

""" BEGIN: One-time initialization of some script variables {{{
let s:lastMsg = ''
let s:lastMsgGrp = 'None'
" Indicates the current recursion level for executing p4 commands.
let s:recLevel = 0

if OnMS() && match(&shell, '\<bash\>') != -1
  " When using cygwin bash with native vim, p4 gets confused by the PWD, which
  "   is in cygwin style.
  let s:p4CommandPrefix = "unset PWD && "
else
  let s:p4CommandPrefix = ""
endif

" Special characters in a filename that are not acceptable in a filename (as a
"   window title) on windows.
let s:specialChars = '\([*:?"<>|]\)' 
let s:specialChars{'*'} = 'S'
let s:specialChars{':'} = 'C'
let s:specialChars{'?'} = 'Q'
let s:specialChars{'"'} = 'D'
let s:specialChars{'<'} = 'L'
let s:specialChars{'>'} = 'G'
let s:specialChars{'|'} = 'P'

"
" A lot of metadata on perforce command syntax and handling.
"

let s:p4KnownCmds = "add,admin,branch,branches,change,changes,client,clients," .
      \ "counter,counters,delete,depot,depots,describe,diff,diff2,dirs,edit," .
      \ "filelog,files,fix,fixes,flush,fstat,get,group,groups,have,help,info," .
      \ "integrate,integrated,job,jobs,jobspec,label,labels,labelsync,lock," .
      \ "logger,obliterate,opened,passwd,print,protect,rename,reopen,resolve," .
      \ "resolved,revert,review,reviews,set,submit,sync,triggers,typemap," .
      \ "unlock,user,users,verify,where,"
" Add some built-in commands to this list.
let s:p4KnownCmds = s:p4KnownCmds . "vdiff,vdiff2,"

" Map between the option and the commands that reqire us to pass an argument
"   with this option.
let s:p4OptCmdMap{'b'} = 'diff2,integrate'
let s:p4OptCmdMap{'c'} = 'add,delete,edit,fix,fstat,integrate,lock,opened,' .
      \ 'reopen,revert,review,reviews,submit,unlock'
let s:p4OptCmdMap{'e'} = 'jobs'
let s:p4OptCmdMap{'j'} = 'fixes'
let s:p4OptCmdMap{'l'} = 'labelsync'
let s:p4OptCmdMap{'m'} = 'changes,filelog,jobs'
let s:p4OptCmdMap{'o'} = 'print'
let s:p4OptCmdMap{'s'} = 'changes,integrate'
let s:p4OptCmdMap{'t'} = 'add,client,edit,label,reopen'
let s:p4OptCmdMap{'O'} = 'passwd'
let s:p4OptCmdMap{'P'} = 'passwd'
let s:p4OptCmdMap{'S'} = 'set'

" These built-in options require us to pass an argument. These options start
"   with a '+'.
let s:biOptCmdMap{'c'} = 'diff'


" NOTE: The current file is used as the default argument, only when the
"   command is not one of the s:askUserCmds and it is not one of
"   s:curFileNotDefCmds or s:nofileArgsCmds.
" For these commands, we don't need to default to the current file, as these
"   commands can work without any arguments.
let s:curFileNotDefCmds = 'change,changes,client,files,integrate,job,jobs,' .
      \ 'jobspec,labels,labelsync,opened,resolve,submit,user,'
" For these commands, we need to ask user for the argument, as we can't assume
"   the current file is the default.
let s:askUserCmds = 'admin,branch,counter,depot,fix,group,label,'
" A subset of askUserCmds, that should use a more generic prompt.
let s:genericPromptCmds = 'admin,counter,fix,'
" Commands that essentially display a list of files.
let s:filelistCmds = 'files,have,integrate,opened,'
" Commands that work with a spec.
let s:specCmds='branch,change,client,depot,group,job,jobspec,label,protect,' .
      \ 'submit,triggers,typemap,user,'
" Out of the above specCmds, these are the only commands that don't
"   support '-o' option. Consequently we have to have our own template.
let s:noOutputCmds='submit,'
" The following are used only to create a specification, not to view them.
"   Consequently, they don't accept a '-d' option to delete the spec.
let s:specOnlyCmds = 'jobspec,submit,'
" These commands might change the fstat of files, requiring an update on some
"   or all the buffers loaded into vim.
"let s:statusUpdReqCmds = 'add,delete,edit,get,lock,reopen,revert,sync,unlock,'
"" For these commands we need to call :checktime, as the command might have
""   changed the state of the file.
"let s:checktimeReqCmds = 'edit,get,reopen,revert,sync,'
" For these commands, we can even set 'autoread' along with doing a :checktime.
let s:autoreadCmds = 'edit,get,reopen,revert,sync,'
" These commands don't expect filename arguments, so no special processing for
"   file expansion.
let s:nofileArgsCmds = 'branch,branches,change,client,clients,counters,depot,' .
      \ 'depots,describe,dirs,group,groups,help,info,job,jobspec,label,' .
      \ 'logger,passwd,protect,rename,review,triggers,typemap,user,users,'
" For these commands, the output should not be set to perforce type.
let s:ftNotPerforceCmds = 'diff,diff2,print,vdiff,vdiff2'
" Allows navigation keys in the command window.
let s:navigateCmds = 'help,'
" These commands accept a '-m' argument to limit the list size.
let s:limitListCmds = 'filelog,jobs,changes,'
" These commands take the diff option -dx.
let s:diffCmds = 'describe,diff,diff2,'
" For the following commands, the default output mode is 20.
let s:outputType20Cmds = 'add,delete,edit,get,lock,reopen,revert,sync,unlock,'

" If there is a confirm message, then PFIF() will prompt user before
"   continuing with the run.
let s:confirmMsgs{'revert'} = "Reverting file(s) will overwrite any edits to " .
      \ "the files(s)\n Do you want to continue?"
let s:confirmMsgs{'submit'} = "This will commit the changelist to the depot." .
      \ "\n Do you want to continue?"

" List of the global variable names of the user configurable settings.
let s:settings = 'User,Client,Password,Port,ClientRoot,CmdPath,Presets,' .
      \ 'DefaultOptions,DefaultDiffOptions,EnableMenu,EnablePopupMenu,' .
      \ 'UseExpandedMenu,UseExpandedPopupMenu,EnableRuler,RulerWidth,' .
      \ 'DefaultListSize,EnableActiveStatus,OptimizeActiveStatus,' .
      \ 'ASIgnoreDefPattern,ASIgnoreUsrPattern,PromptToCheckout,' .
      \ 'CheckOutDefault,UseGUIDialogs,MaxLinesInDialog,SortSettings,' .
      \ 'TempDir,SplitCommand,UseVimDiff2,EnableFileChangedShell,' .
      \ 'HideOnBufHidden,Depot,Autoread'

" Map of global variable name to the local variable that are different than
"   their global counterparts.
let s:settingsMap{'EnableActiveStatus'} = 'activeStatusEnabled'
let s:settingsMap{'EnableRuler'} = 'rulerEnabled'
let s:settingsMap{'EnableMenu'} = 'menuEnabled'
let s:settingsMap{'EnablePopupMenu'} = 'popupMenuEnabled'
let s:settingsMap{'ASIgnoreDefPattern'} = 'ignoreDefPattern'
let s:settingsMap{'ASIgnoreUsrPattern'} = 'ignoreUsrPattern'

let s:helpWinName = 'P4\ help'

let s:SPACE_AS_SEP = '\\\@<!\%(\\\\\)* ' " Unprotected space.
let s:EMPTY_STR = '^\s*$'

let s:CM_RUN = 'run' | let s:CM_FILTER = 'filter' | let s:CM_DISPLAY = 'display'
let s:CM_PIPE = 'pipe'

let s:changesExpr  = "matchstr(getline(\".\"), '" . '^Change \zs\d\+\ze ' . "')"
let s:branchesExpr = "matchstr(getline(\".\"), '" . '^Branch \zs[^ ]\+\ze ' .
      \ "')"
let s:labelsExpr   = "matchstr(getline(\".\"), '" . '^Label \zs[^ ]\+\ze ' .
      \ "')"
let s:clientsExpr  = "matchstr(getline(\".\"), '" . '^Client \zs[^ ]\+\ze ' .
      \ "')"
let s:usersExpr    = "matchstr(getline(\".\"), '" .
      \ '^[^ ]\+\ze <[^@>]\+@[^>]\+> ([^)]\+)' . "')"
let s:jobsExpr     = "matchstr(getline(\".\"), '" . '^[^ ]\+\ze on ' . "')"
let s:depotsExpr   = "matchstr(getline(\".\"), '" . '^Depot \zs[^ ]\+\ze ' .
      \ "')"
let s:openedExpr   = "s:ConvertToLocalPath(s:GetCurrentDepotFile(line('.')))"
let s:describeExpr = "s:DescribeGetCurrentItem()"
let s:filesExpr    = "s:ConvertToLocalPath(s:GetCurrentDepotFile(line('.')))"
let s:haveExpr     = "s:ConvertToLocalPath(s:GetCurrentDepotFile(line('.')))"
let s:filelogExpr  = "s:GetCurrentDepotFile(line('.'))"
let s:groupsExpr   = "expand('<cword>')"

" If an explicit handler is defined, then it will override the default rule of
"   finding the command with the singular form.
let s:filelogItemHandler = "s:printHdlr"
let s:changesItemHandler = "s:changeHdlr"
let s:openedItemHandler = "s:OpenFile"
let s:describeItemHandler = "s:OpenFile"
let s:filesItemHandler = "s:OpenFile"
let s:haveItemHandler = "s:OpenFile"

" Define handlers for built-in commands. These have no arguments, they will
"   use the existing parsed command-line vars. Set s:errCode on errors.
let s:builtinCmdHandler{'vdiff'} = 's:VDiffHandler' 
let s:builtinCmdHandler{'vdiff2'} = 's:VDiff2Handler' 

let s:p4Contexts = ""
let s:p4ContextSeparator = ":::"
let s:p4ContextItemSeparator = ";;;"

aug Perforce | aug END " Define autocommand group.
call AddToFCShellPre(s:myScriptId . 'FileChangedShell')

""" END: One-time initialization of some script variables }}}

""" END: Initializations }}}


""" BEGIN: Command specific functions {{{

function! s:printHdlr(scriptOrigin, outputType, ...)
  exec MakeArgumentString()
  exec "let retVal = s:PFIF(a:scriptOrigin + 1, a:outputType, 'print', " .
	\ argumentString . ")"

  if s:StartBufSetup(a:outputType)
    let undo  = 0
    " The first line printed by p4 for non-q operation causes vim to misjudge
    " the filetype.
    if getline(1) =~ '//[^#]\+#\d\+ - '
      setlocal modifiable
      let firstLine = getline(1)
      silent! 1delete _
    endif

    set ft=
    doautocmd filetypedetect BufNewFile
    " If automatic detection doesn't work...
    if &ft == ""
      let &ft=s:GuessFileTypeForCurrentWindow()
    endif

    if exists('firstLine')
      silent! 1put! =firstLine
      setlocal nomodifiable
    endif

    call s:EndBufSetup(a:outputType)
  endif
  return retVal
endfunction

function! s:describeHdlr(scriptOrigin, outputType, ...)
  exec MakeArgumentString()
  if !a:scriptOrigin
    exec "call s:ParseOptionsIF(1, line('$'), 1, 'describe', " .
	  \ argumentString . ")"
  endif
  " If -s doesn't exist, and user doesn't intent to see a diff, then let us
  "   add -s option. In any case he can press enter on the <SHOW DIFFS> to see
  "   it later.
  if	  ! MvContainsElement(s:p4CmdOptions, s:SPACE_AS_SEP, '-s', ' ') &&
	\ ! MvContainsPattern(s:p4CmdOptions, s:SPACE_AS_SEP, '-d.', ' ')
    let s:p4CmdOptions = s:p4CmdOptions . ' -s'
    let s:p4WinName = s:MakeWindowName() " Adjust window name.
  endif

  exec "let retVal = s:PFIF(2, a:outputType, 'describe')"
  if s:StartBufSetup(a:outputType) && getline(1) !~ ' - no such changelist'
    call s:SetupFileBrowse(a:outputType)
    if MvContainsElement(s:p4CmdOptions, s:SPACE_AS_SEP, '-s', ' ')
      setlocal modifiable
      call append('$', "\t<SHOW DIFFS>")
      setlocal nomodifiable
    else
      call s:SetupDiff()
    endif

    call s:EndBufSetup(a:outputType)
  endif
  return retVal
endfunction

function! s:diffHdlr(scriptOrigin, outputType, ...)
  exec MakeArgumentString()
  if !a:scriptOrigin
    exec "call s:ParseOptionsIF(1, line('$'), 1, 'diff', " .
	  \ argumentString . ")"
  endif

  " If a change number is specified in the diff, we need to handle it
  "   ourselves, as p4 doesn't understand this.
  let changeIdx = MvIndexOfPattern(s:p4CmdOptions, s:SPACE_AS_SEP,
	\ '+c\s\+\d\+', ' ') " Searches including change no.
  if changeIdx != -1 " If a change no. is specified.
    call s:PushP4Context()
    let s:p4Command = 'opened'
    let s:p4CmdOptions = '-c ' . MvElementAt(s:p4CmdOptions, s:SPACE_AS_SEP,
	  \ changeIdx + 1, ' ')
    let retVal = s:PFIF(2, a:outputType, 'opened')
    if s:errCode != 0
      return
    endif
    if getline(1) !~ 'ile(s) not opened on this client\.'
      setl modifiable
      call s:SilentSub('#.*', '%s///e')
      call s:PeekP4Context() " Bring in a copy.
      exec "PF -x - " . s:p4Options . " ++f diff"
    endif
    call s:PopP4Context()
  else
    exec "let retVal = s:PFIF(2, a:outputType, 'diff')"
  endif
  if s:StartBufSetup(a:outputType)
    call s:SetupDiff()

    call s:EndBufSetup(a:outputType)
  endif
  return retVal
endfunction

function! s:diff2Hdlr(scriptOrigin, outputType, ...)
  exec MakeArgumentString()
  if !a:scriptOrigin
    exec "call s:ParseOptionsIF(1, line('$'), 1, 'diff2', " .
	  \ argumentString . ")"
  endif

  " The pattern takes care of ignoring protected spaces as separators.
  let nArgs = MvNumberOfElements(s:p4Arguments, s:SPACE_AS_SEP, ' ')
  if nArgs < 2
    if nArgs == 0
      let file = s:EscapeFileName(expand('%'))
    else
      let file = s:p4Arguments
    endif
    let ver1 = s:PromptFor(0, s:useGUIDialogs, "Version1? ", '')
    let ver2 = s:PromptFor(0, s:useGUIDialogs, "Version2? ", '')
    let s:p4Arguments = file . s:MakeRevStr(ver1) . " " . file .
	  \ s:MakeRevStr(ver2)
  endif

  exec "let retVal = s:PFIF(2, a:outputType, 'diff2')"
  if s:StartBufSetup(a:outputType)
    call s:SetupDiff()

    call s:EndBufSetup(a:outputType)
  endif
  return retVal
endfunction

function! s:changeHdlrImpl(outputType)
  let _p4Arguments = ''
  " If argument(s) is not a number...
  if s:p4Arguments != '' && match(s:p4Arguments, '^\d\+$') == -1
    let _p4Arguments = s:p4Arguments
    let s:p4Arguments = '' " Let a new changelist be created.
  endif
  let retVal = s:PFIF(2, a:outputType, 'change')
  if s:errCode == 0 && s:StartBufSetup(a:outputType) ||
	\ s:commandMode == s:CM_FILTER
    let p4Options = ''
    if s:p4Options != ''
      let p4Options = CreateArgString(s:p4Options, s:SPACE_AS_SEP, ' ') .
	    \ ', '
    endif
    if _p4Arguments != ''
      if search('^Files:', 'w') && line('.') != line('$')
	call SaveHardPosition('PChangeImpl')
	+
	call s:PushP4Context()
	exec '.,$call s:PFIF(1, 0, ' . p4Options . '"++f", "opened", "-c", ' .
	      \ '"default", ' . CreateArgString(_p4Arguments, ' ') . ')'
	call s:PopP4Context()

	if s:errCode == 0
	  call s:SilentSub('^', '.,$s//\t/e')
	  call RestoreHardPosition('PChangeImpl')
	  call s:SilentSub('#\d\+ - \(\S\+\) .*$', '.,$s//\t# \1/e')
	endif
	call RestoreHardPosition('PChangeImpl')
	call ResetHardPosition('PChangeImpl')
      endif
    endif

    call s:EndBufSetup(a:outputType)
    setl nomodified
    if _p4Arguments != '' && &cmdheight > 1
      " The message about W and WQ must have gone by now.
      redraw | call s:LastMessage()
    endif
  endif
  return retVal
endfunction

function! s:changeHdlr(scriptOrigin, outputType, ...)
  exec MakeArgumentString()
  if !a:scriptOrigin
    exec "call s:ParseOptionsIF(1, line('$'), 1, 'change', " .
	  \ argumentString . ")"
  endif
  let retVal = s:changeHdlrImpl(a:outputType)
  if s:StartBufSetup(a:outputType)
    let p4Options = ''
    if s:p4Options != ''
      let p4Options = CreateArgString(s:p4Options, s:SPACE_AS_SEP, ' ') .
	    \ ', '
    endif
    exec 'command! -buffer -nargs=* PChangeSubmit :call <SID>W(0, ' .
	  \ p4Options . '"submit", <f-args>)'

    call s:EndBufSetup(a:outputType)
  endif
  return retVal
endfunction

" Create a template for submit.
function! s:submitHdlr(scriptOrigin, outputType, ...)
  exec MakeArgumentString()
  if !a:scriptOrigin
    exec "call s:ParseOptionsIF(1, line('$'), 1, 'submit', " .
	  \ argumentString . ")"
  endif

  if MvContainsElement(s:p4CmdOptions, s:SPACE_AS_SEP, '-c', ' ') == 1
    " Non-interactive.
    let retVal = s:PFIF(2, a:outputType, 'submit')
  else
    call s:PushP4Context()
    " This is done just to get the :W and :WQ commands defined properly and
    "	open the window with a proper name. The actual job is done by the call
    "	to s:changeHdlrImpl() which is then run in filter mode to avoid the
    "	side-effects (such as :W and :WQ getting redefined etc.)
    let s:p4CmdOptions = '+y ' . s:p4CmdOptions " Don't confirm.
    let s:p4Options = '+t ' . s:p4Options " Testmode.
    call s:PFIF(2, 0, 'submit')
    let _newWindowCreated = s:newWindowCreated
    call s:PeekP4Context()
    let s:p4CmdOptions = '' " These must be specific to 'submit'.
    let s:p4Command = 'change'
    let s:commandMode = s:CM_FILTER | let s:filterRange = '.'
    let retVal = s:changeHdlrImpl(a:outputType)
    setlocal nomodified
    if s:errCode != 0
      return
    endif
    let s:newWindowCreated = _newWindowCreated
    call s:PopP4Context()

    if s:StartBufSetup(a:outputType)
      let p4Options = ''
      if s:p4Options != ''
	let p4Options = CreateArgString(s:p4Options, s:SPACE_AS_SEP, ' ') .
	      \ ', '
      endif
      exec 'command! -buffer -nargs=* PSubmitPostpone :call <SID>W(0, ' .
	    \ p4Options . '"change", <f-args>)'
      set ft=perforce " Just to get the cursor placement right.
      call s:EndBufSetup(a:outputType)
    endif

    if s:errCode
      call s:EchoMessage("Error creating submission template.", 'Error')
    endif
  endif
  return s:errCode
endfunction

function! s:resolveHdlr(scriptOrigin, outputType, ...)
  exec MakeArgumentString()
  if !a:scriptOrigin
    exec "call s:ParseOptionsIF(1, line('$'), 1, 'resolve', " .
	  \ argumentString . ")"
  endif

  if (match(s:p4CmdOptions, '-a[fmsty]\>') == -1) &&
        \ (match(s:p4CmdOptions, '-n\>') == -1)
    return s:SyntaxError("Interactive resolve not implemented (yet).")
  endif
  exec "let retVal = s:PFIF(2, a:outputType, 'resolve')"
  return retVal
endfunction

function! s:filelogHdlr(scriptOrigin, outputType, ...)
  exec MakeArgumentString()
  exec "let retVal = s:PFIF(a:scriptOrigin + 1, a:outputType, 'filelog', " .
	\ argumentString . ")"

  if s:StartBufSetup(a:outputType)
    " No meaning for delete.
    silent! nunmap <buffer> D
    silent! delcommand PItemDelete
    command! -range -buffer -nargs=0 PFilelogDiff
          \ :call s:FilelogDiff2(<line1>, <line2>)
    vnoremap <silent> <buffer> D :PFilelogDiff<CR>
    command! -buffer -nargs=0 PFilelogPrint :call <SID>PFIF(0, 0, 'print',
	  \ <SID>GetCurrentItem())
    nnoremap <silent> <buffer> p :PFilelogPrint<CR>
    command! -buffer -nargs=0 PFilelogSync :call <SID>FilelogSyncToCurrentItem()
    nnoremap <silent> <buffer> S :PFilelogSync<CR>
    command! -buffer -nargs=0 PFilelogDescribe
          \ :call <SID>FilelogDescribeChange()
    nnoremap <silent> <buffer> C :PFilelogDescribe<CR>

    call s:EndBufSetup(a:outputType)
  endif
endfunction

function! s:clientsHdlr(scriptOrigin, outputType, ...)
  exec MakeArgumentString()
  exec "let retVal = s:PFIF(a:scriptOrigin + 1, a:outputType, 'clients', " .
	\ argumentString . ")"

  if s:StartBufSetup(a:outputType)
    command! -buffer -nargs=0 PClientsTemplate
          \ :call <SID>PFIF(1, 0, 'client', '+P', '-t', <SID>GetCurrentItem())
    nnoremap <silent> <buffer> P :PClientsTemplate<CR>

    call s:EndBufSetup(a:outputType)
  endif
  return retVal
endfunction

function! s:changesHdlr(scriptOrigin, outputType, ...)
  exec MakeArgumentString()
  exec "let retVal = s:PFIF(a:scriptOrigin + 1, a:outputType, 'changes', " .
	\ argumentString . ")"

  if s:StartBufSetup(a:outputType)
    command! -buffer -nargs=0 PItemDescribe
	  \ :call <SID>PChangesDescribeCurrentItem()
    command! -buffer -nargs=0 PChangesSubmit
          \ :call <SID>ChangesSubmitChangeList()
    nnoremap <silent> <buffer> S :PChangesSubmit<CR>
    command! -buffer -nargs=0 PChangesOpened
	  \ :if getline('.') =~ " \\*pending\\* '" |
	  \    call <SID>PFIF(1, 0, 'opened', '-c', <SID>GetCurrentItem()) |
	  \  endif
    command! -buffer -nargs=0 PItemOpen
	  \ :if getline('.') =~ " \\*pending\\* '" |
	  \    call <SID>PFIF(0, 0, 'change', <SID>GetCurrentItem()) |
	  \  else |
	  \    call <SID>PFIF(0, 0, 'describe', '-dd', <SID>GetCurrentItem()) |
	  \  endif
    nnoremap <silent> <buffer> o :PChangesOpened<CR>

    call s:EndBufSetup(a:outputType)
  endif
endfunction

function! s:labelsHdlr(scriptOrigin, outputType, ...)
  exec MakeArgumentString()
  exec "let retVal = s:PFIF(a:scriptOrigin + 1, a:outputType, 'labels', " .
	\ argumentString . ")"

  if s:StartBufSetup(a:outputType)
    command! -buffer -nargs=0 PLabelsSyncClient
          \ :call <SID>LabelsSyncClientToLabel()
    nnoremap <silent> <buffer> S :PLabelsSyncClient<CR>
    command! -buffer -nargs=0 PLabelsSyncLabel
          \ :call <SID>LabelsSyncLabelToClient()
    nnoremap <silent> <buffer> C :PLabelsSyncLabel<CR>
    command! -buffer -nargs=0 PLabelsFiles :call <SID>PFIF(1, 0, 'files', '+p',
	  \ '//...@'. <SID>GetCurrentItem())
    nnoremap <silent> <buffer> I :PLabelsFiles<CR>
    command! -buffer -nargs=0 PLabelsTemplate :call <SID>PFIF(1, 0, 'label',
	  \ '+P', '-t', <SID>GetCurrentItem())
    nnoremap <silent> <buffer> P :PLabelsTemplate<CR>

    call s:EndBufSetup(a:outputType)
  endif
  return retVal
endfunction

function! s:helpHdlr(scriptOrigin, outputType, ...)
  call SaveWindowSettings2("PerforceHelp", 1)
  " If there is a help window already open, then we need to reuse it.
  exec MakeArgumentString()
  let helpWin = bufwinnr(s:helpWinName)
  exec "let retVal = s:PFIF(a:scriptOrigin + 1, a:outputType, 'help', " .
	\ argumentString . ")"

  if s:StartBufSetup(a:outputType)
    command! -buffer -nargs=0 PHelpSelect
	  \ :call <SID>helpHdlr(0, 0, expand("<cword>"))
    nnoremap <silent> <buffer> <CR> :PHelpSelect<CR>
    nnoremap <silent> <buffer> K :PHelpSelect<CR>
    nnoremap <silent> <buffer> <2-LeftMouse> :PHelpSelect<CR>
    call s:PFUnSetupBufAutoCommand(DeEscape(s:helpWinName), 'BufUnload')
    call AddNotifyWindowClose(s:helpWinName, s:myScriptId . "RestoreWindows")
    if helpWin == -1 " Resize only when it was not already visible.
      exec "resize " . 20
    endif
    redraw | echo
	  \ "Press <CR>/K/<2-LeftMouse> to drilldown on perforce help keywords."

    call s:EndBufSetup(a:outputType)
  endif
  return retVal
endfunction

" Built-in command handlers {{{
function! s:VDiffHandler()
  if MvNumberOfElements(s:p4Arguments, s:SPACE_AS_SEP, ' ') >= 2
    return s:SyntaxError("Too many arguments passed to vdiff.")
  endif

  if s:p4Arguments != ''
    let fileName = s:p4Arguments
    let v:errmsg = ""
    exec s:splitCommand fileName
    if v:errmsg != ""
      return s:SyntaxError("There was an error openeing the file: " . fileName)
    endif
  else
    let fileName = expand('%') " This is already visible.
  endif

  let s:p4Command = 'print'
  let s:p4CmdOptions = s:p4CmdOptions . ' -q'
  let s:p4WinName = s:MakeTempName(fileName)
  let s:p4Arguments = fileName
  let _splitCommand = s:splitCommand
  let s:splitCommand = "vsplit"
  call s:PFIF(2, 0, 'print')
  let s:splitCommand = _splitCommand
  if s:errCode != 0
    return
  endif
  diffthis
  wincmd l
  diffthis
  wincmd _
endfunction

function! s:VDiff2Handler()
  if MvNumberOfElements(s:p4Arguments, s:SPACE_AS_SEP, ' ') != 2
    return s:SyntaxError("vdiff2 command requires two arguments.")
  endif

  let firstFile = MvElementAt(s:p4Arguments, s:SPACE_AS_SEP, 0, ' ')
  let secondFile = MvElementAt(s:p4Arguments, s:SPACE_AS_SEP, 1, ' ')
  let tempFile1 = s:MakeTempName(firstFile)
  let tempFile2 = s:MakeTempName(secondFile)
  if firstFile == "" || secondFile == "" || (tempFile1 == tempFile2)
    return s:SyntaxError(
	  \ "vdiff2 command requires two distinct files as arguments.")
  endif

  let s:p4Command = 'print'
  let s:p4CmdOptions = s:p4CmdOptions . ' -q'
  let s:p4WinName = tempFile1
  let s:p4Arguments = firstFile
  call s:PFIF(2, 0, 'print')
  if s:errCode != 0
    return
  endif
  let s:p4WinName = tempFile2
  let s:p4Arguments = secondFile
  let _splitCommand = s:splitCommand
  wincmd K
  let s:splitCommand = "vsplit"
  call s:PFIF(2, 0, 'print')
  let s:splitCommand = _splitCommand
  if s:errCode != 0
    return
  endif
  diffthis
  wincmd l
  diffthis
  wincmd _
endfunction

" Returns a fileName in the temp directory that is unique for the branch and
"   revision specified in the fileName.
function! s:MakeTempName(filePath)
  let depotPath = s:ConvertToDepotPath(a:filePath)
  if depotPath == ''
    return ''
  endif
  let tmpName = s:tempDir . '/'
  let branch = s:GetBranchName(depotPath)
  if branch != ''
    let tmpName = s:tempDir . branch . '-'
  endif
  let revSpec = s:GetRevisionSpecifier(depotPath)
  if revSpec != ''
    let tmpName = tmpName . substitute(strpart(revSpec, 1), '/', '_', 'g') . '-'
  endif
  return tmpName . fnamemodify(substitute(a:filePath, '\\*#\d\+$', '', ''),
	\ ':t')
endfunction

function! s:SyntaxError(msg)
  if s:errCode == 0
    let s:errCode = 1
  endif
  call s:ConfirmMessage(a:msg, "OK", 1, "Error")
  return s:errCode
endfunction
" Built-in command handlers }}}

""" END: Command specific functions }}}


""" BEGIN: Helper functions {{{

" Open a file from an alternative codeline.
" If mode == 0, first file is opened and all other files are added to buffer
"   list.
" If mode == 1, the files are not really opened, the list is just returned.
" If mode == 2, it behaves the same as mode == 0, except that the file is
"   split opened.
" If there are no arguments passed, user is prompted to enter. He can then
"   enter a codeline followed by a list of filenames.
" If only one argument is passed, it is assumed to be the codeline and the
"   current filename is assumed (user is not prompted).
function! s:PFOpenAltFile(mode, ...) " {{{
  if a:0 < 2
    if a:0 == 0
      " Prompt for codeline string (codeline optionally followed by filenames).
      let codelineStr = s:PromptFor(0, s:useGUIDialogs,
	    \ "Enter the alternative codeline string: ", '')
      if codelineStr == ""
	return ""
      endif
      if MvNumberOfElements(codelineStr, s:SPACE_AS_SEP, ' ') < 2
	let codelineStr = codelineStr . ' ' . s:EscapeFileName(expand('%'))
      endif
    elseif a:0 == 1
      let codelineStr = a:1 . ' ' . s:EscapeFileName(expand('%'))
    endif
    let argumentString = CreateArgString(codelineStr, s:SPACE_AS_SEP)
  else
    exec MakeArgumentString()
  endif

  exec "let altFileNames = s:PFGetAltFiles(" . argumentString . ")"
  if a:mode == 0 || a:mode == 2
    let n = MvNumberOfElements(altFileNames, s:SPACE_AS_SEP, ' ')
    if n == 1
      execute ((a:mode == 0) ? ":edit " : ":split ") . altFileNames
    else
      call MvIterCreate(altFileNames, s:SPACE_AS_SEP, "Perforce", ' ')
      while MvIterHasNext("Perforce")
	execute ":badd " . MvIterNext("Perforce")
      endwhile
      call MvIterDestroy("Perforce")
      execute ((a:mode == 0) ? ":edit " : ":split ") . 
	    \ MvElementAt(altFileNames, s:SPACE_AS_SEP, 0, ' ')
    endif
  else
    return altFileNames
  endif
endfunction " }}}

" Interactively change the port/client/user.
function! s:SwitchPortClientUser() " {{{
  let p4Port = s:PromptFor(0, s:useGUIDialogs, "Port: ", s:p4Port)
  let p4Client = s:PromptFor(0, s:useGUIDialogs, "Client: ", s:p4Client)
  let p4User = s:PromptFor(0, s:useGUIDialogs, "User: ", s:p4User)
  call s:PSwitch(p4Port, p4Client, p4User)
endfunction " }}}

" No args: Print presets and prompt user to select a preset.
" Number: Select that numbered preset.
" port [client] [user]: Set the specified settings.
function! s:PSwitch(...) " {{{
  let nSets = MvNumberOfElements(s:p4Presets, ',')
  if a:0 == 0
    if nSets == 0
      call s:EchoMessage("No sets to select from.", 'Error')
      return
    endif

    let selectedSetting = MvPromptForElement(s:p4Presets, ',', -1,
          \ "Select the setting: ", -1, s:useGUIDialogs)
    call s:PSwitchHelper(selectedSetting)
    return
  else
    if match(a:1, '^\d\+') == 0
      let index = a:1 + 0
      if index >= nSets
        call s:EchoMessage("Not that many sets.", 'Error')
        return
      endif
      let selectedSetting = MvElementAt(s:p4Presets, ',', index)
      call s:PSwitchHelper(selectedSetting)
      return
    else
      let g:p4Port = a:1
      if a:0 > 1
        let g:p4Client = a:2
      endif
      if a:0 > 2
        let g:p4User = a:3
      endif
    endif
    let g:p4Password = ""
    call s:Initialize()
    call s:GetClientInfo()
  endif
endfunction " }}}

function! s:PSwitchHelper(settingStr) " {{{
  if a:settingStr != ""
    let settingStr = substitute(a:settingStr, '\s\+', "','", 'g')
    let settingStr = substitute(settingStr, '^', "'", '')
    let settingStr = substitute(settingStr, '$', "'", '')
    exec 'call s:PSwitch(' . settingStr . ')'
  endif
endfunction " }}}

" Handler for opened command.
function! s:OpenFile(scriptOrigin, outputType, fileName) " {{{
  if filereadable(a:fileName)
    if a:outputType == 0
      let curWin = winnr()
      let winnr = bufwinnr(a:fileName)
      if winnr != -1
	exec winnr.'wincmd w'
      else
	wincmd p
      endif
      if curWin != winnr() && winnr() == GetPreviewWinnr()
	wincmd p " Don't use preview window.
      endif
      if winnr() == curWin
	split
      endif
      let bufNr = FindBufferForName(a:fileName)
      if bufNr != -1
	exec "buffer" bufNr | " Preserves line number.
      else
	exec "edit " . a:fileName
      endif
    else
      " FIXME: Check if I can use the s:GotoWindow() function here.
      if ! s:p4HideOnBufHidden && exists('b:p4Command')
	pclose
      endif
      exec "pedit " . a:fileName
    endif
  else
    call s:printHdlr(0, a:outputType, a:fileName)
  endif
endfunction " }}}

function! s:DescribeGetCurrentItem() " {{{
  if getline(".") == "\t<SHOW DIFFS>"
    let b:p4FullCmd = MvRemovePattern(b:p4FullCmd, s:SPACE_AS_SEP,
	  \ "[\"']\\?-s[\"']\\?", ' ') " -s possibly sorrounded by quotes.
    call s:PRefreshActivePane()
    call s:SetupDiff()
    return ""
  else
    return s:ConvertToLocalPath(s:GetCurrentDepotFile(line('.')))
  endif
endfunction " }}}

function! s:getCommandItemHandler(outputType, command, args) " {{{
  let itemHandler = ""
  if exists("s:{a:command}ItemHandler")
    let itemHandler = s:{a:command}ItemHandler
  elseif match(a:command, 'e\?s$') != -1
    let handlerCmd = substitute(a:command, 'e\?s$', '', '')
    if exists('*s:{handlerCmd}Hdlr')
      let itemHandler = 's:' . handlerCmd . 'Hdlr'
    else
      let itemHandler = 's:PFIF'
    endif
  endif
  if itemHandler == 's:PFIF'
    return "call s:PFIF(1, " . a:outputType . ", '" . handlerCmd . "', " .
	  \ a:args . ")"
  elseif itemHandler != ''
    return 'call ' . itemHandler . '(0, ' . a:outputType . ', ' . a:args . ')'
  endif
  return itemHandler
endfunction " }}}

function! s:OpenCurrentItem(outputType) " {{{
  let curItem = s:GetCurrentItem()
  if curItem != ""
    let commandHandler = s:getCommandItemHandler(a:outputType, b:p4Command,
	  \ "'" . curItem . "'")
    if commandHandler != ""
      exec commandHandler
    endif
  endif
endfunction " }}}

function! s:GetCurrentItem() " {{{
  if exists("b:p4Command") && exists("s:{b:p4Command}Expr")
    exec "return " s:{b:p4Command}Expr
  endif
  return ""
endfunction " }}}

function! s:DeleteCurrentItem() " {{{
  let curItem = s:GetCurrentItem()
  if curItem != ""
    let answer = s:ConfirmMessage("Are you sure you want to delete " .
          \ curItem . "?", "&Yes\n&No", 2, "Question")
    if answer == 1
      let commandHandler = s:getCommandItemHandler(2, b:p4Command,
	    \ "'-d', '" . curItem . "'")
      if commandHandler != ""
	exec commandHandler
      endif
      if v:shell_error == ""
        call s:PRefreshActivePane()
      endif
    endif
  endif
endfunction " }}}

function! s:LaunchCurrentFile() " {{{
  if s:fileLauncher == ''
    call s:ConfirmMessage("There was no launcher command configured to launch ".
	  \ "this item, use g:p4FileLauncher to configure." , "OK", 1, "Error")
    return
  endif
  let curItem = s:GetCurrentItem()
  if curItem != ""
    exec 'silent! !'.s:fileLauncher curItem
  endif
endfunction " }}}

function! s:FilelogDiff2(line1, line2) " {{{
  let line1 = a:line1
  let line2 = a:line2
  if line1 == line2
    if line2 < line("$")
      let line2 = line2 + 1
    elseif line1 > 1
      let line1 = line1 - 1
    else
      return
    endif
  endif

  let file1 = s:GetCurrentDepotFile(line1)
  if file1 != ""
    let file2 = s:GetCurrentDepotFile(line2)
    if file2 != "" && file2 != file1
      " file2 will be older than file1.
      exec "call s:PFIF(0, -1, \"" . (s:useVimDiff2 ? 'vdiff2' : 'diff2') .
	    \ "\", file2, file1)"
    endif
  endif
endfunction " }}}

function! s:FilelogSyncToCurrentItem() " {{{
  let curItem = s:GetCurrentItem()
  if curItem != ""
    let answer = s:ConfirmMessage("Do you want to sync to: " . curItem . " ?",
          \ "&Yes\n&No", 2, "Question")
    if answer == 1
      call s:PFIF(1, -1, 'sync', curItem)
    endif
  endif
endfunction " }}}

function! s:ChangesSubmitChangeList() " {{{
  let curItem = s:GetCurrentItem()
  if curItem != ""
    let answer = s:ConfirmMessage("Do you want to submit change list: " .
          \ curItem . " ?", "&Yes\n&No", 2, "Question")
    if answer == 1
      call s:submitHdlr(0, 0, "+y", "-c", curItem)
    endif
  endif
endfunction " }}}

function! s:LabelsSyncClientToLabel() " {{{
  let curItem = s:GetCurrentItem()
  if curItem != ""
    let answer = s:ConfirmMessage("Do you want to sync client to the label: " .
          \ curItem . " ?", "&Yes\n&No", 2, "Question")
    if answer == 1
      exec "let retVal = s:PFIF(1, 1, 'sync',
	    \ '//" . s:p4Depot . "/...@' . curItem)"
      return retVal
    endif
  endif
endfunction " }}}

function! s:LabelsSyncLabelToClient() " {{{
  let curItem = s:GetCurrentItem()
  if curItem != ""
    let answer = s:ConfirmMessage("Do you want to sync label: " . curItem .
          \ " to client " . s:p4Client . " ?", "&Yes\n&No", 2, "Question")
    if answer == 1
      exec "let retVal = s:PFIF(1, 1, 'labelsync', '-l', curItem)"
      return retVal
    endif
  endif
endfunction " }}}

function! s:FilelogDescribeChange() " {{{
  let changeNo = matchstr(getline("."), ' change \zs\d\+\ze ')
  if changeNo != ""
    exec "call s:describeHdlr(0, 1, changeNo)"
  endif
endfunction " }}}

function! s:SetupFileBrowse(outputType) " {{{
  " For now, assume that a new window is created and we are in the new window.
  exec "setlocal includeexpr=" . s:myScriptId . "ConvertToLocalPath(v:fname)"

  " No meaning for delete.
  silent! nunmap <buffer> D
  silent! delcommand PItemDelete
  command! -buffer -nargs=0 PFileDiff :call <SID>diffHdlr(0, 1,
	\ <SID>ConvertToLocalPath(<SID>GetCurrentDepotFile(line("."))))
  nnoremap <silent> <buffer> D :PFileDiff<CR>
  command! -buffer -nargs=0 PFileProps :call <SID>PFIF(1, 0, 'fstat', '-C',
	\ <SID>GetCurrentDepotFile(line(".")))
  nnoremap <silent> <buffer> P :PFileProps<CR>
  command! -buffer -nargs=0 PFileRevert :call <SID>PFIF(1, -1, 'revert',
	\ <SID>ConvertToLocalPath(<SID>GetCurrentDepotFile(line("."))))
  nnoremap <silent> <buffer> R :PFileRevert \| PRefreshActivePane<CR>
  command! -buffer -nargs=0 PFilePrint :call <SID>printHdlr(0, 0,
	\ <SID>GetCurrentDepotFile(line(".")))
  nnoremap <silent> <buffer> p :PFilePrint<CR>
  command! -buffer -nargs=0 PFileGet :call <SID>PFIF(1, -1, 'sync',
	\ <SID>GetCurrentDepotFile(line(".")))
  command! -buffer -nargs=0 PFileSync :call <SID>PFIF(1, -1, 'sync',
	\ substitute(<SID>GetCurrentDepotFile(line(".")), '#.*', '', ''))
  nnoremap <silent> <buffer> S :PFileSync<CR>
  command! -buffer -nargs=0 PFileChange :call <SID>changeHdlr(0, 0, 
	\ <SID>GetCurrentChangeNumber(line(".")))
  nnoremap <silent> <buffer> C :PFileChange<CR>
  command! -buffer -nargs=0 PFileLaunch :call <SID>LaunchCurrentFile()
  nnoremap <silent> <buffer> A :PFileLaunch<CR>
endfunction " }}}

function! s:SetupDiff() " {{{
  setlocal ft=diff
  command! -buffer -nargs=0 PDiffLink :call <SID>DiffOpenSrc(0)
  command! -buffer -nargs=0 PDiffPLink :call <SID>DiffOpenSrc(1)
  nnoremap <buffer> <silent> O :PDiffLink<CR>
  nnoremap <buffer> <silent> <CR> :PDiffPLink<CR>
endfunction " }}}

function! s:SetupSelectItem() " {{{
  nnoremap <buffer> <silent> D :PItemDelete<CR>
  nnoremap <buffer> <silent> O :PItemOpen<CR>
  nnoremap <buffer> <silent> <CR> :PItemDescribe<CR>
  nnoremap <buffer> <silent> <2-LeftMouse> :PItemDescribe<CR>
  command! -buffer -nargs=0 PItemDescribe :call <SID>OpenCurrentItem(1)
  command! -buffer -nargs=0 PItemOpen :call <SID>OpenCurrentItem(0)
  command! -buffer -nargs=0 PItemDelete :call <SID>DeleteCurrentItem()
  cnoremap <buffer> <C-X><C-I> <C-R>=<SID>GetCurrentItem()<CR>
endfunction " }}}

function! s:RestoreWindows(dummy) " {{{
  call RestoreWindowSettings2("PerforceHelp")
  call s:PFExecBufClean(bufnr(s:helpWinName))
endfunction " }}}

function! s:NavigateBack() " {{{
  call s:Navigate('u')
  if line('$') == 1 && getline(1) == ''
    call s:NavigateForward()
  endif
endfunction " }}}

function! s:NavigateForward() " {{{
  call s:Navigate("\<C-R>")
endfunction " }}}

function! s:Navigate(key) " {{{
  let _modifiable = &l:modifiable
  try
    setlocal modifiable
    " Use built-in markers as Vim takes care of remembering and restoring them
    "   during the undo/redo.
    normal! mt

    silent! exec "normal" a:key

    if line("'t") > 0 && line("'t") <= line('$')
      normal! `t
    endif
  finally
    let &l:modifiable = _modifiable
  endtry
endfunction " }}}

function! s:GetCurrentChangeNumber(lineNo) " {{{
  let line = getline(a:lineNo)
  let changeNo = matchstr(line, ' - \S\+ change \zs\S\+\ze (')
  if changeNo == 'default'
    let changeNo = ''
  endif
  return changeNo
endfunction " }}}

function! s:PChangesDescribeCurrentItem() " {{{
  let currentChangeNo = s:GetCurrentItem()
  if currentChangeNo != ""
    call s:describeHdlr(0, 1, '-s', currentChangeNo)

    " For pending changelist, we have to run a separate opened command to get
    "	the list of opened files. We don't need <SHOW DIFFS> line, as it is
    "	still not subbmitted. This works like p4win.
    if getline('.') =~ "^.* \\*pending\\* '.*$"
      wincmd p
      setlocal modifiable
      call setline(line('$'), "Affected files ...")
      call append(line('$'), "")
      call append(line('$'), "")
      exec '$call s:PW(0, "opened", "-c", currentChangeNo)'
      wincmd p
    endif
  endif
endfunction " }}}

function! s:PFSettings() " {{{
  if s:sortSettings
    if exists("s:sortedSettings")
      let settings = s:sortedSettings
    else
      let settings = MvQSortElements(s:settings, ',', 'CmpByString', 1)
      let s:sortedSettings = settings
    endif
  else
    let settings = s:settings
  endif
  let selectedSetting = MvPromptForElement2(settings, ',', -1,
	\ "Select the setting: ", -1, 0, 3)
  if selectedSetting != ""
    let oldVal = ''
    if exists('s:p4{selectedSetting}')
      let oldVal = s:p4{selectedSetting}
    else
      if exists('s:settingsMap{selectedSetting}')
	let oldVal = s:{s:settingsMap{selectedSetting}}
      else
	let localVar = substitute(selectedSetting, '^\(\u\)', '\L\1', '')
	if exists('s:{localVar}')
	  let oldVal = s:{localVar}
	else
	  echoerr "Internal error detected, couldn't locate value for " .
		\ selectedSetting
	endif
      endif
    endif
    let newVal = input("Current value for " . selectedSetting . " is: " .
	  \ oldVal . "\nEnter new value: ", oldVal)
    if newVal != oldVal
      exec "let g:p4" . selectedSetting . " = '" . newVal . "'"
      call s:Initialize()
    endif
  endif
endfunction " }}}

function! s:MakeRevStr(ver) " {{{
  let verStr = ''
  if a:ver =~ '^[#@&]'
    let verStr = a:ver
  elseif a:ver =~ '^[-+]\?\d\+\>\|^none\>\|^head\>\|^have\>'
    let verStr = '#' . a:ver
  elseif a:ver != ''
    let verStr = '@' . a:ver
  endif
  return verStr
endfunction " }}}

function! s:GetDepotName(fileName) " {{{
  if s:IsFileUnderDepot(a:fileName)
    return s:p4Depot
  elseif stridx(a:fileName, '//') == 0
    return matchstr(a:fileName, '^//\zs[^/]\+\ze/')
  else
    return ''
  endif
endfunction " }}}

function! s:GetBranchName(fileName) " {{{
  if s:IsFileUnderDepot(a:fileName)
    " TODO: Need to run where command at this phase.
  elseif stridx(a:fileName, '//') == 0
    return matchstr(a:fileName, '^//[^/]\+/\zs[^/]\+\ze')
  else
    return ''
  endif
endfunction " }}}

function! s:GetRevisionSpecifier(fileName) " {{{
  return matchstr(a:fileName,
	\ '^\(\%(\S\|\\\@<!\%(\\\\\)*\\ \)\+\)[\\]*\zs[#@].*$')
endfunction " }}}

function! s:PExecCmd(cmd) " {{{
  if exists(':'.a:cmd)
    exec a:cmd
  else
    call s:EchoMessage('The command: ' . a:cmd .
	  \ ' is not defined for this buffer.', 'WarningMsg')"
  endif
endfunction " }}}

function! s:SilentSub(pat, cmd) " {{{
  let _search = @/
  try
    let @/ = a:pat
    silent! exec a:cmd
  finally
    let @/ = _search
  endtry
endfunction " }}}

" Open the source line for the current line from the diff.
function! s:DiffOpenSrc(preview) " {{{
  if s:GetCurrentItem() != ''
    PItemOpen
  endif
  call SaveHardPosition('DiffOpenSrc')
  let orgLine = line('.')
  " Search backwards to find the header for this diff (could contain two
  " depot files or one depot file with or without a local file).
  let filePat = '\zs[^#]\+\%(#\d\+\)\=\ze\%( ([^)]\+)\)\='
  if search('^==== '.filePat.'\%( - '.filePat.'\)\= ====', 'bW')
    let firstFile = matchstr(getline('.'), '^==== \zs'.filePat.
	  \ '\%( - \| ====\)')
    let secondFile = matchstr(getline('.'), ' - '.filePat.' ====',
	  \ strlen(firstFile)+5)
    call RestoreHardPosition('DiffOpenSrc')
    if firstFile == ''
      return
    elseif secondFile == ''
      " When there is only one file, then it is treated as the secondFile.
      let secondFile = firstFile
      let firstFile = ''
    endif

    " Search for the start of the diff segment. We could be in default,
    " context or unified mode.
    if search('^\d\+\%(,\d\+\)\=[adc]\d\+\%(,\d\+\)\=$', 'bW') " default.
      let segStLine = line('.')
      let segHeader = getline('.')
      call RestoreHardPosition('DiffOpenSrc')
      let context = 'depot'
      let regPre = '^'
      if getline('.') =~ '^>'
	let context = 'local'
	let regPre = '[cad]'
	if search('^---$', 'bW') && line('.') > segStLine
	  let segStLine = line('.')
	endif
      endif
      let stLine = matchstr(segHeader, regPre.'\zs\d\+\ze')
      call RestoreHardPosition('DiffOpenSrc')
      let offset = line('.') - segStLine - 1
    elseif search('\([*-]\)\1\1 \d\+,\d\+ \1\{4}', 'bW') " context.
      if getline('.') =~ '^-'
	let context = 'local'
      else
	let context = 'depot'
      endif
      let stLine = matchstr(getline('.'), '^[*-]\{3} \zs\d\+\ze,')
      let segStLine = line('.')
      call RestoreHardPosition('DiffOpenSrc')
      let offset = line('.') - segStLine - 1
    elseif search('^@@ -\=\d\+,\d\+ +\=\d\+,\d\+ @@$', 'bW') " unified
      let segStLine = line('.')
      let segHeader = getline('.')
      call RestoreHardPosition('DiffOpenSrc')
      let context = 'local'
      let sign = '+'
      if getline('.') =~ '^-'
	let context = 'depot'
	let sign = '-'
      endif
      let stLine = matchstr(segHeader, ' '.sign.'\zs\d\+\ze,\d\+')
      let _ma = &l:modifiable
      try
	setl modifiable
	" Count the number of lines that come from the other side (those lines
	"   that start with an opposite sign).
	let _ss = @/ | let @/ = '^'.substitute('-+', sign, '', '') |
	      \ let offOffset = matchstr(GetVimCmdOutput( segStLine.',.s//&/'),
	      \ '\d\+\ze substitutions\? on \d\+ lines\?') + 0 | let @/ = _ss
	call RestoreHardPosition('DiffOpenSrc')
	let offset = line('.') - segStLine - 1 - offOffset
	if offOffset > 0
	  silent! undo
	  call RestoreHardPosition('DiffOpenSrc')
	endif
      finally
	let &l:modifiable = _ma
      endtry
    endif

    let s:errCode = 0
    if context == 'depot' && firstFile == ''
      return
    endif
    if context == 'local'
      let file = secondFile
    else
      let file = firstFile
    endif
    if s:IsDepotPath(file)
      call s:printHdlr(0, a:preview, file)
      let offset = offset + 1 " For print header.
    else
      call s:OpenFile(1, a:preview, file)
    endif
    if s:errCode == 0
      if a:preview
	wincmd P
      endif
      exec (stLine + offset)
      if a:preview
	" Also works as a work-around for the buffer not getting scrolled.
	normal! z.
	wincmd p
      endif
    endif
  endif
endfunction " }}}

""" END: Helper functions }}}


""" BEGIN: Middleware functions {{{

" Filter contents through p4.
function! s:PW(scriptOrigin, ...) range
  exec MakeArgumentString()
  if a:scriptOrigin != 2
    exec "call s:ParseOptions(a:firstline, a:lastline, '++f', " .
	  \ argumentString . ")"
  else
    let s:commandMode = s:CM_FILTER
  endif
  setlocal modifiable
  let retVal = s:PFIF(2, 5, s:p4Command)
  return retVal
endfunction

" Generate raw output into a new window.
function! s:PFRaw(outputType, ...)
  exec MakeArgumentString()
  exec "call s:ParseOptions(1, line('$'), " . argumentString . ")"

  let retVal = s:PFImpl(a:outputType, 1, 0, "")
  return retVal
endfunction

function! s:W(quitWhenDone, commandName, ...)
  exec MakeArgumentString()
  exec "call s:ParseOptionsIF(1, line('$'), 0, a:commandName, " .
	\ argumentString . ")"
  let s:p4CmdOptions = s:p4CmdOptions . ' -i'
  " We can't capture the return value using this syntax.
  1,$call s:PW(2)
  if s:errCode == 0
    setl nomodified
    if a:quitWhenDone
      quit
    endif
  else
    if search('^Change \d\+ created', 'w')
      let newChangeNo = matchstr(getline('.'), '\d\+')
      let _z = @z
      let _undolevels=&undolevels
      let _bufhidden=&l:bufhidden
      try
	silent! normal! 1G"zyG
	undo
	" Make the below changes such a way that they can't be undo. This in a
	"   way, forces Vim to create an undo point, so that user can later
	"   undo and see these changes, with proper change number and status
	"   in place. Unfortunately this has the side effect of loosing the
	"   previous undo history.
	set undolevels=-1
	if search("^Change:\tnew$")
	  call setline('.', "Change:\t" . newChangeNo)
	endif
	if search("^Status:\tnew$")
	  call setline('.', "Status:\tpending")
	endif
	call s:PFUnSetupBufAutoCommand(expand('%'), 'BufUnload')
	setlocal bufhidden=hide
	setl nomodified
	let &undolevels=_undolevels
	silent! 0,$delete _
	silent! put! =@z
	call s:PFSetupForSpec()
      finally
	let @z = _z
	let &undolevels=_undolevels
	let &l:bufhidden=_bufhidden
      endtry
      let b:p4FullCmd = s:CreateFullCmd('-o change ' . newChangeNo)
    endif
  endif
endfunction

function! s:ParseOptionsIF(fline, lline, scriptOrigin, commandName, ...) " range
  exec MakeArgumentString()

  " There are multiple possibilities here:
  "   - scriptOrigin, in which case the commandName contains the name of the
  "	command, but the varArgs also may contain it.
  "   - commandOrigin, in which case the commandName may actually be the
  "	name of the command, or it may be the first argument to p4 itself, in
  "	any case we will let p4 handle the error cases.
  if MvContainsElement(s:p4KnownCmds, ',', a:commandName) && a:scriptOrigin
    exec "call s:ParseOptions(a:fline, a:lline, " .
	  \ argumentString . ")"
    " Add a:commandName only if it doesn't already exist in the var args.
    " Handles cases like "PF help submit" and "PF -c <client> change changeno#",
    "   where the commandName need not be at the starting and there could be
    "   more than one valid commandNames (help and submit).
    if s:p4Command != a:commandName
      exec "call s:ParseOptions(a:fline, a:lline, a:commandName, "
	    \ . argumentString . ")"
    endif
  else
    exec "call s:ParseOptions(a:fline, a:lline, a:commandName, " .
	  \ argumentString . ")"
  endif
endfunction

" PFIF {{{
" The commandName may not be the perforce command when it is not of script
"   origin (called directly from a command), but it should be always command
"   name, when it is script origin.
" scriptOrigin: An integer indicating the origin of the call. 
"   0 - Originated directly from the user, so should redirect to the specific
"	command handler (if exists), after some basic processing.
"   1 - Originated from the script, continue with the full processing.
"   2 - Same as 1 but, avoid parsing arguments (they are already parsed by the
"       caller).
function! s:PFIF(scriptOrigin, outputType, commandName, ...) range
  let output = '' " Used only when mode is s:CM_DISPLAY
  if a:scriptOrigin != 2
    exec MakeArgumentString()
    exec "call s:ParseOptionsIF(a:firstline, a:lastline, "
	  \ . "a:scriptOrigin, a:commandName, " . argumentString . ")"
    if s:commandMode == s:CM_DISPLAY
      let output = DeEscape(s:p4Arguments)
      let s:p4Arguments = ''
      let s:p4WinName = s:MakeWindowName()
    endif
  elseif s:commandMode == s:CM_DISPLAY
    let output = a:1
  endif

  let modifyWindowName = 0
  let outputType = a:outputType
  if a:outputType == -1
    if MvContainsElement(s:outputType20Cmds, ',', s:p4Command)
      let outputType = 20
    else
      let outputType = 0
    endif
  endif

  let outputIdx = MvIndexOfPattern(s:p4Options, s:SPACE_AS_SEP,
	\ '+o\s\+\d\+', ' ') " Searches including output mode.
  if outputIdx != -1
    let outputType = MvElementAt(s:p4Options, s:SPACE_AS_SEP, outputIdx + 1,
	  \ ' ') + 0
  endif
  if ! a:scriptOrigin
    if exists('*s:{s:p4Command}Hdlr')
      return s:{s:p4Command}Hdlr(1, outputType, a:commandName)
    endif
  endif
 
  let dontProcess = MvContainsElement(s:p4CmdOptions, s:SPACE_AS_SEP, '+p', ' ')
  " If there is a confirm message for this command, then first prompt user.
  let dontConfirm = MvContainsElement(s:p4CmdOptions, s:SPACE_AS_SEP, '+y', ' ')
  if exists('s:confirmMsgs{s:p4Command}') && ! dontConfirm
    let option = s:ConfirmMessage(s:confirmMsgs{s:p4Command}, "&Yes\n&No", 2,
	  \ "Question")
    if option == 2
      let s:errCode = 2
      return ''
    endif
  endif

  if MvContainsElement(s:limitListCmds, ',', s:p4Command) &&
	\ ! MvContainsElement(s:p4CmdOptions, s:SPACE_AS_SEP, '-m', ' ') &&
	\ s:defaultListSize > -1
    let s:p4CmdOptions = '-m ' . s:defaultListSize . ' ' . s:p4CmdOptions
    let modifyWindowName = 1
  endif
  if MvContainsElement(s:diffCmds, ',', s:p4Command) &&
	\ ! MvContainsPattern(s:p4CmdOptions, s:SPACE_AS_SEP, '-d[cdnsu]', ' ')
	\ && s:defaultDiffOptions != ""
    let s:p4CmdOptions = s:defaultDiffOptions . ' ' . s:p4CmdOptions
    let modifyWindowName = 1
  endif

  " Process p4Arguments.
  if ! dontProcess && s:p4Arguments == "" && s:commandMode == s:CM_RUN
    if (MvContainsElement(s:askUserCmds, ',', s:p4Command) &&
	  \ ! MvContainsElement(s:p4CmdOptions, s:SPACE_AS_SEP, '-i', ' ')) ||
	  \ MvContainsElement(s:p4CmdOptions, s:SPACE_AS_SEP, '+P', ' ')
      if MvContainsElement(s:genericPromptCmds, ',', s:p4Command)
	let prompt = 'Enter arguments for ' . s:p4Command . ': '
      else
	let prompt = "Enter the " . s:p4Command . " name: "
      endif
      let additionalArg = s:PromptFor(0, s:useGUIDialogs, prompt, '')
      if additionalArg == ""
	if MvContainsElement(s:genericPromptCmds, ',', s:p4Command)
	  call s:EchoMessage('Arguments required for '. s:p4Command, 'Error')
	else
	  call s:EchoMessage(substitute(s:p4Command, "^.", '\U&', '') .
		\ " name required.", 'Error')
	endif
	let s:errCode = 2
        return ''
      endif
      let s:p4Arguments =  additionalArg
    elseif ! dontProcess &&
	  \ ! MvContainsElement(s:curFileNotDefCmds, ',', s:p4Command) &&
	  \ ! MvContainsElement(s:nofileArgsCmds, ',', s:p4Command)
      let s:p4Arguments = s:EscapeFileName(expand('%'))
      let modifyWindowName = 1
    endif
  elseif ! dontProcess && match(s:p4Arguments, '[#@&]') != -1
    " If there is an argument without a filename, then assume it is the current
    "	file.
    " Pattern is the start of line or whitespace followed by an unprotected
    "	[#@&] with a revision/codeline specifier and then again followed by
    "	end of line or whitespace.
    let s:p4Arguments = substitute(s:p4Arguments,
          \ '\%(^\|\%('.s:SPACE_AS_SEP.'\)\+\)\@<=' .
	  \ '\\\@<!\%(\\\\\)*\(\%([#@&]\%([-+]\?\d\+\|\S\+\)\)\+\)' . 
	  \ '\%(\%('.s:SPACE_AS_SEP.'\)\+\|$\)\@=',
	  \ '\=s:EscapeFileName(expand("%")) . submatch(1) . submatch(2)', 'g')

    " Adjust the revisions for offsets.
    call s:PushP4Context()
    " Pattern is a series of non-space chars or protected spaces (filename)
    "	followed by the revision specifier.
    let p4Arguments = substitute(s:p4Arguments,
	  \ '\(\%(\S\|\\\@<!\%(\\\\\)*\\ \)\+\)[\\]*#\([-+]\d\+\)',
	  \ '\=submatch(1) . "#" . ' .
	  \ 's:AdjustRevision(submatch(1), submatch(2))', 'g')
    call s:PopP4Context()
    let s:p4Arguments = p4Arguments
    if s:errCode != 0
      return ''
    endif

    " Unprotected '&'.
    if match(s:p4Arguments, '\\\@<!\%(\\\\\)*&') != -1
      " Pattern is a series of non-space chars or protected spaces (filename)
      "	  including the revision specifier, if any, followed by the alternative
      "	  codeline specifier.
      let s:p4Arguments = substitute(s:p4Arguments,
	    \ '\(\%([^ ]\|\\\@<!\%(\\\\\)*\\ \)\+' .
	    \ '\%([\\]*[#@]\%(-\?\d\+\|\w\+\)\)\?\)\\\@<!\%(\\\\\)*&\(\w\+\)',
	    \ '\=s:PFGetAltFiles(submatch(2), submatch(1))', 'g')
    endif
    let modifyWindowName = 1
  endif

  let testMode = 0
  if MvContainsElement(s:p4Options, s:SPACE_AS_SEP, '+d', ' ')
    let testMode = 1 " Ignore.
  elseif MvContainsElement(s:p4Options, s:SPACE_AS_SEP, '+t', ' ')
    let testMode = 2 " Debug.
  endif

  " Remove all the built-in options.
  let _p4Options = s:p4Options
  let s:p4Options = substitute(s:p4Options, '+\S\+\%(\s\+[^-+]\+\|\s\+\)\?',
	\ '', 'g')
  let _p4CmdOptions = s:p4CmdOptions
  let s:p4CmdOptions = substitute(s:p4CmdOptions,
	\ '+\S\+\%(\s\+[^-+]\+\|\s\+\)\?', '', 'g')
  if s:p4Options != _p4Options || s:p4CmdOptions != _p4CmdOptions
    let modifyWindowName = 1
  endif
  if MvContainsElement(s:diffCmds, ',', s:p4Command)
    " Remove the dummy option, if exists (see |perforce-default-diff-format|).
    let s:p4CmdOptions = MvRemoveElement(s:p4CmdOptions, s:SPACE_AS_SEP, '-dd',
	  \ ' ')
  endif

  if s:p4Command == 'help'
    " Use simple window name for all the help commands.
    let s:p4WinName = s:helpWinName
  elseif modifyWindowName
    let s:p4WinName = s:MakeWindowName() 
  endif

  " If the command is a built-in command, then don't pass it to external p4.
  if exists('s:builtinCmdHandler{s:p4Command}')
    let s:errCode = 0
    return {s:builtinCmdHandler{s:p4Command}}()
  endif

  let specMode = 0
  if MvContainsElement(s:specCmds, ',', s:p4Command)
    if match(s:p4CmdOptions, '-d\>') == -1
	  \ && ! MvContainsElement(s:noOutputCmds, ',', s:p4Command)
      let s:p4CmdOptions = "-o " . s:p4CmdOptions
    endif

    " Go into specification mode only if the user intends to edit the output.
    if ((s:p4Command == 'submit' &&
	  \ ! MvContainsElement(s:p4CmdOptions, s:SPACE_AS_SEP, '-c', ' ')) ||
      \ (! MvContainsElement(s:specOnlyCmds, ',', s:p4Command) &&
	  \ ! MvContainsElement(s:p4CmdOptions, s:SPACE_AS_SEP, '-d', ' '))) &&
     \ outputType == 0
      let specMode = 1
    endif
  endif
  
  let navigateCmd = 0
  if MvContainsElement(s:navigateCmds, ',', s:p4Command)
    let navigateCmd = 1
  endif

  let retryCount = 0
  " CAUTION: This is like a do..while loop, but not exactly the same, be
  " careful using continue, the counter will not get incremented.
  while 1
    " Save the context, as the below call may result in a reentrant call to
    "	this function.
    call s:PushP4Context()
    let retVal = s:PFImpl(outputType, (testMode != 2 ? ! navigateCmd : 2),
	  \ testMode, output)
    call s:PopP4Context()

    " Everything else in this loop is for password support.
    if s:errCode == 0
      break
    else
      let output = retVal
      if output == ''
	let output = getline(1)
      endif
      if output =~ 'Perforce password (P4PASSWD) invalid or unset.'
	let g:p4Password = inputsecret("Password required for user " . s:p4User
	      \ . ": ", s:p4Password)
	if g:p4Password == s:p4Password
	  unlet g:p4Password
	  break
	endif
	"call s:PushP4Context()
	call s:Initialize()
	"call s:PopP4Context()
      else
	break
      endif
    endif
    let retryCount = retryCount + 1
    if retryCount > 2
      break
    endif
  endwhile
  " We are doing checktime now for all commands, right in PFImpl() itself.
  "if MvContainsElement(s:checktimeReqCmds, ',', s:p4Command)
  "  checktime
  "endif
  if s:errCode != 0
    return ''
  endif

  if s:StartBufSetup(outputType)
    " If this command has a handler for the individual items, then enable the
    " item selection commands.
    if s:getCommandItemHandler(0, s:p4Command, '') != ""
      call s:SetupSelectItem()
    endif

    if !MvContainsElement(s:ftNotPerforceCmds, ',', s:p4Command)
      setlocal ft=perforce
    endif

    if MvContainsElement(s:filelistCmds, ',', s:p4Command)
      call s:SetupFileBrowse(outputType)
    endif

    if s:newWindowCreated
      if specMode
	let argStr = ''
	if s:p4Options !~ s:EMPTY_STR
	  let argStr = CreateArgString(s:p4Options, s:SPACE_AS_SEP) . ','
	endif
	" It is not possible to have an s:p4Command which is in s:p4KnownCmds
	"	  and still not be the actual intended command.
	if MvContainsElement(s:p4KnownCmds, ',', s:p4Command)
	  let argStr = argStr . "'" . s:p4Command . "', "
	else
	  " FIXME: Why am I using b:p4Command instead of s:p4Command here ???
	  let argStr = argStr . "'" . b:p4Command . "', "
	endif
	if s:p4CmdOptions !~ s:EMPTY_STR
	  let argStr = argStr . CreateArgString(s:p4CmdOptions, ' ') . ', '
	endif
	exec 'command! -buffer -nargs=* W :call <SID>W(0, ' . argStr .
	      \ '<f-args>)'
	exec 'command! -buffer -nargs=* WQ :call <SID>W(1, ' . argStr .
	      \ '<f-args>)'
	call s:EchoMessage("When done, save " . s:p4Command .
	      \ " spec by using :W or :WQ command. Undo on errors.", 'None')
	call s:PFSetupForSpec()
      else " Define q to quit the read-only perforce windows (David Fishburn)
	nnoremap <buffer> q <C-W>q
      endif
    endif

    if navigateCmd
      nnoremap <silent> <buffer> <C-O> :call <SID>NavigateBack()<CR>
      nnoremap <silent> <buffer> <BS> :call <SID>NavigateBack()<CR>
      nnoremap <silent> <buffer> <Tab> :call <SID>NavigateForward()<CR>
    endif

    call s:EndBufSetup(outputType)
  endif

  return retVal
endfunction " PFIF }}}

""" START: Adopted from Tom's perforce plugin. {{{

"---------------------------------------------------------------------------
" Produce string for ruler output
function! s:P4RulerStatus()
  if exists('b:p4RulerStr') && b:p4RulerStr != ""
    return b:p4RulerStr
  endif
  if !exists('b:p4FStatDone') || !b:p4FStatDone
    return ''
  endif

  "let b:p4RulerStr = '[p4 '
  let b:p4RulerStr = '['
  if exists('b:p4RulerErr') && b:p4RulerErr != ''
    let b:p4RulerStr = b:p4RulerStr . b:p4RulerErr
  elseif !exists('b:p4HaveRev')
    let b:p4RulerStr = ''
  elseif b:p4Action == ''
    if b:p4OtherOpen == ''
      let b:p4RulerStr = b:p4RulerStr . 'unopened'
    else
      let b:p4RulerStr = b:p4RulerStr . b:p4OtherOpen . ':' . b:p4OtherAction
    endif
  else
    if b:p4Change == 'default'
      let b:p4RulerStr = b:p4RulerStr . b:p4Action
    else
      let b:p4RulerStr = b:p4RulerStr . b:p4Action . ':' . b:p4Change
    endif
  endif
  if exists('b:p4HaveRev') && b:p4HaveRev != ''
    let b:p4RulerStr = b:p4RulerStr . ' #' . b:p4HaveRev . '/' . b:p4HeadRev
  endif

  if b:p4RulerStr != ''
    let b:p4RulerStr = b:p4RulerStr . ']'
  endif
  return b:p4RulerStr
endfunction


function! s:GetClientInfo()
  let infoStr = s:PFIF(0, 4, "info")
  if s:errCode != 0
    return s:SyntaxError(v:errmsg)
  endif
  let s:clientRoot = CleanupFileName(s:StrExtract(infoStr,
	\ '\CClient root: \f\+', 13))
endfunction


" Get/refresh filestatus for the specified buffer with optimizations.
function! s:GetFileStatus(buf, refresh)
  " If it is not a normal buffer, then ignore it.
  if &buftype != ''
    return ""
  endif

  if ! type(a:buf) " If number.
    let bufNr = (a:buf == 0) ? bufnr('%') : a:buf
  else
    let bufNr = bufnr(a:buf)
  endif
  if bufNr == -1 || (!a:refresh && s:optimizeActiveStatus &&
	\ getbufvar(bufNr, "p4FStatDone"))
    return ""
  endif

  " This is an optimization by restricting status to the files under the
  "   client root only.
  if !s:IsFileUnderDepot(expand('#'.bufNr))
    return ""
  endif

  return s:GetFileStatusImpl(bufNr)
endfunction


function! s:ResetFileStatusForBuffer(bufNr)
  call setbufvar(a:bufNr, 'p4FStatDone', 0)
endfunction


"---------------------------------------------------------------------------
" Obtain file status information
" TODO:
"   By running fstat with the depot file would generate more information, but
"     that would mean I should know the branch mapping. Unless I have a way to
"     cache the branch mappings, running 'where' command everytime will be too
"     slow.
function! s:GetFileStatusImpl(bufNr)
  if bufname(a:bufNr) == ""
    return ""
  endif
  let fileName = fnamemodify(bufname(a:bufNr), ':p')
  let bufNr = a:bufNr
  " If the filename matches with one of the ignore patterns, then don't do
  " status.
  if s:ignoreDefPattern != '' && match(fileName, s:ignoreDefPattern) != -1
    return ""
  endif
  if s:ignoreUsrPattern != '' && match(fileName, s:ignoreUsrPattern) != -1
    return ""
  endif

  call setbufvar(bufNr, 'p4RulerStr', '') " Let this be reconstructed.

  let fileStatusStr = s:PFIF(1, 4, 'fstat', fileName)
  call setbufvar(bufNr, 'p4FStatDone', '1')

  if s:errCode != 0
    call setbufvar(bufNr, 'p4RulerErr', "<ERROR>")
    return ""
  endif

  if match(fileStatusStr, ' - file(s) not in client view\.') >= 0
    call setbufvar(bufNr, 'p4RulerErr', "<Not In View>")
    " Required for optimizing out in future runs.
    call setbufvar(bufNr, 'p4HeadRev', '')
    return ""
  elseif match(fileStatusStr, ' - no such file(s).') >= 0
    call setbufvar(bufNr, 'p4RulerErr', "<Not In Depot>")
    " Required for optimizing out in future runs.
    call setbufvar(bufNr, 'p4HeadRev', '')
    return ""
  else
    call setbufvar(bufNr, 'p4RulerErr', '')
  endif

  call setbufvar(bufNr, 'p4HeadRev',
	\ s:StrExtract(fileStatusStr, '\CheadRev [0-9]\+', 8))
  call setbufvar(bufNr, 'p4DepotFile',
	\ s:StrExtract(fileStatusStr, '\CdepotFile \f\+', 10))
  call setbufvar(bufNr, 'p4ClientFile',
	\ s:StrExtract(fileStatusStr, '\CclientFile \f\+', 11))
  call setbufvar(bufNr, 'p4HaveRev',
	\ s:StrExtract(fileStatusStr, '\ChaveRev [0-9]\+', 8))
  call setbufvar(bufNr, 'p4Action',
	\ s:StrExtract(fileStatusStr, '\Caction [^[:space:]]\+', 7))
  call setbufvar(bufNr, 'p4OtherOpen',
	\ s:StrExtract(fileStatusStr, '\CotherOpen0 [^[:space:]@]\+', 11))
  call setbufvar(bufNr, 'p4OtherAction',
	\ s:StrExtract(fileStatusStr, '\CotherAction0 [^[:space:]@]\+', 13))
  call setbufvar(bufNr, 'p4Change',
	\ s:StrExtract(fileStatusStr, '\Cchange [^[:space:]]\+', 7))

  return fileStatusStr
endfunction


function! s:StrExtract(str, pat, pos)
  let part = matchstr(a:str, a:pat)
  let part = strpart(part, a:pos)
  return part
endfunction


function! s:AdjustRevision(file, adjustment)
  let s:errCode = 0
  let revNum = a:adjustment
  if revNum =~ '[-+]\d\+'
    let revNum = substitute(revNum, '^+', '', '')
    if getbufvar(a:file, 'p4HeadRev') == ''
      " If fstat is not done yet, do it now.
      call s:GetFileStatus(a:file, 1)
      if getbufvar(a:file, 'p4HeadRev') == ''
	call s:EchoMessage("Current revision is not available. " .
	      \ "To be able to use negative revisions, see help on " .
	      \ "'perforce-active-status'.", 'Error')
	let s:errCode = 1
	return -1
      endif
    endif
    let revNum = getbufvar(a:file, 'p4HaveRev') + revNum
    if revNum < 1
      call s:EchoMessage("Not that many revisions available. Try again " .
	    \ "using PRefreshFileStatus command.", 'Error')
      let s:errCode = 1
      return -1
    endif
  endif
  return revNum
endfunction

"---------------------------------------------------------------------------
" One of a set of functions that returns fields from the p4 fstat command
function! s:IsCurrent()
  let revdiff = b:p4HeadRev - b:p4HaveRev
  if revdiff == 0
    return 0
  else
    return -1
  endif
endfunction


function! s:CheckOutFile()
  if ! s:promptToCheckout || ! s:IsFileUnderDepot(expand("%"))
    return
  endif

  if filereadable(expand("%")) && ! filewritable(expand("%"))
    let option = s:ConfirmMessage("Readonly file, do you want to checkout " .
          \ "from perforce?", "&Yes\n&No", s:checkOutDefault, "Question")
    if option == 1
      call s:PFIF(1, 21, 'edit')
      if ! s:errCode
	" You need to explicitly execute this autocommand to get the change
	"   detected and for other events (such as BufRead) to get fired. This
	"   was suggested by Bram.
	" The currentCommand by now must have got reset, so we need to
	"   explicitly set it and finally reset it.
	let currentCommand = s:currentCommand
	try
	  let s:currentCommand = 'edit'
	  exec "doautocmd FileChangedShell " . expand('%')
	finally
	  let s:currentCommand = currentCommand
	endtry
      endif
    endif
  endif
endfunction


function! s:FileChangedShell()
  if s:activeStatusEnabled
    call s:ResetFileStatusForBuffer(expand("<abuf>") + 0)
  endif
  let autoread = -1
  if MvContainsElement(s:autoreadCmds, ',', s:currentCommand)
    let autoread = s:autoread
  endif
  return autoread
endfunction
""" END: Adapted from Tom's perforce plugin. }}}

""" END: Middleware functions }}}


""" BEGIN: Infrastructure {{{

" Assumes that the arguments are already parsed and are ready to be used in
"   the script variables.
" Low level interface with the p4 command.
" outputType (string):
"   0 - Execute p4 and place the output in a new window.
"   1 - Same as above, but use preview window.
"   2 - Execute p4 and show the output in a dialog for confirmation.
"   3 - Execute p4 and echo the output.
"   4 - Execute p4 and return the output.
"   5 - Execute p4 no output expected. Essentially same as 4 when the current
"	commandMode doesn't produce any output, just for clarification.
"  20 - Execute p4 and if the output is less than s:maxLinesInDialog number of
"	lines, display a dialog (mode 2), otherwise display in a new window
"	(mode 0)
"  21 - Same as 20, use mode 1 instead of 0.
" clearBuffer (boolean): If the buffer contents should be cleared before
"     adding the new output.
" testMode (number):
"   0 - Run normally.
"   1 - debugging, display the command-line instead of the actual output..
"   2 - testing, ignore.
" Returns the output if available. If there is any error, the error code will
"   be available in s:errCode variable.
function! s:PFImpl(outputType, clearBuffer, testMode, output) " {{{
  " FIXME: Work-around.
  let _newWindowCreated = s:newWindowCreated
  let s:newWindowCreated = 0
  try " [-2f]
  let s:recLevel = s:recLevel + 1

  let outputType = a:outputType
  let s:errCode = 0

  let fullCmd = ''
  if s:commandMode != s:CM_DISPLAY
    let fullCmd = s:MakeP4Cmd()
  endif
  " save the name of the current file.
  let p4CurFileName = expand("%")

  " If the output has to be shown in a window, position cursor appropriately,
  " creating a new window if required.
  let v:errmsg = ""
  " Ignore outputType in this case.
  if s:commandMode != s:CM_PIPE && s:commandMode != s:CM_FILTER
    if outputType == 0 || outputType == 1
      call s:GotoWindow(outputType, a:clearBuffer, p4CurFileName)
    endif
  endif

  let output = ""
  if ! a:testMode && s:errCode == 0
    let s:currentCommand = ''
    " Make sure all the already existing changes are detected. We don't have
    "	s:currentCommand set here, so the user will get an appropriate prompt.
    checktime
    let s:currentCommand = s:p4Command
    try
      if s:commandMode == s:CM_RUN
	" If we are placing the output in a new window, then we should avoid
	"   system() for performance reasons, imagine doing a 'print' on a
	"   huge file.
	" These two outputType's correspond to placing the output in a window.
	if outputType != 0 && outputType != 1
	  let output = s:System(fullCmd, a:outputType)
	else
	  exec '.call s:Filter(fullCmd, a:outputType, 1)'
	  let output = ""
	endif
      elseif s:commandMode == s:CM_FILTER
	exec s:filterRange . 'call s:Filter(fullCmd, a:outputType, 1)'
      elseif s:commandMode == s:CM_PIPE
	exec s:filterRange . 'call s:Filter(fullCmd, a:outputType, 2)'
      elseif s:commandMode == s:CM_DISPLAY
	let output = a:output
      endif
      " Detect any new changes to the loaded buffers.
      " CAUTION: This actually results in a reentrant call back to this
      "   function, but our Push/Pop mechanism for the context should take
      "   care of it.
      checktime
    finally
      let s:currentCommand = ''
    endtry
  elseif a:testMode != 2
    let output = fullCmd
  endif

  if s:errCode == 0
    if outputType == 20 || outputType == 21
      let nLines = strlen(substitute(output, "[^\n]", "", "g"))
      if nLines > s:maxLinesInDialog
	" Open the window now.
	let outputType = outputType - 20
	call s:GotoWindow(outputType, a:clearBuffer, p4CurFileName)
      else
	let outputType = 2
      endif
    endif

    let v:errmsg = ""
    " If we have non-null output, then handling it is still pending.
    if output != ''
      " If the output has to be shown in a dialog, bring up a dialog with the
      "   output, otherwise show it in the current window.
      if outputType == 0 || outputType == 1
	silent! put! =output
      elseif outputType == 2
	call s:ConfirmMessage(output, "OK", 1, "Info")
      elseif outputType == 3
	echo output
      elseif outputType == 4
	" Do nothing we will just return it.
      endif
    endif
  endif
  return output

  finally " [+2s]
    if s:newWindowCreated
      call s:PFSetupBuf(expand('%'))
      let b:p4Command = s:p4Command
      let b:p4Options = s:p4Options
      let b:p4FullCmd = fullCmd
      if outputType == 1
	wincmd p
      endif
    endif
    if s:recLevel > 1
      let s:newWindowCreated = _newWindowCreated
    endif
    let s:recLevel = s:recLevel - 1
  endtry
endfunction " }}}

" External command execution {{{

let s:ST_WIN_CMD = 0 | let s:ST_WIN_SH = 1 | let s:ST_UNIX = 2
function! s:GetShellEnvType()
  " When 'shellslash' option is available, then the platform must be one of
  "	those that support '\' as a pathsep.
  if exists('+shellslash')
    if stridx(&shell, 'cmd.exe') != -1 ||
	  \ stridx(&shell, 'command.com') != -1
      return s:ST_WIN_CMD
    else
      return s:ST_WIN_SH
    endif
  else
    return s:ST_UNIX
  endif
endfunction

function! s:System(fullCmd, outputType)
  return s:ExecCmd(a:fullCmd, a:outputType, 0)
endfunction

function! s:Filter(fullCmd, outputType, mode) range
  " For command-line, we need to protect '%', '#' and '!' chars, even if they
  "   are in quotes, to avoid getting expanded by Vim before invoking external
  "   cmd.
  let fullCmd = Escape(a:fullCmd, '%#!')
  exec a:firstline.",".a:lastline.
	\ "call s:ExecCmd(fullCmd, a:outputType, a:mode)"
endfunction

function! s:ExecCmd(fullCmd, outputType, mode) range
  let shellEnvType = s:GetShellEnvType()
  let v:errmsg = ''
  let output = ''
  try
    " Assume the shellredir is set correctly to capture the error messages.
    if a:mode == 0
      let output = system(a:fullCmd)
    elseif a:mode == 1
      silent! exec a:firstline.",".a:lastline."!".a:fullCmd
    else
      silent! exec a:firstline.",".a:lastline."write !".a:fullCmd
    endif

    call s:CheckShellError(output, a:outputType)
    return output
  catch /^Vim\%((\a\+)\)\=:E/ " 48[2-5]
    let v:errmsg = substitute(v:exception, '^[^:]\+:', '', '')
    call s:CheckShellError(output, a:outputType)
  catch /^Vim:Interrupt$/
    let s:errCode = 1
  catch " Ignore.
  endtry
endfunction

" Creates the actual p4 command that can be executed using system().
function! s:MakeP4Cmd()
  let addOptions = s:defaultOptions . ' '
  if s:p4Client != "" &&
	\ !MvContainsElement(s:p4Options, s:SPACE_AS_SEP, '-c', ' ')
    let addOptions = addOptions . '-c ' . s:p4Client . ' '
  endif
  if s:p4User != "" &&
	\ !MvContainsElement(s:p4Options, s:SPACE_AS_SEP, '-u', ' ')
    let addOptions = addOptions . '-u ' . s:p4User . ' '
  endif
  if s:p4Port != "" &&
	\ !MvContainsElement(s:p4Options, s:SPACE_AS_SEP, '-p', ' ')
    let addOptions = addOptions . '-p ' . s:p4Port . ' '
  endif
  if s:p4Password != "" &&
	\ !MvContainsElement(s:p4Options, s:SPACE_AS_SEP, '-P', ' ')
    let addOptions = addOptions . '-P ' . s:p4Password
  endif
  
  return s:CreateFullCmd(s:MakeP4CmdString(addOptions))
endfunction

" - For windoze+native, use double-quotes to sorround the arguments and for
"   embedded double-quotes, just double them.
" - For windoze+sh, use single-quotes to sorround the aruments and for embedded
"   single-quotes, just replace them with '""'""' (if 'shq' or 'sxq' is a
"   double-quote) and just '"'"' otherwise. Embedded double-quotes also need
"   to be doubled.
" - For Unix+sh, use single-quotes to sorround the arguments and for embedded
"   single-quotes, just replace them with '"'"'. 
function! s:CreateFullCmd(cmd)
  let fullCmd = a:cmd
  " I am only worried about passing arguments with spaces as they are to the
  "   external commands, I currently don't care about back-slashes
  "   (backslashes are normally expected only on windows when 'shellslash'
  "   option is set, but even then the 'shell' is expected to take care of
  "   them.). However, for cygwin bash, there is a loss of one level
  "   of the back-slashes somewhere in the chain of execution (most probably
  "   between CreateProcess() and cygwin?), so we need to double them.
  let shellEnvType = s:GetShellEnvType()
  if shellEnvType == s:ST_WIN_CMD
    let quoteChar = '"'
    " Escape the existing double-quotes (by doubling them).
    let fullCmd = substitute(fullCmd, '"', '""', 'g')
  else
    let quoteChar = "'"
    if shellEnvType == s:ST_WIN_SH
      " Escape the existing double-quotes (by doubling them).
      let fullCmd = substitute(fullCmd, '"', '""', 'g')
    endif
    " Take care of existing single-quotes (by exposing them, as you can't have
    "	single-quotes inside a single-quoted string).
    if &shellquote == '"' || &shellxquote == '"'
      let squoteRepl = "'\"\"'\"\"'"
    else
      let squoteRepl = "'\"'\"'"
    endif
    let fullCmd = substitute(fullCmd, "'", squoteRepl, 'g')
  endif

  " Now sorround the arguments with quotes, considering the protected
  "   spaces.
  let fullCmd = substitute(fullCmd,
	\ '\%(^\)\@<!\(\%([^ ]\|\\\@<=\%(\\\\\)* \)\+\)',
	\ quoteChar.'\1'.quoteChar, 'g')
  " We delay adding pipe part so that we can avoid the above processing.
  let fullCmd = fullCmd . ' ' . s:p4Pipe 
  let fullCmd = UnEscape(fullCmd, ' ') " Unescape just the spaces.
  let fullCmd = s:p4CommandPrefix . s:p4CmdPath . ' ' . fullCmd
  if shellEnvType == s:ST_WIN_SH && &shell =~ '\<bash\>'
    let fullCmd = substitute(fullCmd, '\\', '\\\\', 'g')
  endif
  let g:p4FullCmd = fullCmd " Debug.
  return fullCmd
endfunction

" Generates a command string as the user typed, using the script variables.
function! s:MakeP4CmdString(p4DefOptions)
  let opts = ''
  if s:p4Options !~ s:EMPTY_STR
    let opts = s:p4Options . ' '
  elseif exists('b:p4Options') && b:p4Options !~ s:EMPTY_STR
    let opts = b:p4Options . ' '
  endif
  " If there are duplicates, perfore takes the first option, so let opts come
  "   before p4DefOptions.
  let cmdStr = opts . a:p4DefOptions . ' ' . s:p4Command . ' ' . s:p4CmdOptions
	\ . ' ' . s:p4Arguments
  " Consolidate multiple consecutive spaces into one. 
  let cmdStr = s:CleanSpaces(cmdStr)
  " Remove the protection from the characters that we treat specially (Note: #
  "   and % are treated specially by Vim command-line itself, and the
  "   back-slashes are removed even before we see them.)
  let cmdStr = UnEscape(cmdStr, '&')
  return cmdStr
endfunction

" In case of outputType == 4, it assumes the caller wants to see the output as
" it is, so no error message is given. The caller is expected to check for
" error code, though.
function! s:CheckShellError(output, outputType)
  if (v:shell_error != 0 || v:errmsg != '') && a:outputType != 4
    let output = "There was an error executing external p4 command.\n"
    if v:errmsg != ''
      let output = output . "\n" . "errmsg = " . v:errmsg
    endif
    " When commandMode == s:CM_RUN, the error message may already be there in
    "	the current window.
    if a:output != ''
      let output = output . "\n" . a:output
    elseif a:output == "" &&
	  \ (s:commandMode == s:CM_RUN && line('$') == 1 && col('$') == 1)
      let output = output . "\n" .
            \ "Check if your 'shellredir' option captures error messages."
    endif
    call s:ConfirmMessage(output, "OK", 1, "Error")
  endif
  let s:errCode = v:shell_error
  return v:shell_error
endfunction

" External command execution }}}

" Push/Pop/Peek context {{{
function! s:PushP4Context()
  let contextString = ""
  let contextString = MvAddElement(contextString, s:p4ContextItemSeparator,
	\ s:p4Options)
  let contextString = MvAddElement(contextString, s:p4ContextItemSeparator,
	\ s:p4Command)
  let contextString = MvAddElement(contextString, s:p4ContextItemSeparator,
	\ s:p4CmdOptions)
  let contextString = MvAddElement(contextString, s:p4ContextItemSeparator,
	\ s:p4Arguments)
  let contextString = MvAddElement(contextString, s:p4ContextItemSeparator,
	\ s:p4Pipe)
  let contextString = MvAddElement(contextString, s:p4ContextItemSeparator,
	\ s:p4WinName)
  let contextString = MvAddElement(contextString, s:p4ContextItemSeparator,
	\ s:commandMode)
  let contextString = MvAddElement(contextString, s:p4ContextItemSeparator,
	\ s:filterRange)
  "let contextString = MvAddElement(contextString, s:p4ContextItemSeparator,
  "	\ s:newWindowCreated)
  let s:p4Contexts = MvAddElement(s:p4Contexts, s:p4ContextSeparator,
	\ contextString)
endfunction

function! s:PeekP4Context()
  call s:PopP4ContextImpl(1)
endfunction

function! s:PopP4Context()
  call s:PopP4ContextImpl(0)
endfunction

function! s:PopP4ContextImpl(peek)
  let nContexts = MvNumberOfElements(s:p4Contexts, s:p4ContextSeparator)
  if nContexts <= 0
    echoerr "PopP4Context: Contexts stack is empty"
    return
  endif
  let contextString = MvElementAt(s:p4Contexts, s:p4ContextSeparator,
	\ nContexts - 1)
  if !a:peek
    let s:p4Contexts = MvRemoveElementAt(s:p4Contexts, s:p4ContextSeparator,
	  \ nContexts - 1)
  endif

  call MvIterCreate(contextString, s:p4ContextItemSeparator, "PopP4Context")
  let s:p4Options = MvIterNext("PopP4Context")
  let s:p4Command = MvIterNext("PopP4Context")
  let s:p4CmdOptions = MvIterNext("PopP4Context")
  let s:p4Arguments = MvIterNext("PopP4Context")
  let s:p4Pipe = MvIterNext("PopP4Context")
  let s:p4WinName = MvIterNext("PopP4Context")
  let s:commandMode = MvIterNext("PopP4Context")
  let s:filterRange = MvIterNext("PopP4Context")
  "let s:newWindowCreated = MvIterNext("PopP4Context")
  call MvIterDestroy("PopP4Context")
endfunction
" Push/Pop/Peek context }}}

""" BEGIN: Argument parsing {{{
function! s:ResetP4Vars()
  " Syntax is:
  "   PF <p4Options> <p4Command> <p4CmdOptions> <p4Arguments> | <p4Pipe>
  " Ex: PF -c hari integrate -b branch -s <fromFile> <toFile>
  let s:p4Options = ""
  let s:p4Command = ""
  let s:p4CmdOptions = ""
  let s:p4Arguments = ""
  let s:p4Pipe = ""
  let s:p4WinName = ""
  " commandMode:
  "   run - Execute p4 using system() or its equivalent.
  "   filter - Execute p4 as a filter for the current window contents. Use
  "	       commandPrefix to restrict the filter range.
  "   display - Don't execute p4. The output is already passed in.
  let s:commandMode = "run"
  let s:filterRange = ""

  " The command that is currently being executed. Used to determine autoread.
  let s:currentCommand = ''
  let s:errCode = 0
  " FIXME: Strictly speaking this should be part of the context, but
  "   currently, the context gets generated by the ParseOptions() function,
  "   which doesn't know about this. For now, this is being worked-around by
  "   explicitly saving and restoring everytime in PFIF() function (before the
  "   ParseOptions() can get a chance to overwrite it).
  let s:newWindowCreated = 0
endfunction
call s:ResetP4Vars() " Let them get initialized the first time.

" Parses the arguments into 4 parts, "options to p4", "p4 command",
" "options to p4 command", "actual arguments". Also generates the window name.
function! s:ParseOptions(fline, lline, ...) " range
  call s:ResetP4Vars()
  if a:0 == 0
    return
  endif

  let s:filterRange = a:fline . ',' . a:lline
  let i = 1
  let prevArg = ""
  let curArg = ""
  let s:pendingPipeArg = ''
  while i <= a:0
    try " Just for the sake of loop variables. [-2f]

    if s:pendingPipeArg != ''
      let curArg = s:pendingPipeArg
      let s:pendingPipeArg = ''
    elseif s:p4Pipe == ''
      let curArg = a:{i}
      let pipeIndex = match(curArg, '\\\@<!\%(\\\\\)*\zs|')
      if pipeIndex != -1
	let pipePart = strpart(curArg, pipeIndex)
	let p4Part = strpart(curArg, 0, pipeIndex)
	if p4Part !~ s:EMPTY_STR
	  let curArg = p4Part
	  let s:pendingPipeArg = pipePart
	else
	  let curArg = pipePart
	endif
      endif
    else
      let curArg = a:{i}
    endif

    " Escape the embedded spaces such that only the spaces between them are
    " left unprotected.
    let curArg = s:Escape(curArg)

    if curArg =~ '^|' || s:p4Pipe != ''
      let s:p4Pipe = s:p4Pipe . ' ' . curArg
      continue
    endif

    if ! s:IsAnOption(curArg) " If not an option.
      if s:p4Command == "" && MvContainsPattern(s:p4KnownCmds, ',', curArg)
	" If the previous one was an option to p4 that takes in an argument.
	if prevArg =~ '^-[cCdHLpPux]$' || prevArg =~ '^+o$' " See :PH usage.
	  let s:p4Options = s:p4Options . ' ' . curArg
	else
	  let s:p4Command = curArg
	endif
      else " Argument is not a perforce command.
        if s:p4Command == ""
          let s:p4Options = s:p4Options . ' ' . curArg
        else
	  let optArg = 0
	  " Look for options that have an argument, so we can collect this
	  " into p4CmdOptions instead of p4Arguments.
	  if s:p4Arguments == "" && s:IsAnOption(prevArg)
	    " We could as well just check for the option here, but combining
	    " this with the command name will increase the accuracy of finding
	    " the starting point for p4Arguments.
	    if (prevArg[0] == '-' && exists('s:p4OptCmdMap{prevArg[1]}') &&
		  \ MvContainsElement(s:p4OptCmdMap{prevArg[1]}, ',',
		    \ s:p4Command)) ||
	     \ (prevArg[0] == '+' && exists('s:biOptCmdMap{prevArg[1]}') &&
		  \ MvContainsElement(s:biOptCmdMap{prevArg[1]}, ',',
		    \ s:p4Command))
	      let optArg = 1
	    endif
	  endif

	  if optArg
	    let s:p4CmdOptions = s:p4CmdOptions . ' ' . curArg
	  else
	    let s:p4Arguments = s:p4Arguments . ' ' . curArg
	  endif
        endif
      endif
    else
      if s:p4Arguments == ""
	if s:p4Command == ""
	  let s:commandMode = s:CM_RUN
	  if curArg =~ '^++.$'
	    if curArg == '++p'
	      let s:commandMode = s:CM_PIPE
	    elseif curArg == '++f'
	      let s:commandMode = s:CM_FILTER
	    elseif curArg == '++d'
	      let s:commandMode = s:CM_DISPLAY
	    elseif curArg == '++r'
	      let s:commandMode = s:CM_RUN
	    endif
	    continue
	  endif
	  let s:p4Options = s:p4Options . ' ' . curArg
	else
	  let s:p4CmdOptions = s:p4CmdOptions . ' ' . curArg
	endif
      else
	let s:p4Arguments = s:p4Arguments . ' ' .  curArg
      endif
    endif
   " This option requires it to act like a filter.
    if s:p4Command == '' && curArg == '-x'
      let s:commandMode = s:CM_FILTER
    endif

    finally " [+2s]
      if s:pendingPipeArg == ''
	let i = i + 1
      endif
      let prevArg = curArg
    endtry
  endwhile
  let s:p4Options = s:CleanSpaces(s:p4Options)
  let s:p4Command = s:CleanSpaces(s:p4Command)
  let s:p4CmdOptions = s:CleanSpaces(s:p4CmdOptions)
  let s:p4Arguments = s:CleanSpaces(s:p4Arguments)
  let s:p4WinName = s:MakeWindowName()
endfunction

function! s:IsAnOption(arg)
  if a:arg =~ '^-.$' || a:arg =~ '^-d[cdnsu]$' || a:arg =~ '^-a[fmsty]$' ||
	\ a:arg =~ '^-s[ader]$' || a:arg =~ '^-qu$' || a:arg =~ '^+.$'
	\ || a:arg =~ '^++.$'
    return 1
  else
    return 0
  endif
endfunction

function! s:Escape(str)
  return Escape(a:str, ' ')
endfunction

function! s:CleanSpaces(str)
  " Though not complete, it is just easier to say,
  "   "spaces that are not preceded by \'s".
  return substitute(substitute(a:str, '^ \+\|\%(\\\@<! \)\+$', '', ''),
	\ '\%(\\\@<! \)\+', ' ', 'g')
endfunction
""" END: Argument parsing }}}

""" BEGIN: Messages and dialogs {{{
function! s:ShowVimError(errmsg)
  call s:ConfirmMessage("There was an error executing a Vim command.\n\t" .
	\ a:errmsg, "OK", 1, "Error")
  let s:errCode = 1
endfunction

function! s:EchoMessage(msg, type)
  let s:lastMsg = a:msg
  let s:lastMsgGrp = a:type
  redraw | exec 'echohl' a:type | echo a:msg | echohl NONE
endfunction

function! s:ConfirmMessage(msg, opts, def, type)
  let s:lastMsg = a:msg
  let s:lastMsgGrp = 'None'
  if a:type == 'Error'
    let s:lastMsgGrp = 'Error'
  endif
  return confirm(a:msg, a:opts, a:def, a:type)
endfunction

function! s:PromptFor(loop, useDialogs, msg, default)
  let result = ""
  while result == ""
    if a:useDialogs
      let result = inputdialog(a:msg, a:default)
    else
      let result = input(a:msg, a:default)
    endif
    if ! a:loop
      break
    endif
  endwhile
  return result
endfunction

function! s:LastMessage()
  call s:EchoMessage(s:lastMsg, s:lastMsgGrp)
endfunction
""" END: Messages and dialogs }}}

""" BEGIN: Filename handling {{{
" Escape all the special characters (as the user would if he typed the name
"   himself).
function! s:EscapeFileName(fName)
  return Escape(a:fName, ' &|')
endfunction

function! s:GuessFileTypeForCurrentWindow()
  let fileExt = s:GuessFileType(b:p4CurFileName)
  if fileExt == ""
    let fileExt = s:GuessFileType(expand("%"))
  endif
  return fileExt
endfunction

function! s:GuessFileType(name)
  let fileExt = fnamemodify(a:name, ":e")
  return matchstr(fileExt, '\w\+')
endfunction

function! s:IsDepotPath(depotPath)
  if match(a:depotPath, '^//' . s:p4Depot . '/') == 0 ||
        \ match(a:depotPath, '^//'. s:p4Client . '/') == 0
    return 1
  else
    return 0
  endif
endfunction

function! s:ConvertToLocalPath(depotPath)
  let fileName = a:depotPath
  if s:IsDepotPath(a:depotPath)
    let fileName = s:clientRoot . substitute(fileName, '^//[^/]\+', '', '')
  endif
  let fileName = substitute(fileName, '#[^#]\+$', '', '')
  return fileName
endfunction

" I should really use 'where' command here.
function! s:ConvertToDepotPath(localPath)
  let fileName = a:localPath
  if ! s:IsDepotPath(a:localPath)
    let fileName = CleanupFileName(a:localPath)
    if s:IsFileUnderDepot(fileName)
      let fileName = substitute(fileName, '^' . s:clientRoot, '//' . s:p4Depot,
	    \ '')
    endif
  endif
  return fileName
endfunction

" Requires at least 2 arguments.
" Returns a list of alternative filenames.
function! s:PFGetAltFiles(codeline, ...)
  if a:0 == 0
    return ""
  endif

  let altCodeLine = a:codeline

  let i = 1
  let altFiles = ""
  let root=CleanupFileName(s:clientRoot) . "/"
  while i <= a:0
    let fileName = a:{i}
    let fileName=CleanupFileName(fileName)
    " We have only one slash after the cleanup is done.
    if match(fileName, '^/' . s:p4Depot . '/') == 0 ||
          \ match(fileName, '^/'. s:p4Client . '/') == 0
      let fileName = root . substitute(fileName, '^/[^/]\+/', '', '')
    endif
    " One final cleanup, just in case.
    let fileName=CleanupFileName(fileName)

    if altCodeLine == s:p4Depot
      let altFile = substitute(fileName, root, '//' . s:p4Depot . '/', "")
    else
      let altFile = substitute(fileName, root . '[^/]\+', root . altCodeLine,
	    \ "")
    endif
    let altFiles = MvAddElement(altFiles, ' ', escape(altFile, ' '))
    let i = i + 1
  endwhile
  " Remove the last separator, so the list is ready to be used for 1 element
  " case.
  let altFiles = strpart(altFiles, 0, strlen(altFiles) - 1)
  return altFiles
endfunction

function! s:IsFileUnderDepot(fileName)
  let fileName = CleanupFileName(a:fileName)
  if stridx(fileName, s:clientRoot) != 0
    return 0
  else
    return 1
  endif
endfunction

" This better take the line as argument, but I need the context of current
"   buffer contents anyway...
" I don't need to handle other revision specifiers here, as I won't expect to
"   see them here (perforce converts them to the appropriate revision number). 
function! s:GetCurrentDepotFile(lineNo)
  " Local submissions.
  let fileName = ""
  let line = getline(a:lineNo)
  if match(line, '//' . s:p4Depot . '/.*\(#\d\+\)\?') != -1 ||
        \ match(line, '^//'. s:p4Client . '/.*\(#\d\+\)\?') != -1
    let fileName = matchstr(line, '//[^/]\+/[^#]*\(#\d\+\)\?')
  elseif match(line, '\.\.\. #\d\+ .*') != -1
    " Branches, integrations etc.
    let fileVer = matchstr(line, '\d\+')
    call SaveHardPosition('Perforce')
    exec a:lineNo
    if search('^//' . s:p4Depot . '/', 'bW') == -1
      let fileName = ""
    else
      let fileName = substitute(s:GetCurrentDepotFile(line(".")), '#\d\+$', '',
	    \ '')
      let fileName = fileName . "#" . fileVer
    endif
    call RestoreHardPosition('Perforce')
    call ResetHardPosition('Perforce')
  endif
  return fileName
endfunction
""" END: Filename handling }}}

""" BEGIN: Buffer management, etc. {{{
" Must be followed by a call to s:EndBufSetup()
function! s:StartBufSetup(outputType)
  " If this outputType creates a new window, then only do setup.
  if !s:errCode
    if s:newWindowCreated
      if a:outputType == 1 || a:outputType == 21
	wincmd p
      endif

      return 1
    endif
  endif
  return 0
endfunction

function! s:EndBufSetup(outputType)
  if s:newWindowCreated
    if a:outputType == 1 || a:outputType == 21
      wincmd p
    endif
  endif
endfunction

" Goto/Open window for the current command.
" clearBuffer (number):
"   0 - clear with no undo.
"   1 - clear with undo.
"   2 - don't clear
function! s:GotoWindow(outputType, clearBuffer, p4CurFileName)
  " If there is a window for this buffer already, then we will just move
  "   cursor into it.
  let curBufnr = winbufnr(winnr())
  let winnr = bufwinnr(FindBufferForName(s:p4WinName))
  let nWindows = NumberOfWindows()
  let s:newWindowCreated = 1
  let _eventignore = &eventignore
  try
    set eventignore=BufRead,BufReadPre,BufEnter,BufNewFile
    if a:outputType == 1 " Preview
      let alreadyOpen = 0
      try
	wincmd P
	" No exception, preview window is already open.
	" Only when the buffer is not already visible in the preview window.
	if winnr() != winnr
	  " If the current buffer in preview window is a perforce buffer, when
	  "   we switch to a different buffer, unless 'hidden' or
	  "   'bufhidden=hide' setting is set, we have to first do a :pclose.
	  if exists("b:p4CurFileName")
	    if ! &hidden && &l:bufhidden != 'hide' && ! s:p4HideOnBufHidden
	      pclose
	      let nWindows = nWindows - 1
	    elseif s:p4HideOnBufHidden
	      setlocal bufhidden=hide
	    endif
	  endif
	else
	  let alreadyOpen = 1
	endif
      catch /^Vim\%((\a\+)\)\=:E441/
	" Ignore.
      endtry
      if !alreadyOpen
	call s:EditP4WinName('pedit', nWindows)
	wincmd P
      endif
      normal! mt
    elseif winnr != -1
      call MoveCursorToWindow(winnr)
      " For navigation.
      normal! mt
    else
      exec s:splitCommand
      call s:EditP4WinName('edit', nWindows)
    endif
  finally
    let &eventignore = _eventignore
  endtry
  if s:newWindowCreated
    " We now have a new window created, but may be with errors.
    if s:errCode == 0
      setlocal noreadonly
      setlocal modifiable
      if s:commandMode == s:CM_RUN
	if a:clearBuffer == 1
	  call OptClearBuffer()
	elseif a:clearBuffer == 0
	  silent! 0,$delete _
	endif
      endif

      let b:p4CurFileName = a:p4CurFileName
      " Even if we found an existing window for it, we still want to set
      "   certain variables.
      let s:newWindowCreated = 1
    else
      if winbufnr(winnr()) == curBufnr
	quit
      else
	" This should even close the window.
	silent! exec "bwipeout " . bufnr('%')
      endif
      let s:newWindowCreated = 0
    endif
  endif
endfunction

function! s:EditP4WinName(editCmd, nWindows)
  let fatal = 0
  let bug = 0
  let exception = ''
  try
    exec a:editCmd s:p4WinName
  catch /^Vim\%((\a\+)\)\=:E303/
    " This is a non-fatal error.
    let bug = 1 | let exception = v:exception
  catch /^Vim\%((\a\+)\)\=:\%(E77\|E480\)/
    let bug = 1 | let exception = v:exception
    let fatal = 1
  catch
    let fatal = 1 | let exception = v:exception
  endtry
  if fatal
    call s:ShowVimError(exception)
  endif
  if bug
    echohl ERROR | echomsg "Please report this error message:\n".v:exception.
	  \ "\nwith the following information:\ns:p4WinName=".s:p4WinName |
	  \ echohl NONE
  endif
  if a:editCmd !~ '\<pedit\>' && a:nWindows == NumberOfWindows()
    let s:newWindowCreated = 0
  endif
endfunction

function! s:MakeWindowName()
  let cmdStr = s:MakeP4CmdString('p4')
  let winName = cmdStr
  "let winName = DeEscape(winName)
  " HACK: Work-around for some weird handling of buffer names that have "..."
  "   (the perforce wildcard) at the end of the filename or in the middle
  "   followed by a space. The autocommand is not getting triggered to clean
  "   the buffer. If we append another character to this, I observed that the
  "   autocommand gets triggered. Using "/" instead of "'" would probably be
  "   more appropriate, but this is causing unexpected FileChangedShell
  "   autocommands on certain filenames (try "PF submit ../..." e.g.).
  "let winName = substitute(winName, '\.\.\%( \|$\)\@=', '&/', 'g')
  let winName = substitute(winName, '\.\.\%( \|$\)\@=', "&'", 'g')
  " The intention is to do the substitute only on systems like windoze that
  "   don't allow all characters in the filename, but I can't generalize it
  "   enough, so as a workaround I a just assuming any system supporting
  "   'shellslash' option to be a windoze like system. In addition, cygwin
  "   vim thinks that it is on Unix and tries to allow all characters, but
  "   since the underlying OS doesn't support it, we need the same treatment
  "   here also.
  if exists('+shellslash') || has('win32unix')
    " Some characters are not allowed in a filename on windows so substitute
    " them with something else.
    let winName = substitute(winName, s:specialChars,
	  \ '\="[" . s:specialChars{submatch(1)} . "]"', 'g')
    "let winName = substitute(winName, s:specialChars, '\\\1', 'g')
  endif
  " Finally escape some characters again.
  let winName = Escape(winName, " #%\t")
  if s:GetShellEnvType() == s:ST_UNIX
    let winName = substitute(winName, '\\\@<!\(\%(\\\\\)*\\[^ ]\)', '\\\1', 'g')
    let winName = escape(winName, "'~$`{\"")
  endif
  return winName
endfunction

function! s:PFSetupBuf(bufName)
  call SetupScratchBuffer()
  " Remove any ^M's at the end (for windows), without corrupting the search
  " register or its history.
  call s:SilentSub("\<CR>$", '%s///e')
  setlocal nomodified
  setlocal nomodifiable
  setlocal foldcolumn=0
  if s:p4HideOnBufHidden
    setlocal bufhidden=hide
  else
    setlocal bufhidden=
    call s:PFSetupBufAutoCommand(a:bufName, 'BufUnload',
	\ ':call <SID>PFExecBufClean(expand("<abuf>") + 0)')
  endif
endfunction

function! s:PFSetupForSpec()
  setlocal modifiable
  set buftype=
  call s:PFSetupBufAutoCommand(expand('%'), 'BufWriteCmd', ':W')
endfunction

function! s:WipeoutP4Buffers(...)
  let testMode = 1
  if a:0 > 0 && a:1 == '+y'
    let testMode = 0
  endif
  let i = 1
  let lastBuf = bufnr('$')
  let cleanedBufs = ''
  while i <= lastBuf
    if bufexists(i) && expand('#'.i) =~ '\<p4 ' && bufwinnr(i) == -1
      if testMode
	let cleanedBufs = cleanedBufs . ', ' . expand('#'.i)
      else
	let _report = &report
	try
	  set report=99999
	  exec 'bwipeout' i
	  call s:PFUnSetupBufAutoCommand(expand('#'.i), 'BufUnload')
	finally
	  let &report = _report
	endtry
	let cleanedBufs = cleanedBufs + 1
      endif
    endif
    let i = i + 1
  endwhile
  if testMode
    echo "Buffers that will be wipedout (Use +y to perform action):" .
	  \ cleanedBufs
  else
    echo "Total Perforce buffers wipedout (start with 'p4 '): " . cleanedBufs
  endif
endfunction

" Arrange an autocommand such that the buffer is automatically deleted when the
"  window is quit. Delete the autocommand itself when done.
function! s:PFSetupBufAutoCommand(bufName, auName, auCmd)
  let bufName = s:GetBufNameForAu(a:bufName)
  " Just in case the autocommands are leaking, this will curtail the leak a
  "   little bit.
  silent! exec 'au! Perforce' a:auName bufName
  exec 'au Perforce' a:auName bufName a:auCmd
endfunction

function! s:PFUnSetupBufAutoCommand(bufName, auName)
  let bufName = s:GetBufNameForAu(a:bufName)
  silent! exec "au! Perforce" a:auName bufName
endfunction

function! s:GetBufNameForAu(bufName)
  let bufName = a:bufName
  " Autocommands always require forward-slashes.
  let bufName = substitute(bufName, "\\\\", '/', 'g')
  let bufName = escape(bufName, '*?,{}[ ')
  return bufName
endfunction

" Find and delete the buffer. Delete the autocommand itself after that.
function! s:PFExecBufClean(bufNo)
  if a:bufNo == -1 | return | endif
  " We get here, only when the buffer is getting unloaded, because the user
  "   didn't use one of the 'hidden' or 'bufhidden' settings or :hide command.
  "   It is safe to assume that this buffer can just be wipedout at this
  "   stage.
  exec "au! Perforce * " . s:GetBufNameForAu(bufname(a:bufNo))
  silent! exec "bwipeout! ". a:bufNo
endfunction

function! s:PRefreshActivePane()
  if exists("b:p4FullCmd")
    call SaveHardPosition('Perforce')

    let _modifiable = &l:modifiable
    try
      setlocal modifiable
      exec "1,$!" . b:p4FullCmd
    catch
      call s:ShowVimError(b:exception)
    finally
      let &l:modifiable=_modifiable
    endtry

    call RestoreHardPosition('Perforce')
    call ResetHardPosition('Perforce')
  endif
endfunction
""" END: Buffer management, etc. }}}

""" BEGIN: Testing {{{
" Ex: PFTestCmdParse -c client -u user integrate -b branch -s source target1 target2
command! -nargs=* -range=% PFTestCmdParse call <SID>TestParseOptions(<f-args>)
function! s:TestParseOptions(commandName, ...) range
  exec MakeArgumentString()
  exec "call s:ParseOptionsIF(a:firstline, a:lastline," .
	\ " 0, a:commandName, " . argumentString . ")"
  echo "p4Options :" . s:p4Options . ":"
  echo "p4Command :" . s:p4Command . ":"
  echo "p4CmdOptions :" . s:p4CmdOptions . ":"
  echo "p4Arguments :" . s:p4Arguments . ":"
  echo "p4Pipe :" . s:p4Pipe . ":"
  echo "p4WinName :" . s:p4WinName . ":"
  echo "commandMode :" . s:commandMode . ":"
  echo "filterRange :" . s:filterRange . ":"
  echo "Cmd :" . s:CreateFullCmd(s:MakeP4CmdString('')) . ":"
endfunction

"function! s:TestPushPopContexts()
"  let s:p4Options = "options1"
"  let s:p4Command = "command1"
"  let s:p4CmdOptions = "cmdOptions1"
"  let s:p4Arguments = "arguments1"
"  let s:p4WinName = "winname1"
"  call s:PushP4Context()
"
"  let s:p4Options = "options2"
"  let s:p4Command = "command2"
"  let s:p4CmdOptions = "cmdOptions2"
"  let s:p4Arguments = "arguments2"
"  let s:p4WinName = "winname2"
"  call s:PushP4Context()
"
"  call s:ResetP4Vars()
"  echo "After reset: " . s:CreateFullCmd(s:MakeP4CmdString(''))
"  call s:PopP4Context()
"  echo "After pop1: " . s:CreateFullCmd(s:MakeP4CmdString(''))
"  call s:PopP4Context()
"  echo "After pop2: " . s:CreateFullCmd(s:MakeP4CmdString(''))
"endfunction

""" END: Testing }}}

""" END: Infrastructure }}}

" Restore cpo.
let &cpo = s:save_cpo
unlet s:save_cpo

" vim6:fdm=marker
