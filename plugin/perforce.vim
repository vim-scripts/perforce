" perforce.vim: Interface with perforce SCM through p4.
" Author: Hari Krishna (hari_vim at yahoo dot com)
" Last Change: 28-Oct-2004 @ 18:25
" Created:     Sometime before 20-Apr-2001
" Requires:    Vim-6.3, genutils.vim(1.14), multvals.vim(3.6)
" Version:     3.1.1
" Licence: This program is free software; you can redistribute it and/or
"          modify it under the terms of the GNU General Public License.
"          See http://www.gnu.org/copyleft/gpl.txt 
" Acknowledgements:
"     See ":help perforce-acknowledgements".
" Download From:
"     http://www.vim.org//script.php?script_id=240
" Usage:
"     For detailed help, see ":help perforce" or read doc/perforce.txt. 
"
" TODO: {{{
"
"   - I need a test suite to stop things from breaking.
"   - Should the client returned by g:p4CurPresetExpr be made permanent?
"   - curPresetExpr can't support password, so how is the expression going to
"     change password?
"   - If you actually use python to execute, you may be able to display the
"     output incrementally.
"   - There seems to be a problem with 'autoread' change leaking. Not sure if
"     we explicitly set it somewhere, check if we are using try block.
"   - Buffer local autocommads are pretty useful for perforce plugin, send
"     feedback.
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
"     that was passed to the main command (unless the main command already
"     generated a new window, in which case the original s:p4Options are
"     remembered through b:p4Options and automatically reused for the
"     subcommands), or the user will see incorrect behavior or at the worst,
"     errors.
"   - The p4FullCmd now can have double-quotes surrounding each of the
"     individual arguments if the shell is cmd.exe or command.com, so while
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
"   - Eventhough DefFileChangedShell event handling is now localized, we still
"     need to depend on s:currentCommand to determine the 'autoread' value,
"     this is because some other plugin might have already installed a
"     FileChangedShell event to DefFileChangedShell, resulting in us receiving
"     callbacks anytime, so we need a variable that has a lifespace only for
"     the duration of the execution of p4 commands?
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
"       On Windoze+native:
"         cmd /c <command>
"       On Windoze+sh:
"         sh -c "<command>"
"       On Unix+sh:
"         sh -c (<command>) 
"   - By the time we parse arguments, we protect all the back-slashes, which
"     means that we would never see a single-back-slash.
"   - Using back-slashes on Cygwin vim is unique and causes E303. This is
"     because it thinks it is on UNIX where it is not a special character, but
"     underlying Windows obviously treats it special and so it bails out.
"   - Using back-slashes on Windows+sh also seems to be different. Somewhere in
"     the execution line (most probably the path from CreateProcess() to sh,
"     as it doesn't happen in all other types of interfaces) consumes one
"     level of extra back-slashes. If it is even number it becomes half, and
"     if it is odd then the last unpaired back-slash is left as it is.
"   - Some test cases for special character handling:
"     - PF fstat a\b
"     - PF fstat a\ b
"     - PF fstat a&b
"     - PF fstat a\&b
"     - PF fstat a\#b
"     - PF fstat a\|b
"   - Careful using s:PFIF(1) from within script, as it doesn't redirect the
"     call to the corresponding handler (if any).
"   - Careful using ":PF" command from within handlers, especially if you are
"     executing the same s:p4Command again as it will result in a recursion.
"   - The outputType's -2 and -1 are local to the s:PFrangeIF() interface, the
"     actual s:PFImpl() or any other methods shouldn't know anything about it.
"     Which is why this outputType should be used only for those commands that
"     don't have a handler. Besides this scheme will not even work if a
"     handler exists, as the outputType will get permanently set to 4 by the
"     time it gets redirected back to s:PFrangeIF() through the handler. (If
"     this should ever be a requirement, we will need another state variable
"     called s:orgOutputType.)
"   - Be careful to pass argument 0 to s:PopP4Context() whenever the logical
"     p4 operation ends, to avoid getting the s:errCode carried over. This is
"     currently taken care of for all the known recursive or ignorable error
"     cases.
"   - We need to use s:outputType as much as possible, not a:outputType, which
"     is there only to pass it on to s:ParseOptions(). After calling s:PFIF()
"     the outputType is established in s:outputType.
"   - s:errCode is reset by ParseOptions(). For cases that Push and Pop context
"     even before the first call to ParseOptions() (such as the
"     s:GetClientInfo() function), we have to check for s:errCode before we
"     pop context, or we will just carry on an error code from a previous bad
"     run (applies to mostly utility functions).
" END NOTES }}}

if exists('loaded_perforce')
  finish
endif
if v:version < 603
  echomsg 'Perforce: You need at least Vim 6.3'
  finish
endif


" We need these scripts at the time of initialization itself.
if !exists('loaded_multvals')
  runtime plugin/multvals.vim
endif
if !exists('loaded_multvals') || loaded_multvals < 306
  echomsg 'perforce: You need a newer version of multvals.vim plugin'
  finish
endif
if !exists('loaded_genutils')
  runtime plugin/genutils.vim
endif
if !exists('loaded_genutils') || loaded_genutils < 114
  echomsg 'perforce: You need a newer version of genutils.vim plugin'
  finish
endif
let loaded_perforce=300

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

let firstTimeInit = 1
if !exists("s:p4CmdPath") " The first-time only, initialize with defaults.
  let s:p4CmdPath = "p4"
  let s:clientRoot = ""
  let s:defaultListSize='100'
  let s:defaultDiffOptions=''
  let s:p4DefaultPreset = -1
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
  let s:tempDir = fnamemodify(tempname(), ':h')
  let s:splitCommand = "split"
  let s:enableFileChangedShell = 1
  let s:useVimDiff2 = 0
  let s:p4BufHidden = 'wipe'
  let s:autoread = 1
  if OnMS()
    let s:fileLauncher = 'start rundll32 SHELL32.DLL,ShellExec_RunDLL'
  else
    let s:fileLauncher = ''
  endif
  let s:curPresetExpr = ''
  let s:curDirExpr = ''
  let s:useClientViewMap = 1
else
  let firstTimeInit = 0
endif

function! s:CondDefSetting(globalName, settingName, ...)
  let assgnmnt = (a:0 != 0) ? a:1 : a:globalName
  if exists(a:globalName)
    exec "let" a:settingName "=" assgnmnt
    exec "unlet" a:globalName
  endif
endfunction
 
call s:CondDefSetting('g:p4CmdPath', 's:p4CmdPath')
call s:CondDefSetting('g:p4ClientRoot', 's:clientRoot',
      \ 'CleanupFileName(g:p4ClientRoot)')
call s:CondDefSetting('g:p4DefaultListSize', 's:defaultListSize')
call s:CondDefSetting('g:p4DefaultDiffOptions', 's:defaultDiffOptions')
call s:CondDefSetting('g:p4DefaultPreset', 's:p4DefaultPreset')
if exists('g:p4Depot') && g:p4Depot !~# s:EMPTY_STR
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
call s:CondDefSetting('g:p4BufHidden', 's:p4BufHidden')
call s:CondDefSetting('g:p4Autoread', 's:autoread')
call s:CondDefSetting('g:p4FileLauncher', 's:fileLauncher')
call s:CondDefSetting('g:p4CurPresetExpr', 's:curPresetExpr')
call s:CondDefSetting('g:p4CurDirExpr', 's:curDirExpr')
call s:CondDefSetting('g:p4UseClientViewMap', 's:useClientViewMap')
delfunction s:CondDefSetting

if firstTimeInit && s:p4DefaultPreset != -1 &&
      \ s:p4DefaultPreset.'' !~# s:EMPTY_STR
  call s:PFSwitch(0, s:p4DefaultPreset)
endif

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

aug P4ClientRoot
  au!
  if s:clientRoot =~# s:EMPTY_STR || s:p4Client =~# s:EMPTY_STR ||
        \ s:p4User =~# s:EMPTY_STR
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

command! -nargs=* -complete=custom,<SID>PFComplete PP
      \ :call <SID>printHdlr(0, 0, <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PPrint
      \ :call <SID>printHdlr(0, 0, <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PD
      \ :call <SID>diffHdlr(0, 0, <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PDiff
      \ :call <SID>diffHdlr(0, 0, <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PEdit
      \ :call <SID>PFIF(0, -2, "edit", <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PE
      \ :call <SID>PFIF(0, -2, "edit", <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PReopen
      \ :call <SID>PFIF(0, -2, "reopen", <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PAdd
      \ :call <SID>PFIF(0, -2, "add", <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PA
      \ :call <SID>PFIF(0, -2, "add", <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PDelete
      \ :call <SID>PFIF(0, -2, "delete", <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PLock
      \ :call <SID>PFIF(0, -2, "lock", <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PUnlock
      \ :call <SID>PFIF(0, -2, "unlock", <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PRevert
      \ :call <SID>PFIF(0, -2, "revert", <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PR
      \ :call <SID>PFIF(0, -2, "revert", <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PSync
      \ :call <SID>PFIF(0, -2, "sync", <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PG
      \ :call <SID>PFIF(0, -2, "get", <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PGet
      \ :call <SID>PFIF(0, -2, "get", <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete POpened
      \ :call <SID>PFIF(0, 0, "opened", <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PO
      \ :call <SID>PFIF(0, 0, "opened", <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PHave
      \ :call <SID>PFIF(0, 0, "have", <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PWhere
      \ :call <SID>PFIF(0, 0, "where", <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PDescribe
      \ :call <SID>describeHdlr(0, 0, <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PFiles
      \ :call <SID>PFIF(0, 0, "files", <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PLabelsync
      \ :call <SID>PFIF(0, 0, "labelsync", <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PFilelog
      \ :call <SID>filelogHdlr(0, 0, <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PIntegrate
      \ :call <SID>PFIF(0, 0, "integrate", <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PD2
      \ :call <SID>diff2Hdlr(0, 0, <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PDiff2
      \ :call <SID>diff2Hdlr(0, 0, <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PFstat
      \ :call <SID>PFIF(0, 0, "fstat", <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PH
      \ :call <SID>helpHdlr(0, 0, <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PHelp
      \ :call <SID>helpHdlr(0, 0, <f-args>)


""" Some list view commands.
command! -nargs=* -complete=custom,<SID>PFComplete PChanges
      \ :call <SID>changesHdlr(0, 0, <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PBranches
      \ :call <SID>PFIF(0, 0, "branches", <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PLabels
      \ :call <SID>labelsHdlr(0, 0, <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PClients
      \ :call <SID>clientsHdlr(0, 0, <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PUsers
      \ :call <SID>PFIF(0, 0, "users", <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PJobs
      \ :call <SID>PFIF(0, 0, "jobs", <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PDepots
      \ :call <SID>PFIF(0, 0, "depots", <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PGroups
      \ :call <SID>PFIF(0, 0, "groups", <f-args>)


""" The following support some p4 operations that normally involve some
"""   interaction with the user (they are more than just shortcuts).

command! -nargs=* -complete=custom,<SID>PFComplete PChange
      \ :call <SID>changeHdlr(0, 0, <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PBranch
      \ :call <SID>PFIF(0, 0, "branch", <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PLabel
      \ :call <SID>PFIF(0, 0, "label", <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PClient
      \ :call <SID>PFIF(0, 0, "client", <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PUser
      \ :call <SID>PFIF(0, 0, "user", <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PJob
      \ :call <SID>PFIF(0, 0, "job", <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PJobspec
      \ :call <SID>PFIF(0, 0, "jobspec", <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PDepot
      \ :call <SID>PFIF(0, 0, "depot", <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PGroup
      \ :call <SID>PFIF(0, 0, "group", <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PSubmit
      \ :call <SID>submitHdlr(0, 0, <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PResolve
      \ :call <SID>resolveHdlr(0, 0, <f-args>)

" Some built-in commands.
command! -nargs=? -complete=custom,<SID>PFComplete PVDiff
      \ :call <SID>PFIF(0, 0, "vdiff", <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PVDiff2
      \ :call <SID>PFIF(0, 0, "vdiff2", <f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete PExec
      \ :call <SID>PFIF(0, 5, "exec", <f-args>)

""" Other utility commands.

command! -nargs=* -complete=file E :call <SID>PFOpenAltFile(0, <f-args>)
command! -nargs=* -complete=file ES :call <SID>PFOpenAltFile(2, <f-args>)
command! -nargs=* -complete=custom,<SID>PFSwitchComplete PFSwitch
      \ :call <SID>PFSwitch(1, <f-args>)
command! -nargs=* PFSwitchPortClientUser :call <SID>SwitchPortClientUser()
command! -nargs=0 PFRefreshActivePane :call <SID>PFRefreshActivePane()
command! -nargs=0 PFRefreshFileStatus :call <SID>GetFileStatus(0, 1)
command! -nargs=0 PFToggleCkOut :call <SID>ToggleCheckOutPrompt(1)
command! -nargs=* -complete=custom,<SID>PFSettingsComplete PFS
      \ :PFSettings <args>
command! -nargs=* -complete=custom,<SID>PFSettingsComplete PFSettings
      \ :call <SID>PFSettings(<f-args>)
command! -nargs=0 PFDiffOff :call CleanDiffOptions()
command! -nargs=? PFWipeoutBufs :call <SID>WipeoutP4Buffers(<f-args>)
"command! -nargs=* -complete=file -range=% PF
command! -nargs=* -complete=custom,<SID>PFComplete -range=% PF
      \ :call <SID>PFrangeIF(<line1>, <line2>, 0, -2, <f-args>)
command! -nargs=* -complete=file PFRaw :call <SID>PFRaw(<f-args>)
command! -nargs=* -complete=custom,<SID>PFComplete -range=% PW
      \ :call <SID>PW(<line1>, <line2>, 0, <f-args>)
command! -nargs=0 PFLastMessage :call <SID>LastMessage()
command! -nargs=0 PFBugReport :runtime perforce/perforcebugrep.vim
command! -nargs=0 PFUpdateViews :call <SID>UpdateViewMappings()

" New normal mode mappings.
if (! exists("no_plugin_maps") || ! no_plugin_maps) &&
      \ (! exists("no_perforce_maps") || ! no_execmap_maps)
  nnoremap <silent> <Leader>prap :PFRefreshActivePane<cr>
  nnoremap <silent> <Leader>prfs :PFRefreshFileStatus<cr>

  " Some generic mappings.
  if maparg('<C-X><C-P>', 'c') == ""
    cnoremap <C-X><C-P> <C-R>=<SID>PFOpenAltFile(1)<CR>
  endif
endif

" Command definitions }}}

" Give a chance for the perforcemenu.vim to reconfigure the menu. Allow users
"   to add their own stuff.
runtime! perforce/perforcemenu.vim
let v:errmsg = ''

let s:promptToCheckout = ! s:promptToCheckout
call s:ToggleCheckOutPrompt(0)

endfunction " s:Initialize }}}

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

let s:p4KnownCmds = "add,admin,annotate,branch,branches,change,changes," .
      \ "client,clients,counter,counters,delete,depot,depots,describe,diff," .
      \ "diff2,dirs,edit,filelog,files,fix,fixes,flush,fstat,get,group," .
      \ "groups,have,help,info,integrate,integrated,job,jobs,jobspec,label," .
      \ "labels,labelsync,lock,logger,monitor,obliterate,opened,passwd,print," .
      \ "protect,rename,reopen,resolve,resolved,revert,review,reviews,set," .
      \ "submit,sync,triggers,typemap,unlock,user,users,verify,where,"
" Add some built-in commands to this list.
let s:builtinCmds = "vdiff,vdiff2,exec,"
let s:allCommands = s:p4KnownCmds . s:builtinCmds
let s:p4KnownCmdsCompStr = ''

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

" Map the commands with short name to their long versions.
let s:shortCmdMap{'p'} = 'print'
let s:shortCmdMap{'d'} = 'diff'
let s:shortCmdMap{'e'} = 'edit'
let s:shortCmdMap{'a'} = 'add'
let s:shortCmdMap{'r'} = 'revert'
let s:shortCmdMap{'g'} = 'get'
let s:shortCmdMap{'o'} = 'open'
let s:shortCmdMap{'d2'} = 'diff2'
let s:shortCmdMap{'h'} = 'help'


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
" For the following commands, we should limit the output lines in the dialog
"   to s:maxLinesInDialog. If it exceeds, we should switch to showing a
"   dialog.
let s:limitLinesInDlgCmds =
      \ 'add,delete,edit,get,lock,reopen,revert,sync,unlock,'

" If there is a confirm message, then PFIF() will prompt user before
"   continuing with the run.
let s:confirmMsgs{'revert'} = "Reverting file(s) will overwrite any edits to " .
      \ "the files(s)\n Do you want to continue?"
let s:confirmMsgs{'submit'} = "This will commit the changelist to the depot." .
      \ "\n Do you want to continue?"

" Settings that are not directly exposed to the user. These can be accessed
"   using the public API.
" Refresh the contents of perforce windows, even if the window is already open.
let s:refreshWindowsAlways = 1

" List of the global variable names of the user configurable settings.
let s:settings = 'ClientRoot,CmdPath,Presets,' .
      \ 'DefaultOptions,DefaultDiffOptions,EnableMenu,EnablePopupMenu,' .
      \ 'UseExpandedMenu,UseExpandedPopupMenu,EnableRuler,RulerWidth,' .
      \ 'DefaultListSize,EnableActiveStatus,OptimizeActiveStatus,' .
      \ 'ASIgnoreDefPattern,ASIgnoreUsrPattern,PromptToCheckout,' .
      \ 'CheckOutDefault,UseGUIDialogs,MaxLinesInDialog,SortSettings,' .
      \ 'TempDir,SplitCommand,UseVimDiff2,EnableFileChangedShell,' .
      \ 'BufHidden,Depot,Autoread,UseClientViewMap'
let s:settingsCompStr = ''

" Map of global variable name to the local variable that are different than
"   their global counterparts.
let s:settingsMap{'EnableActiveStatus'} = 'activeStatusEnabled'
let s:settingsMap{'EnableRuler'} = 'rulerEnabled'
let s:settingsMap{'EnableMenu'} = 'menuEnabled'
let s:settingsMap{'EnablePopupMenu'} = 'popupMenuEnabled'
let s:settingsMap{'ASIgnoreDefPattern'} = 'ignoreDefPattern'
let s:settingsMap{'ASIgnoreUsrPattern'} = 'ignoreUsrPattern'

let s:helpWinName = 'P4\ help'

" Unprotected space.
let s:SPACE_AS_SEP = MvCrUnProtectedCharsPattern(' ')
let s:EMPTY_STR = '^\_s*$'

if !exists('s:p4Client') || s:p4Client =~# s:EMPTY_STR
  let s:p4Client = $P4CLIENT
endif
if !exists('s:p4User') || s:p4User =~# s:EMPTY_STR
  if exists("$P4USER") && $P4USER !~# s:EMPTY_STR
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
endif
if !exists('s:p4Port') || s:p4Port =~# s:EMPTY_STR
  let s:p4Port = $P4PORT
endif
let s:p4Password = $P4PASSWD

let s:CM_RUN = 'run' | let s:CM_FILTER = 'filter' | let s:CM_DISPLAY = 'display'
let s:CM_PIPE = 'pipe'

let s:changesExpr  = "matchstr(getline(\".\"), '" .
      \ '^Change \zs\d\+\ze ' . "')"
let s:branchesExpr = "matchstr(getline(\".\"), '" .
      \ '^Branch \zs[^ ]\+\ze ' . "')"
let s:labelsExpr   = "matchstr(getline(\".\"), '" .
      \ '^Label \zs[^ ]\+\ze ' . "')"
let s:clientsExpr  = "matchstr(getline(\".\"), '" .
      \ '^Client \zs[^ ]\+\ze ' . "')"
let s:usersExpr    = "matchstr(getline(\".\"), '" .
      \ '^[^ ]\+\ze <[^@>]\+@[^>]\+> ([^)]\+)' . "')"
let s:jobsExpr     = "matchstr(getline(\".\"), '" .
      \ '^[^ ]\+\ze on ' . "')"
let s:depotsExpr   = "matchstr(getline(\".\"), '" .
      \ '^Depot \zs[^ ]\+\ze ' . "')"
let s:describeExpr = 's:DescribeGetCurrentItem()'
let s:filelogExpr  = 's:GetCurrentDepotFile(line("."))'
let s:groupsExpr   = 'expand("<cword>")'

let s:fileBrowseExpr = 's:ConvertToLocalPath(s:GetCurrentDepotFile(line(".")))'
let s:openedExpr   = s:fileBrowseExpr
let s:filesExpr    = s:fileBrowseExpr
let s:haveExpr     = s:fileBrowseExpr
let s:integrateExpr = s:fileBrowseExpr
" Open in describe window should open the local file.
let s:describeOpenItemExpr = s:fileBrowseExpr

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
let s:builtinCmdHandler{'exec'} = 's:ExecHandler' 

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

  if s:StartBufSetup()
    let undo = 0
    " The first line printed by p4 for non-q operation causes vim to misjudge
    " the filetype.
    if getline(1) =~# '//[^#]\+#\d\+ - '
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

    call s:EndBufSetup()
  endif
  return retVal
endfunction

function! s:describeHdlr(scriptOrigin, outputType, ...)
  exec MakeArgumentString()
  if !a:scriptOrigin
    exec "call s:ParseOptionsIF(1, line('$'), 1, a:outputType, 'describe', " .
          \ argumentString . ")"
  endif
  " If -s doesn't exist, and user doesn't intent to see a diff, then let us
  "   add -s option. In any case he can press enter on the <SHOW DIFFS> to see
  "   it later.
  if      ! MvContainsElement(s:p4CmdOptions, s:SPACE_AS_SEP, '-s', ' ') &&
        \ ! MvContainsPattern(s:p4CmdOptions, s:SPACE_AS_SEP, '-d.\+', ' ')
    let s:p4CmdOptions = s:p4CmdOptions . ' -s'
    let s:p4WinName = s:MakeWindowName() " Adjust window name.
  endif

  exec "let retVal = s:PFIF(2, a:outputType, 'describe')"
  if s:StartBufSetup() && getline(1) !~# ' - no such changelist'
    call s:SetupFileBrowse()
    command! -buffer -nargs=0 PItemOpen :call <SID>DescribeFileOpen()
    if MvContainsElement(s:p4CmdOptions, s:SPACE_AS_SEP, '-s', ' ')
      setlocal modifiable
      call append('$', "\t<SHOW DIFFS>")
      setlocal nomodifiable
    else
      call s:SetupDiff()
    endif

    call s:EndBufSetup()
  endif
  return retVal
endfunction

function! s:diffHdlr(scriptOrigin, outputType, ...)
  exec MakeArgumentString()
  if !a:scriptOrigin
    exec "call s:ParseOptionsIF(1, line('$'), 1, a:outputType, 'diff', " .
          \ argumentString . ")"
  endif

  " If a change number is specified in the diff, we need to handle it
  "   ourselves, as p4 doesn't understand this.
  " FIXME: Take care of protected space.
  let changeNo = matchstr(s:p4CmdOptions, '++c\s\+\zs\%(\d\+\|\<default\>\)')
  if changeNo != '' " If a change no. is specified.
    call s:PushP4Context()
    try
      let s:p4Options = '++T ++N ' . s:p4Options " Testmode.
      let retVal = s:PFIF(2, a:outputType, 'diff') " Opens window.
      if s:errCode == 0
        setlocal modifiable
        exec '.PF ++f opened -c' changeNo
      endif
    finally
      let cntxtStr = s:PopP4Context()
    endtry
  else
    " Any + option is treated like a signal to run external diff.
    let externalDiffOptExists = (MvIndexOfPattern(s:p4CmdOptions,
          \ s:SPACE_AS_SEP, '+\S\+', ' ') != -1)
    if externalDiffOptExists
      if MvNumberOfElements(s:p4Arguments, s:SPACE_AS_SEP, ' ') > 1
        return s:SyntaxError('Option +U can not be used with multiple files.')
      endif
      let needsPop = 0
      try
        let _p4Options = s:p4Options
        let s:p4Options = '++T ' . s:p4Options " Testmode, just open the window.
        let retVal = s:PFIF(2, 0, 'diff')
        let s:p4Options = _p4Options
        if s:errCode != 0
          return
        endif
        call s:PushP4Context() | let needsPop = 1
        PW print -q
        if s:errCode == 0
          setlocal modifiable
          let fileName = s:ConvertToLocalPath(s:p4Arguments)
          call s:PeekP4Context()
          " Remove all the non-external options and process external options.
          " Sample:
          " '-x +width=10 -du -y +U=20 -z -a -db +tabsize=4'
          "   to
          " '--width=10 -U 20 --tabsize=4'
          let diffOpts = substitute(s:p4CmdOptions,
                \ '\s*\([-+]\)\([^= ]\+\)'.
                \   '\%(=\(\%(\\\@<!\%(\\\\\)*\\ \|\S\)\+\)\)\?\s*',
                \ '\=(submatch(1) == "-") ? '.
                \    '"" : '.
                \    '(strlen(submatch(2)) > 1 ? '.
                \     '("--".submatch(2).'.
                \      '(submatch(3) != "" ? "=".submatch(3) : "")) : '.
                \     '("-".submatch(2).'.
                \      '(submatch(3) != "" ? " ".submatch(3) : "")))." "',
                \ 'g')
          if getbufvar(bufnr('#'), '&ff') ==# 'dos'
            setlocal ff=dos
          endif
          silent! exec '%!'.
                \ EscapeCommand('diff', diffOpts.' -- - '.fileName, '')
          if v:shell_error > 1
            call s:EchoMessage('Error executing external diff command. '.
                  \ 'Verify that GNU (or a compatible) diff is in your path.',
                  \ 'ERROR')
            return ''
          endif
          call SilentSubstitute("\<CR>$", '%s///')
          call SilentSubstitute('^--- -', '1s;;--- '.
                \ s:ConvertToDepotPath(fileName))
          1
        endif
      finally
        setlocal nomodifiable
        if needsPop
          call s:PopP4Context()
        endif
      endtry
    else
      exec "let retVal = s:PFIF(2, exists('$P4DIFF') ? 5 : a:outputType, " .
            \ "'diff')"
    endif
  endif

  if s:StartBufSetup()
    call s:SetupDiff()

    if changeNo != '' && getline(1) !~# 'ile(s) not opened on this client\.'
      setl modifiable
      call SilentSubstitute('#.*', '%s///e')
      call s:SetP4ContextVars(cntxtStr) " Restore original diff context.
      call s:PFIF(1, 0, '-x', '-', '++f', '++n', 'diff')
      setl nomodifiable
    endif

    call s:EndBufSetup()
  endif
  return retVal
endfunction

function! s:diff2Hdlr(scriptOrigin, outputType, ...)
  exec MakeArgumentString()
  if !a:scriptOrigin
    exec "call s:ParseOptionsIF(1, line('$'), 1, a:outputType, 'diff2', " .
          \ argumentString . ")"
  endif

  let s:p4Arguments = s:GetDiff2Args()

  exec "let retVal = s:PFIF(2, exists('$P4DIFF') ? 5 : a:outputType, 'diff2')"
  if s:StartBufSetup()
    call s:SetupDiff()

    call s:EndBufSetup()
  endif
  return retVal
endfunction

function! s:changeHdlrImpl(outputType)
  let _p4Arguments = ''
  " If argument(s) is not a number...
  if s:p4Arguments !~# s:EMPTY_STR && match(s:p4Arguments, '^\d\+$') == -1
    let _p4Arguments = s:p4Arguments
    let s:p4Arguments = '' " Let a new changelist be created.
  endif
  let retVal = s:PFIF(2, a:outputType, 'change')
  if s:errCode == 0 && (s:StartBufSetup() ||
        \ s:commandMode ==# s:CM_FILTER)
    let p4Options = ''
    if s:p4Options !~# s:EMPTY_STR
      let p4Options = CreateArgString(s:p4Options, s:SPACE_AS_SEP, ' ') .
            \ ', '
    endif
    if _p4Arguments !~# s:EMPTY_STR
      if search('^Files:', 'w') && line('.') != line('$')
        call SaveHardPosition('PChangeImpl')
        +
        call s:PushP4Context()
        try
          exec 'call s:PFrangeIF(line("."), line("$"), 1, 0, ' .
                \ p4Options . '"++f", "opened", "-c", ' . '"default", '
                \ . CreateArgString(_p4Arguments, ' ') . ')'
        finally
          call s:PopP4Context()
        endtry

        if s:errCode == 0
          call SilentSubstitute('^', '.,$s//\t/e')
          call RestoreHardPosition('PChangeImpl')
          call SilentSubstitute('#\d\+ - \(\S\+\) .*$', '.,$s//\t# \1/e')
        endif
        call RestoreHardPosition('PChangeImpl')
        call ResetHardPosition('PChangeImpl')
      endif
    endif

    call s:EndBufSetup()
    setl nomodified
    if _p4Arguments !~# s:EMPTY_STR && &cmdheight > 1
      " The message about W and WQ must have gone by now.
      redraw | call s:LastMessage()
    endif
  endif
  return retVal
endfunction

function! s:changeHdlr(scriptOrigin, outputType, ...)
  exec MakeArgumentString()
  if !a:scriptOrigin
    exec "call s:ParseOptionsIF(1, line('$'), 1, a:outputType, 'change', " .
          \ argumentString . ")"
  endif
  let retVal = s:changeHdlrImpl(a:outputType)
  if s:StartBufSetup()
    let p4Options = ''
    if s:p4Options !~# s:EMPTY_STR
      let p4Options = CreateArgString(s:p4Options, s:SPACE_AS_SEP, ' ') .
            \ ', '
    endif
    exec 'command! -buffer -nargs=* PChangeSubmit :call <SID>W(0, ' .
          \ p4Options . '"submit", <f-args>)'

    call s:EndBufSetup()
  endif
  return retVal
endfunction

" Create a template for submit.
function! s:submitHdlr(scriptOrigin, outputType, ...)
  exec MakeArgumentString()
  if !a:scriptOrigin
    exec "call s:ParseOptionsIF(1, line('$'), 1, a:outputType, 'submit', " .
          \ argumentString . ")"
  endif

  if MvContainsElement(s:p4CmdOptions, s:SPACE_AS_SEP, '-c', ' ') == 1
    " Non-interactive.
    let retVal = s:PFIF(2, a:outputType, 'submit')
  else
    call s:PushP4Context()
    try
      " This is done just to get the :W and :WQ commands defined properly and
      " open the window with a proper name. The actual job is done by the call
      " to s:changeHdlrImpl() which is then run in filter mode to avoid the
      " side-effects (such as :W and :WQ getting overwritten etc.)
      let s:p4Options = '++y ++T ' . s:p4Options " Don't confirm, and testmode.
      call s:PFIF(2, 0, 'submit')
      if s:errCode == 0
        call s:PeekP4Context()
        let s:p4CmdOptions = '' " These must be specific to 'submit'.
        let s:p4Command = 'change'
        let s:commandMode = s:CM_FILTER | let s:filterRange = '.'
        let retVal = s:changeHdlrImpl(a:outputType)
        setlocal nomodified
        if s:errCode != 0
          return
        endif
       endif
    finally
      call s:PopP4Context()
    endtry

    if s:StartBufSetup()
      let p4Options = ''
      if s:p4Options !~# s:EMPTY_STR
        let p4Options = CreateArgString(s:p4Options, s:SPACE_AS_SEP, ' ') .
              \ ', '
      endif
      exec 'command! -buffer -nargs=* PSubmitPostpone :call <SID>W(0, ' .
            \ p4Options . '"change", <f-args>)'
      set ft=perforce " Just to get the cursor placement right.
      call s:EndBufSetup()
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
    exec "call s:ParseOptionsIF(1, line('$'), 1, a:outputType, 'resolve', " .
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

  if s:StartBufSetup()
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

    call s:EndBufSetup()
  endif
endfunction

function! s:clientsHdlr(scriptOrigin, outputType, ...)
  exec MakeArgumentString()
  exec "let retVal = s:PFIF(a:scriptOrigin + 1, a:outputType, 'clients', " .
        \ argumentString . ")"

  if s:StartBufSetup()
    command! -buffer -nargs=0 PClientsTemplate
          \ :call <SID>PFIF(0, 0, '++A', 'client', '-t', <SID>GetCurrentItem())
    nnoremap <silent> <buffer> P :PClientsTemplate<CR>

    call s:EndBufSetup()
  endif
  return retVal
endfunction

function! s:changesHdlr(scriptOrigin, outputType, ...)
  exec MakeArgumentString()
  exec "let retVal = s:PFIF(a:scriptOrigin + 1, a:outputType, 'changes', " .
        \ argumentString . ")"

  if s:StartBufSetup()
    command! -buffer -nargs=0 PItemDescribe
          \ :call <SID>PChangesDescribeCurrentItem()
    command! -buffer -nargs=0 PChangesSubmit
          \ :call <SID>ChangesSubmitChangeList()
    nnoremap <silent> <buffer> S :PChangesSubmit<CR>
    command! -buffer -nargs=0 PChangesOpened
          \ :if getline('.') =~# " \\*pending\\* '" |
          \    call <SID>PFIF(1, 0, 'opened', '-c', <SID>GetCurrentItem()) |
          \  endif
    nnoremap <silent> <buffer> o :PChangesOpened<CR>
    command! -buffer -nargs=0 PChangesDiff
          \ :if getline('.') =~# " \\*pending\\* '" |
          \    call <SID>diffHdlr(0, 0, '++c', <SID>GetCurrentItem()) |
          \  else |
          \    call <SID>PFIF(0, 0, 'describe', (PFGet('s:defaultDiffOptions')
          \                 =~ '^\s*$' ? '-dd' : PFGet('s:defaultDiffOptions')),
          \                   <SID>GetCurrentItem()) |
          \  endif
    nnoremap <silent> <buffer> d :PChangesDiff<CR>
    command! -buffer -nargs=0 PItemOpen
          \ :if getline('.') =~# " \\*pending\\* '" |
          \    call <SID>PFIF(0, 0, 'change', <SID>GetCurrentItem()) |
          \  else |
          \    call <SID>PFIF(0, 0, 'describe', '-dd', <SID>GetCurrentItem()) |
          \  endif

    call s:EndBufSetup()
  endif
endfunction

function! s:labelsHdlr(scriptOrigin, outputType, ...)
  exec MakeArgumentString()
  exec "let retVal = s:PFIF(a:scriptOrigin + 1, a:outputType, 'labels', " .
        \ argumentString . ")"

  if s:StartBufSetup()
    command! -buffer -nargs=0 PLabelsSyncClient
          \ :call <SID>LabelsSyncClientToLabel()
    nnoremap <silent> <buffer> S :PLabelsSyncClient<CR>
    command! -buffer -nargs=0 PLabelsSyncLabel
          \ :call <SID>LabelsSyncLabelToClient()
    nnoremap <silent> <buffer> C :PLabelsSyncLabel<CR>
    command! -buffer -nargs=0 PLabelsFiles :call <SID>PFIF(0, 0, '++n', 'files',
          \ '//...@'. <SID>GetCurrentItem())
    nnoremap <silent> <buffer> I :PLabelsFiles<CR>
    command! -buffer -nargs=0 PLabelsTemplate :call <SID>PFIF(0, 0, '++A',
          \ 'label', '-t', <SID>GetCurrentItem())
    nnoremap <silent> <buffer> P :PLabelsTemplate<CR>

    call s:EndBufSetup()
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

  if s:StartBufSetup()
    command! -buffer -nargs=0 PHelpSelect
          \ :call <SID>helpHdlr(0, 0, expand("<cword>"))
    nnoremap <silent> <buffer> <CR> :PHelpSelect<CR>
    nnoremap <silent> <buffer> K :PHelpSelect<CR>
    nnoremap <silent> <buffer> <2-LeftMouse> :PHelpSelect<CR>
    call AddNotifyWindowClose(s:helpWinName, s:myScriptId . "RestoreWindows")
    if helpWin == -1 " Resize only when it was not already visible.
      exec "resize " . 20
    endif
    redraw | echo
          \ "Press <CR>/K/<2-LeftMouse> to drilldown on perforce help keywords."

    call s:EndBufSetup()
  endif
  return retVal
endfunction

" Built-in command handlers {{{
function! s:VDiffHandler()
  let nArgs = MvNumberOfElements(s:p4Arguments, s:SPACE_AS_SEP, ' ')
  if nArgs > 2
    return s:SyntaxError("vdiff: Too many arguments.")
  endif

  let firstFile = ''
  let secondFile = ''
  if nArgs == 2
    let firstFile = MvElementAt(s:p4Arguments, s:SPACE_AS_SEP, 0, ' ')
    let secondFile = MvElementAt(s:p4Arguments, s:SPACE_AS_SEP, 1, ' ')
  elseif nArgs == 1
    let secondFile = s:p4Arguments
  else
    let secondFile = s:EscapeFileName(s:GetCurFileName())
  endif
  if firstFile == ''
    let firstFile = s:ConvertToDepotPath(secondFile)
  endif
  call s:VDiffImpl(firstFile, secondFile, 0)
endfunction

function! s:VDiff2Handler()
  if MvNumberOfElements(s:p4Arguments, s:SPACE_AS_SEP, ' ') > 2
    return s:SyntaxError("vdiff2: Too many arguments")
  endif

  let s:p4Arguments = s:GetDiff2Args()

  let firstFile = MvElementAt(s:p4Arguments, s:SPACE_AS_SEP, 0, ' ')
  let secondFile = MvElementAt(s:p4Arguments, s:SPACE_AS_SEP, 1, ' ')
  call s:VDiffImpl(firstFile, secondFile, 1)
endfunction

function! s:VDiffImpl(firstFile, secondFile, preferDepotPaths)
  let firstFile = a:firstFile
  let secondFile = a:secondFile

  if a:preferDepotPaths || s:PathRefersToDepot(firstFile)
    let firstFile = s:ConvertToDepotPath(firstFile)
    let tempFile1 = s:MakeTempName(firstFile)
  else
    let tempFile1 = firstFile
  endif
  if a:preferDepotPaths || s:PathRefersToDepot(secondFile)
    let secondFile = s:ConvertToDepotPath(secondFile)
    let tempFile2 = s:MakeTempName(secondFile)
  else
    let tempFile2 = secondFile
  endif
  if firstFile =~# s:EMPTY_STR || secondFile =~# s:EMPTY_STR ||
        \ (tempFile1 ==# tempFile2)
    return s:SyntaxError("diff requires two distinct files as arguments.")
  endif

  if s:IsDepotPath(firstFile)
    let s:p4Command = 'print'
    let s:p4CmdOptions = '-q'
    let s:p4WinName = tempFile1
    let s:p4Arguments = firstFile
    call s:PFIF(2, 0, 'print')
    if s:errCode != 0
      return
    endif
  else
    let v:errmsg = ''
    silent! exec 'split' firstFile
    if v:errmsg != ""
      return s:ShowVimError("Error opening file: ".firstFile."\n".v:errmsg, '')
    endif
  endif
  diffthis
  wincmd K

  let _splitCommand = s:splitCommand
  let s:splitCommand = 'vsplit'
  let _splitright = &splitright
  set splitright
  try
    if s:IsDepotPath(secondFile)
      let s:p4Command = 'print'
      let s:p4CmdOptions = '-q'
      let s:p4WinName = tempFile2
      let s:p4Arguments = secondFile
      call s:PFIF(2, 0, 'print')
      if s:errCode != 0
        return
      endif
    else
      let v:errmsg = ''
      silent! exec 'vsplit' secondFile
      if v:errmsg != ""
        return s:ShowVimError("Error opening file: ".secondFile."\n".v:errmsg, '')
      endif
    endif
  finally
    let s:splitCommand = _splitCommand
    let &splitright = _splitright
  endtry
  diffthis
  wincmd _
endfunction

" Returns a fileName in the temp directory that is unique for the branch and
"   revision specified in the fileName.
function! s:MakeTempName(filePath)
  let depotPath = s:ConvertToDepotPath(a:filePath)
  if depotPath =~# s:EMPTY_STR
    return ''
  endif
  let tmpName = s:tempDir . '/'
  let branch = s:GetBranchName(depotPath)
  if branch !~# s:EMPTY_STR
    let tmpName = tmpName . branch . '-'
  endif
  let revSpec = s:GetRevisionSpecifier(depotPath)
  if revSpec !~# s:EMPTY_STR
    let tmpName = tmpName . substitute(strpart(revSpec, 1), '/', '_', 'g') . '-'
  endif
  return tmpName . fnamemodify(substitute(a:filePath, '\\*#\d\+$', '', ''),
        \ ':t')
endfunction

function! s:ExecHandler()
  if s:p4Arguments !~# s:EMPTY_STR
    echo s:p4Arguments
    let cmdHadBang = 0
    let cmd = s:p4Arguments
    if cmd =~# '^\s*!'
      let cmdHadBang = 1
      let cmd = substitute(cmd, '^.*!', '', '')
      " FIXME: Pipe itself needs to be escaped, and they could be chained.
      let cmd = EscapeCommand(MvElementAt(cmd, s:SPACE_AS_SEP, 0, ' '),
            \ MvRemoveElementAt(cmd, s:SPACE_AS_SEP, 0, ' '), s:p4Pipe)
    endif
    let cmd = Escape(cmd, '#%!')
    try
      exec (cmdHadBang ? '!' : '').cmd
    catch
      let v:errmsg = substitute(v:exception, '^[^:]\+:', '', '')
      call s:ShowVimError(v:errmsg, v:throwpoint)
    endtry
  endif
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
      if codelineStr =~# s:EMPTY_STR
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

" Interactively change the port/client/user. {{{
function! s:SwitchPortClientUser()
  let p4Port = s:PromptFor(0, s:useGUIDialogs, "Port: ", s:_('p4Port'))
  let p4Client = s:PromptFor(0, s:useGUIDialogs, "Client: ", s:_('p4Client'))
  let p4User = s:PromptFor(0, s:useGUIDialogs, "User: ", s:_('p4User'))
  call s:PFSwitch(1, p4Port, p4Client, p4User)
endfunction

" No args: Print presets and prompt user to select a preset.
" Number: Select that numbered preset.
" port [client] [user]: Set the specified settings.
function! s:PFSwitch(updateClientRoot, ...)
  let nSets = MvNumberOfElements(s:p4Presets, ',')
  if a:0 == 0 || match(a:1, '^\d\+$') == 0
    let selPreset = ''
    if a:0 == 0
      if nSets == 0
        call s:EchoMessage("No sets to select from.", 'Error')
        return
      endif

      let selPreset = MvPromptForElement(s:p4Presets, ',', -1,
            \ "Select the setting: ", -1, s:useGUIDialogs)
    else
      let index = a:1 + 0
      if index >= nSets
        call s:EchoMessage("Not that many sets.", 'Error')
        return
      endif
      let selPreset = MvElementAt(s:p4Presets, ',', index)
    endif
    if selPreset == ''
      return
    endif
    let argumentString = CreateArgString(selPreset, s:SPACE_AS_SEP, ' ')
  else
    exec MakeArgumentString()
  endif
  exec 'call s:PSwitchHelper(a:updateClientRoot, ' . argumentString . ')'

  " Loop through all the buffers and invalidate the filestatuses.
  let lastBufNr = bufnr('$')
  let i = 1
  while i <= lastBufNr
    if bufexists(i) && getbufvar(i, '&buftype') == ''
      call s:ResetFileStatusForBuffer(i)
    endif
    let i = i + 1
  endwhile
endfunction

function! s:PSwitchHelper(updateClientRoot, ...)
  let p4Port = a:1
  let p4Client = s:_('p4Client')
  let p4User = s:_('p4User')
  if a:0 > 1
    let p4Client = a:2
  endif
  if a:0 > 2
    let p4User = a:3
  endif
  if ! s:SetPortClientUser(p4Port, p4Client, p4User)
    return
  endif

  if a:updateClientRoot
    if s:p4Port !=# 'P4CONFIG'
      call s:GetClientInfo()
    else
      let s:clientRoot = '' " Since the client is chosen dynamically.
    endif
  endif
endfunction

function! s:SetPortClientUser(port, client, user)
  if s:p4Port ==# a:port && s:p4Client ==# a:client && s:p4User ==# a:user
    return 0
  endif

  let s:p4Port = a:port
  let s:p4Client = a:client
  let s:p4User = a:user
  let s:p4Password = ''
  return 1
endfunction

function! s:PFSwitchComplete(ArgLead, CmdLine, CursorPos)
  return substitute(s:p4Presets, ',', "\n", 'g')
endfunction
" port/client/user }}}

function! s:PHelpComplete(ArgLead, CmdLine, CursorPos)
  if s:p4KnownCmdsCompStr == ''
    let s:p4KnownCmdsCompStr = substitute(s:p4KnownCmds, ',', "\n", 'g')
  endif
  return s:p4KnownCmdsCompStr.
          \ "simple\ncommands\nenvironment\nfiletypes\njobview\nrevisions\n".
          \ "usage\nviews\n"
endfunction
 
" Handler for opened command.
function! s:OpenFile(scriptOrigin, outputType, fileName) " {{{
  if filereadable(a:fileName)
    if a:outputType == 0
      let curWin = winnr()
      let bufNr = FindBufferForName(a:fileName)
      let winnr = bufwinnr(bufNr)
      if winnr != -1
        exec winnr.'wincmd w'
      else
        wincmd p
      endif
      if curWin != winnr() && &previewwindow
        wincmd p " Don't use preview window.
      endif
      if winnr() == curWin
        split
      endif
      if winbufnr(winnr()) != bufNr
        if bufNr != -1
          exec "buffer" bufNr | " Preserves cursor position.
        else
          exec "edit " . a:fileName
        endif
      endif
    else
      exec "pedit " . a:fileName
    endif
  else
    call s:printHdlr(0, a:outputType, a:fileName)
  endif
endfunction " }}}

function! s:DescribeGetCurrentItem() " {{{
  if getline(".") ==# "\t<SHOW DIFFS>"
    let b:p4FullCmd = MvRemovePattern(b:p4FullCmd, s:SPACE_AS_SEP,
          \ "[\"']\\?-s[\"']\\?", ' ') " -s possibly sorrounded by quotes.
    call s:PFRefreshActivePane()
    call s:SetupDiff()
    return ""
  else
    return s:GetCurrentDepotFile(line('.'))
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
  if itemHandler ==# 's:PFIF'
    return "call s:PFIF(1, " . a:outputType . ", '" . handlerCmd . "', " .
          \ a:args . ")"
  elseif itemHandler !~# s:EMPTY_STR
    return 'call ' . itemHandler . '(0, ' . a:outputType . ', ' . a:args . ')'
  endif
  return itemHandler
endfunction " }}}

function! s:OpenCurrentItem(outputType) " {{{
  let curItem = s:GetOpenItem()
  if curItem !~# s:EMPTY_STR
    let commandHandler = s:getCommandItemHandler(a:outputType, b:p4Command,
          \ "'" . curItem . "'")
    if commandHandler !~# s:EMPTY_STR
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

function! s:GetOpenItem() " {{{
  if exists("b:p4Command") && exists("s:{b:p4Command}OpenItemExpr")
    exec "return " s:{b:p4Command}OpenItemExpr
  endif
  return s:GetCurrentItem()
endfunction " }}}

function! s:DeleteCurrentItem() " {{{
  let curItem = s:GetCurrentItem()
  if curItem !~# s:EMPTY_STR
    let answer = s:ConfirmMessage("Are you sure you want to delete " .
          \ curItem . "?", "&Yes\n&No", 2, "Question")
    if answer == 1
      let commandHandler = s:getCommandItemHandler(2, b:p4Command,
            \ "'-d', '" . curItem . "'")
      if commandHandler !~# s:EMPTY_STR
        exec commandHandler
      endif
      if v:shell_error == ""
        call s:PFRefreshActivePane()
      endif
    endif
  endif
endfunction " }}}

function! s:LaunchCurrentFile() " {{{
  if s:fileLauncher =~# s:EMPTY_STR
    call s:ConfirmMessage("There was no launcher command configured to launch ".
          \ "this item, use g:p4FileLauncher to configure." , "OK", 1, "Error")
    return
  endif
  let curItem = s:GetCurrentItem()
  if curItem !~# s:EMPTY_STR
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
  if file1 !~# s:EMPTY_STR
    let file2 = s:GetCurrentDepotFile(line2)
    if file2 !~# s:EMPTY_STR && file2 != file1
      " file2 will be older than file1.
      exec "call s:PFIF(0, -2, \"" . (s:useVimDiff2 ? 'vdiff2' : 'diff2') .
            \ "\", file2, file1)"
    endif
  endif
endfunction " }}}

function! s:FilelogSyncToCurrentItem() " {{{
  let curItem = s:GetCurrentItem()
  if curItem !~# s:EMPTY_STR
    let answer = s:ConfirmMessage("Do you want to sync to: " . curItem . " ?",
          \ "&Yes\n&No", 2, "Question")
    if answer == 1
      call s:PFIF(1, -2, 'sync', curItem)
    endif
  endif
endfunction " }}}

function! s:ChangesSubmitChangeList() " {{{
  let curItem = s:GetCurrentItem()
  if curItem !~# s:EMPTY_STR
    let answer = s:ConfirmMessage("Do you want to submit change list: " .
          \ curItem . " ?", "&Yes\n&No", 2, "Question")
    if answer == 1
      call s:submitHdlr(0, 0, '++y', 'submit', '-c', curItem)
    endif
  endif
endfunction " }}}

function! s:LabelsSyncClientToLabel() " {{{
  let curItem = s:GetCurrentItem()
  if curItem !~# s:EMPTY_STR
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
  if curItem !~# s:EMPTY_STR
    let answer = s:ConfirmMessage("Do you want to sync label: " . curItem .
          \ " to client " . s:_('p4Client') . " ?", "&Yes\n&No", 2, "Question")
    if answer == 1
      exec "let retVal = s:PFIF(1, 1, 'labelsync', '-l', curItem)"
      return retVal
    endif
  endif
endfunction " }}}

function! s:FilelogDescribeChange() " {{{
  let changeNo = matchstr(getline("."), ' change \zs\d\+\ze ')
  if changeNo !~# s:EMPTY_STR
    exec "call s:describeHdlr(0, 1, changeNo)"
  endif
endfunction " }}}

function! s:SetupFileBrowse() " {{{
  " For now, assume that a new window is created and we are in the new window.
  exec "setlocal includeexpr=" . s:myScriptId . "ConvertToLocalPath(v:fname)"

  " No meaning for delete.
  silent! nunmap <buffer> D
  silent! delcommand PItemDelete
  command! -buffer -nargs=0 PFileDiff :call <SID>diffHdlr(0, 1,
        \ <SID>GetCurrentDepotFile(line(".")))
  nnoremap <silent> <buffer> D :PFileDiff<CR>
  command! -buffer -nargs=0 PFileProps :call <SID>PFIF(1, 0, 'fstat', '-C',
        \ <SID>GetCurrentDepotFile(line(".")))
  nnoremap <silent> <buffer> P :PFileProps<CR>
  command! -buffer -nargs=0 PFileLog :call <SID>PFIF(1, 0, 'filelog',
        \ <SID>GetCurrentDepotFile(line(".")))
  command! -buffer -nargs=0 PFileEdit :call <SID>PFIF(1, -1, 'edit',
        \ <SID>GetCurrentItem())
  nnoremap <silent> <buffer> I :PFileEdit<CR>
  command! -buffer -nargs=0 PFileRevert :call <SID>PFIF(1, -1, 'revert',
        \ <SID>GetCurrentItem())
  nnoremap <silent> <buffer> R :PFileRevert \| PFRefreshActivePane<CR>
  command! -buffer -nargs=0 PFilePrint
        \ :if getline('.') !~# '(\%(u\|ux\)binary)$' |
        \   call <SID>printHdlr(0, 0,
        \   substitute(<SID>GetCurrentDepotFile(line('.')), '#[^#]\+$', '', '').
        \   '#'.
        \   ((getline(".") =~# '#\d\+ - delete change') ?
        \    matchstr(getline('.'), '#\zs\d\+\ze - ') - 1 :
        \    matchstr(getline('.'), '#\zs\d\+\ze - '))
        \   ) |
        \ else |
        \   echo 'PFilePrint: Binary file... ignored.' |
        \ endif
  nnoremap <silent> <buffer> p :PFilePrint<CR>
  command! -buffer -nargs=0 PFileGet :call <SID>PFIF(1, -1, 'sync',
        \ <SID>GetCurrentDepotFile(line(".")))
  command! -buffer -nargs=0 PFileSync :call <SID>PFIF(1, -1, 'sync',
        \ <SID>GetCurrentItem())
  nnoremap <silent> <buffer> S :PFileSync<CR>
  command! -buffer -nargs=0 PFileChange :call <SID>changeHdlr(0, 0, 
        \ <SID>GetCurrentChangeNumber(line(".")))
  nnoremap <silent> <buffer> C :PFileChange<CR>
  command! -buffer -nargs=0 PFileLaunch :call <SID>LaunchCurrentFile()
  nnoremap <silent> <buffer> A :PFileLaunch<CR>
endfunction " }}}

function! s:SetupDiff() " {{{
  setlocal ft=diff
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
  if changeNo ==# 'default'
    let changeNo = ''
  endif
  return changeNo
endfunction " }}}

function! s:PChangesDescribeCurrentItem() " {{{
  let currentChangeNo = s:GetCurrentItem()
  if currentChangeNo !~# s:EMPTY_STR
    call s:describeHdlr(0, 1, '-s', currentChangeNo)

    " For pending changelist, we have to run a separate opened command to get
    "   the list of opened files. We don't need <SHOW DIFFS> line, as it is
    "   still not subbmitted. This works like p4win.
    if getline('.') =~# "^.* \\*pending\\* '.*$"
      wincmd p
      setlocal modifiable
      call setline(line('$'), "Affected files ...")
      call append(line('$'), "")
      call append(line('$'), "")
      exec 'call s:PW(line("$"), line("$"), 0, "opened", "-c", currentChangeNo)'
      wincmd p
    endif
  endif
endfunction " }}}

" Return the current value of the setting.
function! s:GetSettingValue(setting) " {{{
  let value = ''
  if a:setting !~# s:EMPTY_STR
    let setting = a:setting
    if setting =~# '^g:p4'
      let setting = strpart(setting, 4)
    endif
    if exists('{setting}')
      let value = {setting}
    elseif exists('s:{setting}')
      let value = s:{setting}
    elseif exists('s:p4{setting}')
      let value = s:p4{setting}
    else
      if exists('s:settingsMap{setting}')
        let value = s:{s:settingsMap{setting}}
      else
        let localVar = substitute(setting, '^\(\u\)', '\L\1', '')
        if exists('s:{localVar}')
          let value = s:{localVar}
        else
          echoerr "Internal error detected, couldn't locate value for " .
                \ setting
        endif
      endif
    endif
  endif
  return value
endfunction " }}}

" {{{
function! s:PFSettings(...)
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
  if a:0 > 0
    let selectedSetting = a:1
  else
    let selectedSetting = MvPromptForElement2(settings, ',', -1,
          \ "Select the setting: ", -1, 0, 3)
  endif
  if selectedSetting !~# s:EMPTY_STR
    let oldVal = s:GetSettingValue(selectedSetting)
    if a:0 > 1
      let newVal = a:2
      echo 'Current value for' selectedSetting.': "'.oldVal.'" New value: "'.
            \ newVal.'"'
    else
      let newVal = input('Current value for ' . selectedSetting . ' is: ' .
            \ oldVal . "\nEnter new value: ", oldVal)
    endif
    if newVal != oldVal
      let g:p4{selectedSetting} = newVal
      call s:Initialize()
    endif
  endif
endfunction

function! s:PFSettingsComplete(ArgLead, CmdLine, CursorPos)
  if s:settingsCompStr == ''
    let s:settingsCompStr = substitute(s:settings, ',', "\n", 'g')
  endif
  return s:settingsCompStr
endfunction
" }}}

function! s:MakeRevStr(ver) " {{{
  let verStr = ''
  if a:ver =~# '^[#@&]'
    let verStr = a:ver
  elseif a:ver =~# '^[-+]\?\d\+\>\|^none\>\|^head\>\|^have\>'
    let verStr = '#' . a:ver
  elseif a:ver !~# s:EMPTY_STR
    let verStr = '@' . a:ver
  endif
  return verStr
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

function! s:GetDiff2Args()
  let p4Arguments = s:p4Arguments
  " The pattern takes care of ignoring protected spaces as separators.
  let nArgs = MvNumberOfElements(p4Arguments, s:SPACE_AS_SEP, ' ')
  if nArgs < 2
    if nArgs == 0
      let file = s:EscapeFileName(s:GetCurFileName())
    else
      let file = p4Arguments
    endif
    let ver1 = s:PromptFor(0, s:useGUIDialogs, "Version1? ", '')
    let ver2 = s:PromptFor(0, s:useGUIDialogs, "Version2? ", '')
    let p4Arguments = file . s:MakeRevStr(ver1) . " " . file .
          \ s:MakeRevStr(ver2)
  endif
  return p4Arguments
endfunction

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
""" END: Helper functions }}}


""" BEGIN: Middleware functions {{{

" Filter contents through p4.
function! s:PW(fline, lline, scriptOrigin, ...) range
  exec MakeArgumentString()
  if a:scriptOrigin != 2
    exec "call s:ParseOptions(a:fline, a:lline, 0, '++f', " .
          \ argumentString . ")"
  else
    let s:commandMode = s:CM_FILTER
  endif
  setlocal modifiable
  let retVal = s:PFIF(2, 5, s:p4Command)
  return retVal
endfunction

" Generate raw output into a new window.
function! s:PFRaw(...)
  exec MakeArgumentString()
  exec "call s:ParseOptions(1, line('$'), 0, " . argumentString . ")"

  let retVal = s:PFImpl(1, 0, "")
  return retVal
endfunction

function! s:W(quitWhenDone, commandName, ...)
  exec MakeArgumentString()
  exec "call s:ParseOptionsIF(1, line('$'), 0, 5, a:commandName, " .
        \ argumentString . ")"
  let s:p4CmdOptions = s:p4CmdOptions . ' -i'
  let retVal = s:PW(1, line('$'), 2)
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
      try
        silent! keepjumps normal! 1G"zyG
        undo
        " Make the below changes such a way that they can't be undo. This in a
        "   way, forces Vim to create an undo point, so that user can later
        "   undo and see these changes, with proper change number and status
        "   in place. This has the side effect of loosing the previous undo
        "   history, which can be considered desirable, as otherwise the user
        "   can undo this change and back to the new state.
        set undolevels=-1
        if search("^Change:\tnew$")
          silent! keepjumps call setline('.', "Change:\t" . newChangeNo)
        endif
        if search("^Status:\tnew$")
          silent! keepjumps call setline('.', "Status:\tpending")
        endif
        setl nomodified
        let &undolevels=_undolevels
        " Creating an undo point is actually undesirable, as the user will be
        "   able to undo the above change and get back to the new state.
        " Create an an undo point, so that user can later undo and see these
        "   changes, with proper change number and status in place.
        "exec "normal! i\<C-G>u"
        silent! 0,$delete _
        silent! put! =@z
        call s:PFSetupForSpec()
      finally
        let @z = _z
        let &undolevels=_undolevels
      endtry
      let b:p4FullCmd = s:CreateFullCmd('-o change ' . newChangeNo)
    endif
  endif
endfunction

function! s:ParseOptionsIF(fline, lline, scriptOrigin, outputType, commandName,
      \ ...) " range
  exec MakeArgumentString()

  " There are multiple possibilities here:
  "   - scriptOrigin, in which case the commandName contains the name of the
  "     command, but the varArgs also may contain it.
  "   - commandOrigin, in which case the commandName may actually be the
  "     name of the command, or it may be the first argument to p4 itself, in
  "     any case we will let p4 handle the error cases.
  if MvContainsElement(s:allCommands, ',', a:commandName) && a:scriptOrigin
    exec "call s:ParseOptions(a:fline, a:lline, a:outputType, " .
          \ argumentString . ")"
    " Add a:commandName only if it doesn't already exist in the var args.
    " Handles cases like "PF help submit" and "PF -c <client> change changeno#",
    "   where the commandName need not be at the starting and there could be
    "   more than one valid commandNames (help and submit).
    if s:p4Command != a:commandName
      exec "call s:ParseOptions(a:fline, a:lline, a:outputType, a:commandName, "
            \ . argumentString . ")"
    endif
  else
    exec "call s:ParseOptions(a:fline, a:lline, a:outputType, a:commandName, " .
          \ argumentString . ")"
  endif
endfunction

" PFIF {{{
" The commandName may not be the perforce command when it is not of script
"   origin (called directly from a command), but it should be always command
"   name, when it is script origin.
" scriptOrigin: An integer indicating the origin of the call. 
"   0 - Originated directly from the user, so should redirect to the specific
"       command handler (if exists), after some basic processing.
"   1 - Originated from the script, continue with the full processing.
"   2 - Same as 1 but, avoid parsing arguments (they are already parsed by the
"       caller).
function! s:PFIF(scriptOrigin, outputType, commandName, ...)
  exec MakeArgumentString()
  return s:PFrangeIF(1, line('$'), a:scriptOrigin, a:outputType,
        \ a:commandName, '/argumentString/', argumentString)
endfunction

function! s:PFrangeIF(fline, lline, scriptOrigin, outputType, commandName, ...)
  let output = '' " Used only when mode is s:CM_DISPLAY
  if a:scriptOrigin != 2
    if a:0 > 1 && a:1 ==# '/argumentString/'
      let argumentString = a:2
    else
      exec MakeArgumentString()
    endif
    exec "call s:ParseOptionsIF(a:fline, a:lline, "
          \ . "a:scriptOrigin, a:outputType, a:commandName, " .
          \ argumentString . ")"
    if s:commandMode ==# s:CM_DISPLAY
      let output = DeEscape(s:p4Arguments)
      let s:p4Arguments = ''
      let s:p4WinName = s:MakeWindowName()
    endif
  elseif s:commandMode ==# s:CM_DISPLAY
    let output = a:1
  endif

  " FIXME: May be we should not support specifying -ve outputType using ++o.
  let outputIdx = MvIndexOfPattern(s:p4Options, s:SPACE_AS_SEP,
        \ '++o\s\+\d\+', ' ') " Searches including output mode.
  if outputIdx != -1
    let s:outputType = MvElementAt(s:p4Options, s:SPACE_AS_SEP, outputIdx + 1,
          \ ' ') + 0
  endif
  " If this command doesn't care about -ve outputType, then just take care of
  "   it right here.
  if s:outputType < 0 &&
        \ ! MvContainsElement(s:limitLinesInDlgCmds, ',', s:p4Command)
    let s:outputType = a:outputType + 2
  endif
  if ! a:scriptOrigin
    if exists('*s:{s:p4Command}Hdlr')
      return s:{s:p4Command}Hdlr(1, s:outputType, a:commandName)
    endif
  endif
  " Temporarily switch to type "4" such that we can look into the number of
  "   lines in the output and conditionally make it (0,1) or 2.
  if s:outputType < 0
    let s:outputType = 4
  endif

 
  let modifyWindowName = 0
  let dontProcess = MvContainsElement(s:p4Options, s:SPACE_AS_SEP, '++n', ' ')
  let noDefaultArg = MvContainsElement(s:p4Options, s:SPACE_AS_SEP, '++N', ' ')
  " If there is a confirm message for this command, then first prompt user.
  let dontConfirm = MvContainsElement(s:p4Options, s:SPACE_AS_SEP, '++y',
        \ ' ')
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
        \ ! MvContainsPattern(s:p4CmdOptions, s:SPACE_AS_SEP, '-d.*', ' ')
        \ && s:defaultDiffOptions !~# s:EMPTY_STR
    let s:p4CmdOptions = s:defaultDiffOptions . ' ' . s:p4CmdOptions
    let modifyWindowName = 1
  endif

  " Process p4Arguments, unless explicitly not requested to do so, or the '-x'
  "   option to read arguments from a file is given.
  if ! dontProcess && ! noDefaultArg && s:p4Arguments =~# s:EMPTY_STR &&
        \ !MvContainsElement(s:p4Options, s:SPACE_AS_SEP, '-x', ' ')
    if (MvContainsElement(s:askUserCmds, ',', s:p4Command) &&
          \ ! MvContainsElement(s:p4CmdOptions, s:SPACE_AS_SEP, '-i', ' ')) ||
          \ MvContainsElement(s:p4Options, s:SPACE_AS_SEP, '++A', ' ')
      if MvContainsElement(s:genericPromptCmds, ',', s:p4Command)
        let prompt = 'Enter arguments for ' . s:p4Command . ': '
      else
        let prompt = "Enter the " . s:p4Command . " name: "
      endif
      let additionalArg = s:PromptFor(0, s:useGUIDialogs, prompt, '')
      if additionalArg =~# s:EMPTY_STR
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
      let s:p4Arguments = s:EscapeFileName(s:GetCurFileName())
      let modifyWindowName = 1
    endif
  elseif ! dontProcess && match(s:p4Arguments, '[#@&]') != -1
    let p4Arguments = s:p4Arguments
    " If there is an argument without a filename, then assume it is the current
    "   file.
    " Pattern is the start of line or whitespace followed by an unprotected
    "   [#@&] with a revision/codeline specifier and then again followed by
    "   end of line or whitespace.
    let p4Arguments = substitute(p4Arguments,
          \ '\%(^\|\%('.s:SPACE_AS_SEP.'\)\+\)\@<=' .
          \ '\\\@<!\%(\\\\\)*\(\%([#@&]\%([-+]\?\d\+\|\S\+\)\)\+\)' . 
          \ '\%(\%('.s:SPACE_AS_SEP.'\)\+\|$\)\@=',
          \ '\=s:EscapeFileName(s:GetCurFileName()) . submatch(1) .'.
          \   ' submatch(2)',
          \ 'g')

    " Adjust the revisions for offsets.
    " Pattern is a series of non-space chars or protected spaces (filename)
    " followed by the revision specifier.
    let p4Arguments = substitute(p4Arguments,
          \ '\(\%(\S\|\\\@<!\%(\\\\\)*\\ \)\+\)[\\]*#\([-+]\d\+\)',
          \ '\=submatch(1) . "#" . ' .
          \ 's:AdjustRevision(submatch(1), submatch(2))', 'g')
    if s:errCode != 0
      return ''
    endif

    " Unprotected '&'.
    if match(p4Arguments, '\\\@<!\%(\\\\\)*&') != -1
      " CAUTION: Make sure the view mappings are generated before
      "   s:PFGetAltFiles() gets invoked, otherwise the call results in a
      "   recursive |sub-replace-special| and corrupts the mappings.
      call s:CondUpdateViewMappings()
      " Pattern is a series of non-space chars or protected spaces (filename)
      "   including the revision specifier, if any, followed by the alternative
      "   codeline specifier.
      let p4Arguments = substitute(p4Arguments,
            \ '\(\%([^ ]\|\\\@<!\%(\\\\\)*\\ \)\+' .
            \ '\%([\\]*[#@]\%(-\?\d\+\|\w\+\)\)\?\)\\\@<!\%(\\\\\)*&\(\w\+\)',
            \ '\=s:PFGetAltFiles(submatch(2), submatch(1))', 'g')
    endif
    let p4Arguments = UnEscape(p4Arguments, '&@')

    let s:p4Arguments = p4Arguments
    let modifyWindowName = 1
  endif

  let testMode = 0
  if MvContainsElement(s:p4Options, s:SPACE_AS_SEP, '++T', ' ')
    let testMode = 1 " Dry run, opens the window.
  elseif MvContainsElement(s:p4Options, s:SPACE_AS_SEP, '++D', ' ')
    let testMode = 2 " Debug. Opens the window and displays the command.
  endif

  " Remove all the built-in options.
  let _p4Options = s:p4Options
  let s:p4Options = substitute(s:p4Options, '++\S\+\%(\s\+[^-+]\+\|\s\+\)\?',
        \ '', 'g')
  if s:p4Options != _p4Options
    let modifyWindowName = 1
  endif
  if MvContainsElement(s:diffCmds, ',', s:p4Command)
    " Remove the dummy option, if exists (see |perforce-default-diff-format|).
    let s:p4CmdOptions = MvRemoveElement(s:p4CmdOptions, s:SPACE_AS_SEP, '-d',
          \ ' ')
    let modifyWindowName = 1
  endif

  if s:p4Command ==# 'help'
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
    if ((s:p4Command ==# 'submit' &&
          \ ! MvContainsElement(s:p4CmdOptions, s:SPACE_AS_SEP, '-c', ' ')) ||
      \ (! MvContainsElement(s:specOnlyCmds, ',', s:p4Command) &&
          \ ! MvContainsElement(s:p4CmdOptions, s:SPACE_AS_SEP, '-d', ' '))) &&
     \ s:outputType == 0
      let specMode = 1
    endif
  endif
  
  let navigateCmd = 0
  if MvContainsElement(s:navigateCmds, ',', s:p4Command)
    let navigateCmd = 1
  endif

  let retryCount = 0
  let retVal = ''
  " FIXME: When is "not clearing" (value 2) useful at all?
  let clearBuffer = (testMode != 2 ? ! navigateCmd : 2)
  " CAUTION: This is like a do..while loop, but not exactly the same, be
  " careful using continue, the counter will not get incremented.
  while 1
    let retVal = s:PFImpl(clearBuffer, testMode, output)

    " Everything else in this loop is for password support.
    if s:errCode == 0
      break
    else
      if retVal =~# s:EMPTY_STR
        let retVal = getline(1)
      endif
      " FIXME: Works only with English as the language.
      if retVal =~# 'Perforce password (P4PASSWD) invalid or unset.'
        let p4Password = inputsecret("Password required for user " .
              \ s:_('p4User') . ": ", s:p4Password)
        if p4Password ==# s:p4Password
          break
        endif
        let s:p4Password = p4Password
      else
        break
      endif
    endif
    let retryCount = retryCount + 1
    if retryCount > 2
      break
    endif
  endwhile

  " If the original output type was -1, then check if the output is of too
  "   many lines to display in a dialog.
  if a:outputType < 0 && s:outputType == 4
    let nLines = strlen(substitute(retVal, "[^\n]", "", "g"))
    if nLines > s:maxLinesInDialog
      " Open the window now.
      let s:outputType = a:outputType + 2
      let p4Options = s:GetP4Options()
      " We want the window to be opened even on errors, to match that of
      "   regular behavior.
      let errCode = s:errCode
      try
        let s:errCode = 0
        if s:GotoWindow(clearBuffer, s:GetCurFileName(), 1) == 0
          silent! put! =retVal
          call s:InitWindow(g:p4FullCmd, p4Options)
          " Go back and fix the current context in the stack for the change in
          "   value of s:outputType.
        endif
      finally
        let s:errCode = errCode
      endtry
    elseif retVal !~ s:EMPTY_STR
      let s:outputType = 2
      if s:errCode == 0
        call s:ConfirmMessage(retVal, "OK", 1, "Info")
      endif
    endif
    if s:errCode != 0
      call s:CheckShellError(retVal, s:outputType)
    endif
  endif

  if s:errCode != 0
    return retVal
  endif

  " outputType < 0 is used only for the top-level calls, so it is unlikely
  "   that the stack contains multiple perforce commands (unless when the call
  "   gets redirected through :PF), and even if it does, it is very unlikely
  "   that they are for the same perforce command, so just check the
  "   s:p4Command value.
  " CAUTION: It is likely that there are multiple stack items for the same
  "   command, but I am not going to bother about it for now.
  if a:outputType < 0
    if s:NumP4Contexts() > 0
      " Temporarily switch to the callers context so that we can modify and
      "   push it back on the stack.
      let curCntxtStr = s:GetP4ContextVars()
      let outputType = s:outputType
      call s:PopP4Context()
      if a:commandName ==# s:p4Command
        " Correct the outputType.
        let s:outputType = outputType
      endif
      call s:PushP4Context()
      " Restore the original context.
      call s:SetP4ContextVars(curCntxtStr)
    endif
  endif

  if s:StartBufSetup()
    " If this command has a handler for the individual items, then enable the
    " item selection commands.
    if s:getCommandItemHandler(0, s:p4Command, '') !~# s:EMPTY_STR
      call s:SetupSelectItem()
    endif

    if !MvContainsElement(s:ftNotPerforceCmds, ',', s:p4Command)
      setlocal ft=perforce
    endif

    if MvContainsElement(s:filelistCmds, ',', s:p4Command)
      call s:SetupFileBrowse()
    endif

    if s:NewWindowCreated()
      if specMode
        let argStr = ''
        if s:p4Options !~# s:EMPTY_STR
          let argStr = CreateArgString(s:p4Options, s:SPACE_AS_SEP) . ','
        endif
        " It is not possible to have an s:p4Command which is in s:allCommands
        "         and still not be the actual intended command.
        if MvContainsElement(s:allCommands, ',', s:p4Command)
          let argStr = argStr . "'" . s:p4Command . "', "
        else
          " FIXME: Why am I using b:p4Command instead of s:p4Command here ???
          let argStr = argStr . "'" . b:p4Command . "', "
        endif
        if s:p4CmdOptions !~# s:EMPTY_STR
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

    call s:EndBufSetup()
  endif

  return retVal
endfunction

function! s:PFComplete(ArgLead, CmdLine, CursorPos)
  if s:p4KnownCmdsCompStr == ''
    let s:p4KnownCmdsCompStr = substitute(s:p4KnownCmds, ',', "\n", 'g')
  endif
  if a:CmdLine =~ '^\s*P[FW] '
    let argStr = strpart(a:CmdLine, matchend(a:CmdLine, '^\s*PF '))
    let s:p4Command = ''
    if argStr !~# s:EMPTY_STR
      exec 'call s:ParseOptionsIF(-1, -1, 0, 0, ' .
            \ CreateArgString(argStr, s:SPACE_AS_SEP).')'
    endif
    if s:p4Command ==# '' || s:p4Command ==# a:ArgLead
      return s:p4KnownCmdsCompStr."\n".substitute(s:builtinCmds, ',', "\n", 'g')
    endif
  else
    let userCmd = substitute(a:CmdLine, '^\s*P\(.\)\(\w*\).*', '\l\1\2', '')
    if strlen(userCmd) < 3
      if !exists('s:shortCmdMap{userCmd}')
        throw "Perforce internal error: no map found for short command: ".
              \ userCmd
      endif
      let userCmd = s:shortCmdMap{userCmd}
    endif
    let s:p4Command = userCmd
  endif
  if s:p4Command ==# 'help'
    return s:PHelpComplete(a:ArgLead, a:CmdLine, a:CursorPos)
  endif
  if MvContainsElement(s:nofileArgsCmds, ',', s:p4Command)
    return ''
  endif

  " FIXME: Can't set command-line from user function.
  "let argLead = UserFileExpand(a:ArgLead)
  "if argLead !=# a:ArgLead
  "  let cmdLine = strpart(a:CmdLine, 0, a:CursorPos-strlen(a:ArgLead)) .
  "        \ argLead . strpart(a:CmdLine, a:CursorPos)
  "  exec "normal! \<C-\>e'".cmdLine."'\<CR>"
  "  call setcmdpos(a:CursorPos+(strlen(argLead) - strlen(a:ArgLead)))
  "  return ''
  "endif
  if a:ArgLead =~ '^//'.s:p4Depot.'/'
    " Get directory matches.
    let dirMatches = s:GetOutput('dirs', a:ArgLead, "\n", '/&')
    " Get file matches.
    let fileMatches = s:GetOutput('files', a:ArgLead, '#\d\+[^'."\n".']\+', '')
    if dirMatches !~ s:EMPTY_STR || fileMatches !~ s:EMPTY_STR
      return dirMatches.fileMatches
    else
      return ''
    endif
  endif
  return UserFileComplete(a:ArgLead, a:CmdLine, a:CursorPos, 1, '')
endfunction

function! s:GetOutput(p4Cmd, arg, pat, repl)
  let matches = s:PFIF(0, 4, a:p4Cmd, a:arg.'*')
  if s:errCode == 0
    if matches =~ 'no such file(s)'
      let matches = ''
    else
      let matches = substitute(substitute(matches, a:pat, a:repl, 'g'),
            \ "\n\n", "\n", 'g')
    endif
  endif
  return matches
endfunction
" PFIF }}}

""" START: Adopted from Tom's perforce plugin. {{{

"---------------------------------------------------------------------------
" Produce string for ruler output
function! s:P4RulerStatus()
  if exists('b:p4RulerStr') && b:p4RulerStr !~# s:EMPTY_STR
    return b:p4RulerStr
  endif
  if !exists('b:p4FStatDone') || !b:p4FStatDone
    return ''
  endif

  "let b:p4RulerStr = '[p4 '
  let b:p4RulerStr = '['
  if exists('b:p4RulerErr') && b:p4RulerErr !~# s:EMPTY_STR
    let b:p4RulerStr = b:p4RulerStr . b:p4RulerErr
  elseif !exists('b:p4HaveRev')
    let b:p4RulerStr = ''
  elseif b:p4Action =~# s:EMPTY_STR
    if b:p4OtherOpen =~# s:EMPTY_STR
      let b:p4RulerStr = b:p4RulerStr . 'unopened'
    else
      let b:p4RulerStr = b:p4RulerStr . b:p4OtherOpen . ':' . b:p4OtherAction
    endif
  else
    if b:p4Change ==# 'default' || b:p4Change =~# s:EMPTY_STR
      let b:p4RulerStr = b:p4RulerStr . b:p4Action
    else
      let b:p4RulerStr = b:p4RulerStr . b:p4Action . ':' . b:p4Change
    endif
  endif
  if exists('b:p4HaveRev') && b:p4HaveRev !~# s:EMPTY_STR
    let b:p4RulerStr = b:p4RulerStr . ' #' . b:p4HaveRev . '/' . b:p4HeadRev
  endif

  if b:p4RulerStr !~# s:EMPTY_STR
    let b:p4RulerStr = b:p4RulerStr . ']'
  endif
  return b:p4RulerStr
endfunction

function! s:GetClientInfo()
  let infoStr = ''
  call s:PushP4Context()
  try
    let infoStr = s:PFIF(0, 4, 'info')
    if s:errCode != 0
      return s:ConfirmMessage((v:errmsg != '') ? v:errmsg : infoStr, 'OK', 1,
            \ 'Error')
    endif
  finally
    call s:PopP4Context(0)
  endtry
  let s:clientRoot = CleanupFileName(s:StrExtract(infoStr,
        \ '\CClient root: [^'."\n".']\+', 13))
  let s:p4Client = s:StrExtract(infoStr, '\CClient name: [^'."\n".']\+', 13)
  let s:p4User = s:StrExtract(infoStr, '\CUser name: [^'."\n".']\+', 11)
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
  if !s:IsFileUnderDepot(expand('#'.bufNr.':p'))
    return ""
  endif

  return s:GetFileStatusImpl(bufNr)
endfunction

function! s:ResetFileStatusForBuffer(bufNr)
  " Avoid proliferating this buffer variable.
  if getbufvar(a:bufNr, 'p4FStatDone') != 0
    call setbufvar(a:bufNr, 'p4FStatDone', 0)
  endif
endfunction

"---------------------------------------------------------------------------
" Obtain file status information
function! s:GetFileStatusImpl(bufNr)
  if bufname(a:bufNr) == ""
    return ''
  endif
  let fileName = fnamemodify(bufname(a:bufNr), ':p')
  let bufNr = a:bufNr
  " If the filename matches with one of the ignore patterns, then don't do
  " status.
  if s:ignoreDefPattern !~# s:EMPTY_STR &&
        \ match(fileName, s:ignoreDefPattern) != -1
    return ''
  endif
  if s:ignoreUsrPattern !~# s:EMPTY_STR &&
        \ match(fileName, s:ignoreUsrPattern) != -1
    return ''
  endif

  call setbufvar(bufNr, 'p4RulerStr', '') " Let this be reconstructed.

  " This could very well be a recursive call, so we should save the current
  "   state.
  call s:PushP4Context()
  try
    let fileStatusStr = s:PFIF(1, 4, 'fstat', fileName)
    call setbufvar(bufNr, 'p4FStatDone', '1')

    if s:errCode != 0
      call setbufvar(bufNr, 'p4RulerErr', "<ERROR>")
      return ''
    endif
  finally
    call s:PopP4Context(0)
  endtry

  if match(fileStatusStr, ' - file(s) not in client view\.') >= 0
    call setbufvar(bufNr, 'p4RulerErr', "<Not In View>")
    " Required for optimizing out in future runs.
    call setbufvar(bufNr, 'p4HeadRev', '')
    return ''
  elseif match(fileStatusStr, ' - no such file(s).') >= 0
    call setbufvar(bufNr, 'p4RulerErr', "<Not In Depot>")
    " Required for optimizing out in future runs.
    call setbufvar(bufNr, 'p4HeadRev', '')
    return ''
  else
    call setbufvar(bufNr, 'p4RulerErr', '')
  endif

  call setbufvar(bufNr, 'p4HeadRev',
        \ s:StrExtract(fileStatusStr, '\CheadRev [0-9]\+', 8))
  "call setbufvar(bufNr, 'p4DepotFile',
  "      \ s:StrExtract(fileStatusStr, '\CdepotFile [^'."\n".']\+', 10))
  "call setbufvar(bufNr, 'p4ClientFile',
  "      \ s:StrExtract(fileStatusStr, '\CclientFile [^'."\n".']\+', 11))
  call setbufvar(bufNr, 'p4HaveRev',
        \ s:StrExtract(fileStatusStr, '\ChaveRev [0-9]\+', 8))
  let headAction = s:StrExtract(fileStatusStr, '\CheadAction [^[:space:]]\+',
        \ 11)
  if headAction ==# 'delete'
    call setbufvar(bufNr, 'p4Action', '<Deleted>')
    call setbufvar(bufNr, 'p4Change', '')
  else
    call setbufvar(bufNr, 'p4Action',
          \ s:StrExtract(fileStatusStr, '\Caction [^[:space:]]\+', 7))
    call setbufvar(bufNr, 'p4OtherOpen',
          \ s:StrExtract(fileStatusStr, '\CotherOpen0 [^[:space:]@]\+', 11))
    call setbufvar(bufNr, 'p4OtherAction',
          \ s:StrExtract(fileStatusStr, '\CotherAction0 [^[:space:]@]\+', 13))
    call setbufvar(bufNr, 'p4Change',
          \ s:StrExtract(fileStatusStr, '\Cchange [^[:space:]]\+', 7))
  endif

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
  if revNum =~# '[-+]\d\+'
    let revNum = substitute(revNum, '^+', '', '')
    if getbufvar(a:file, 'p4HeadRev') =~# s:EMPTY_STR
      " If fstat is not done yet, do it now.
      call s:GetFileStatus(a:file, 1)
      if getbufvar(a:file, 'p4HeadRev') =~# s:EMPTY_STR
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
            \ "after running PFRefreshFileStatus command.", 'Error')
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
  if ! s:promptToCheckout || ! s:IsFileUnderDepot(expand('%:p'))
    return
  endif
  " If we know that the file is deleted from the depot, don't prompt.
  if exists('b:p4Action') && b:p4Action == '<Deleted>'
    return
  endif

  if filereadable(expand("%")) && ! filewritable(expand("%"))
    let option = s:ConfirmMessage("Readonly file, do you want to checkout " .
          \ "from perforce?", "&Yes\n&No", s:checkOutDefault, "Question")
    if option == 1
      call s:PFIF(1, -1, 'edit')
      if ! s:errCode
        " You need to explicitly execute this autocommand to get the change
        "   detected and for other events (such as BufRead) to get fired. This
        "   was suggested by Bram.
        " The currentCommand by now must have got reset, so we need to
        "   explicitly set it and finally reset it.
        let currentCommand = s:currentCommand
        try
          let s:currentCommand = 'edit'
          if s:enableFileChangedShell
            call DefFCShellInstall()
          endif
          let curOnLastCol = (col('.') == col('$'))
          doautocmd FileChangedShell
          if curOnLastCol
            " Workaround from Benji to positiont the cursor correctly if the
            "   checkout was initiated with "A" command.
            stopinsert | startinsert!
          endif
        finally
          if s:enableFileChangedShell
            call DefFCShellUninstall()
          endif
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
" clearBuffer: If the buffer contents should be cleared before
"     adding the new output (See s:GotoWindow).
" testMode (number):
"   0 - Run normally.
"   1 - testing, ignore.
"   2 - debugging, display the command-line instead of the actual output..
" Returns the output if available. If there is any error, the error code will
"   be available in s:errCode variable.
function! s:PFImpl(clearBuffer, testMode, output) " {{{
  try " [-2f]

  let s:errCode = 0
  let fullCmd = ''
  let p4Options = ''
  if s:commandMode != s:CM_DISPLAY
    let p4Options = s:GetP4Options()
    let fullCmd = s:CreateFullCmd(s:MakeP4CmdString(p4Options))
  endif
  " Save the name of the current file.
  let p4OrgFileName = s:GetCurFileName()

  let s:currentCommand = ''
  " Make sure all the already existing changes are detected. We don't have
  "     s:currentCommand set here, so the user will get an appropriate prompt.
  checktime

  " If the output has to be shown in a window, position cursor appropriately,
  " creating a new window if required.
  let v:errmsg = ""
  " Ignore outputType in this case.
  if s:commandMode != s:CM_PIPE && s:commandMode != s:CM_FILTER
    if s:outputType == 0 || s:outputType == 1
      " Only when "clear with undo" is selected, we optimize out the call.
      call s:GotoWindow((!s:refreshWindowsAlways && (a:clearBuffer == 1)) ?
            \ 2 : a:clearBuffer, p4OrgFileName, 0)
    endif
  endif

  let output = ''
  if s:errCode == 0
    if ! a:testMode
      let s:currentCommand = s:p4Command
      if s:enableFileChangedShell
        call DefFCShellInstall()
      endif

      try
        if s:commandMode ==# s:CM_RUN
          " Only when "clear with undo" is selected, we optimize out the call.
          if s:refreshWindowsAlways ||
                \ ((!s:refreshWindowsAlways && (a:clearBuffer == 1)) &&
                \  (line('$') == 1 && getline(1) =~ '^\s*$'))
            " If we are placing the output in a new window, then we should
            "   avoid system() for performance reasons, imagine doing a
            "   'print' on a huge file.
            " These two outputType's correspond to placing the output in a
            "   window.
            if s:outputType != 0 && s:outputType != 1
              let output = s:System(fullCmd)
            else
              exec '.call s:Filter(fullCmd, 1)'
              let output = ''
            endif
          endif
        elseif s:commandMode ==# s:CM_FILTER
          exec s:filterRange . 'call s:Filter(fullCmd, 1)'
        elseif s:commandMode ==# s:CM_PIPE
          exec s:filterRange . 'call s:Filter(fullCmd, 2)'
        elseif s:commandMode ==# s:CM_DISPLAY
          let output = a:output
        endif
        " Detect any new changes to the loaded buffers.
        " CAUTION: This actually results in a reentrant call back to this
        "   function, but our Push/Pop mechanism for the context should take
        "   care of it.
        checktime
      finally
        if s:enableFileChangedShell
          call DefFCShellUninstall()
        endif
        let s:currentCommand = ''
      endtry
    elseif a:testMode != 1
      let output = fullCmd
    endif

    let v:errmsg = ""
    " If we have non-null output, then handling it is still pending.
    if output !~# s:EMPTY_STR
      " If the output has to be shown in a dialog, bring up a dialog with the
      "   output, otherwise show it in the current window.
      if s:outputType == 0 || s:outputType == 1
        silent! put! =output
      elseif s:outputType == 2
        call s:ConfirmMessage(output, "OK", 1, "Info")
      elseif s:outputType == 3
        echo output
      elseif s:outputType == 4
        " Do nothing we will just return it.
      endif
    endif
  endif
  return output

  finally " [+2s]
    call s:InitWindow(fullCmd, p4Options)
  endtry
endfunction " }}}

function! s:NewWindowCreated()
  if (s:outputType == 0 || s:outputType == 1) && s:errCode == 0 &&
        \ (s:commandMode ==# s:CM_RUN || s:commandMode ==# s:CM_DISPLAY)
    return 1
  else
    return 0
  endif
endfunction

function! s:setBufSetting(opt, set)
  let optArg = matchstr(b:p4Options, '\%(\S\)\@<!-'.a:opt.'\s\+\S\+')
  if optArg !~# s:EMPTY_STR
    let b:p4Options = substitute(b:p4Options, '\V'.optArg, '', '')
    let b:{a:set} = matchstr(optArg, '-'.a:opt.'\s\+\zs.*')
  endif
endfunction

function! s:InitWindow(fullCmd, p4Options)
  if s:NewWindowCreated()
    let b:p4Command = s:p4Command
    let b:p4Options = a:p4Options
    " Separate -p port -c client -u user options and set them individually.
    " Leave the rest in the b:p4Options variable.
    call s:setBufSetting('c', 'p4Client')
    call s:setBufSetting('p', 'p4Port')
    call s:setBufSetting('u', 'p4User')
    let b:p4FullCmd = a:fullCmd
    " Remove any ^M's at the end (for windows), without corrupting the search
    " register or its history.
    call SilentSubstitute("\<CR>$", '%s///e')
    setlocal nomodifiable
    setlocal nomodified
 
    if s:outputType == 1
      wincmd p
    endif
  endif
endfunction

" External command execution {{{

function! s:System(fullCmd)
  return s:ExecCmd(a:fullCmd, 0)
endfunction

function! s:Filter(fullCmd, mode) range
  " For command-line, we need to protect '%', '#' and '!' chars, even if they
  "   are in quotes, to avoid getting expanded by Vim before invoking external
  "   cmd.
  let fullCmd = Escape(a:fullCmd, '%#!')
  exec a:firstline.",".a:lastline.
        \ "call s:ExecCmd(fullCmd, a:mode)"
endfunction

function! s:ExecCmd(fullCmd, mode) range
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

    call s:CheckShellError(output, s:outputType)
    return output
  catch /^Vim\%((\a\+)\)\=:E/ " 48[2-5]
    let v:errmsg = substitute(v:exception, '^[^:]\+:', '', '')
    call s:CheckShellError(output, s:outputType)
  catch /^Vim:Interrupt$/
    let s:errCode = 1
    let v:errmsg = 'Interrupted'
  catch " Ignore.
  endtry
endfunction

function! s:EvalExpr(expr, def)
  let result = a:def
  if a:expr !~# s:EMPTY_STR
    exec "let result = " . a:expr
  endif
  return result
endfunction

function! s:GetP4Options()
  let addOptions = ''

  " If there are duplicates, perfore takes the first option, so let
  "   s:p4Options or b:p4Options come before s:defaultOptions.
  " LIMITATATION: We choose either s:p4Options or b:p4Options only. But this
  "   shouldn't be a big issue as this feature is meant for executing more
  "   commands on the p4 result windows only.
  if s:p4Options !~# s:EMPTY_STR
    let addOptions = addOptions . s:p4Options . ' '
  elseif exists('b:p4Options') && b:p4Options !~# s:EMPTY_STR
    let addOptions = addOptions . b:p4Options . ' '
  endif

  let addOptions = addOptions . s:defaultOptions . ' '

  let p4Client = s:p4Client
  let p4User = s:p4User
  let p4Port = s:p4Port
  try
    if s:p4Port !=# 'P4CONFIG'
      if s:curPresetExpr !~# s:EMPTY_STR
        let preset = s:EvalExpr(s:curPresetExpr, '')
        if preset ~= s:EMPTY_STR
          call s:PFSwitch(0, preset)
        endif
      endif

      if s:_('p4Client') !~# s:EMPTY_STR &&
            \ !MvContainsElement(addOptions, s:SPACE_AS_SEP, '-c', ' ')
        let addOptions = addOptions . '-c ' . s:_('p4Client') . ' '
      endif
      if s:_('p4User') !~# s:EMPTY_STR &&
            \ !MvContainsElement(addOptions, s:SPACE_AS_SEP, '-u', ' ')
        let addOptions = addOptions . '-u ' . s:_('p4User') . ' '
      endif
      if s:_('p4Port') !~# s:EMPTY_STR &&
            \ !MvContainsElement(addOptions, s:SPACE_AS_SEP, '-p', ' ')
        let addOptions = addOptions . '-p ' . s:_('p4Port') . ' '
      endif
      " Don't pass password with '-P' option, it will be too open (ps will show
      "   it up).
      let $P4PASSWD = s:p4Password
    else
    endif
  finally
    let s:p4Client = p4Client
    let s:p4User = p4User
    let s:p4Port = p4Port
  endtry
  
  return addOptions
endfunction

function! s:CreateFullCmd(cmd)
  let fullCmd = EscapeCommand(s:p4CommandPrefix . s:p4CmdPath, a:cmd, s:p4Pipe)
  let g:p4FullCmd = fullCmd
  return fullCmd
endfunction

" Generates a command string as the user typed, using the script variables.
function! s:MakeP4CmdString(p4Options)
  let opts = ''
  let cmdStr = opts . a:p4Options . ' ' . s:p4Command . ' ' . s:p4CmdOptions
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
    " When commandMode ==# s:CM_RUN, the error message may already be there in
    "   the current window.
    if a:output !~# s:EMPTY_STR
      let output = output . "\n" . a:output
    elseif a:output =~# s:EMPTY_STR &&
          \ (s:commandMode ==# s:CM_RUN && line('$') == 1 && col('$') == 1)
      let output = output . "\n\n" .
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
  let contextString = s:GetP4ContextVars()
  let s:p4Contexts = MvAddElement(s:p4Contexts, s:p4ContextSeparator,
        \ contextString)
endfunction

function! s:PeekP4Context()
  return s:PopP4ContextImpl(1, 1)
endfunction

function! s:PopP4Context(...)
  " By default carry forward error.
  return s:PopP4ContextImpl(0, (a:0 ? a:1 : 1))
endfunction

function! s:NumP4Contexts()
  return MvNumberOfElements(s:p4Contexts, s:p4ContextSeparator)
endfunction

function! s:PopP4ContextImpl(peek, carryFwdErr)
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

  call s:SetP4ContextVars(contextString, a:carryFwdErr)
  return contextString
endfunction

" Serialize p4 context variables.
function! s:GetP4ContextVars()
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
  let contextString = MvAddElement(contextString, s:p4ContextItemSeparator,
        \ s:outputType)
  let contextString = MvAddElement(contextString, s:p4ContextItemSeparator,
        \ s:errCode)
  return contextString
endfunction

" De-serialize p4 context variables.
function! s:SetP4ContextVars(contextString, ...)
  let carryFwdErr = 0
  if a:0 && a:1
    let carryFwdErr = s:errCode
  endif

  let contextString = a:contextString
  call MvIterCreate(contextString, s:p4ContextItemSeparator, "SetP4ContextVars")
  let s:p4Options = MvIterNext("SetP4ContextVars")
  let s:p4Command = MvIterNext("SetP4ContextVars")
  let s:p4CmdOptions = MvIterNext("SetP4ContextVars")
  let s:p4Arguments = MvIterNext("SetP4ContextVars")
  let s:p4Pipe = MvIterNext("SetP4ContextVars")
  let s:p4WinName = MvIterNext("SetP4ContextVars")
  let s:commandMode = MvIterNext("SetP4ContextVars")
  let s:filterRange = MvIterNext("SetP4ContextVars")
  let s:outputType = MvIterNext("SetP4ContextVars")
  let s:errCode = MvIterNext("SetP4ContextVars") + carryFwdErr
  call MvIterDestroy("SetP4ContextVars")
endfunction
" Push/Pop/Peek context }}}

""" BEGIN: Argument parsing {{{
function! s:ResetP4ContextVars()
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
  "            commandPrefix to restrict the filter range.
  "   display - Don't execute p4. The output is already passed in.
  let s:commandMode = "run"
  let s:filterRange = ""
  let s:outputType = 0
  let s:errCode = 0
endfunction
call s:ResetP4ContextVars() " Let them get initialized the first time.

" Parses the arguments into 4 parts, "options to p4", "p4 command",
" "options to p4 command", "actual arguments". Also generates the window name.
" outputType (string):
"   0 - Execute p4 and place the output in a new window.
"   1 - Same as above, but use preview window.
"   2 - Execute p4 and show the output in a dialog for confirmation.
"   3 - Execute p4 and echo the output.
"   4 - Execute p4 and return the output.
"   5 - Execute p4 no output expected. Essentially same as 4 when the current
"       commandMode doesn't produce any output, just for clarification.
function! s:ParseOptions(fline, lline, outputType, ...) " range
  call s:ResetP4ContextVars()
  let s:outputType = a:outputType
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

    if s:pendingPipeArg !~# s:EMPTY_STR
      let curArg = s:pendingPipeArg
      let s:pendingPipeArg = ''
    elseif s:p4Pipe =~# s:EMPTY_STR
      let curArg = a:{i}
      " The user can't specify a null string on the command-line, this is an
      "   argument originating from the script, so just ignore it (just for
      "   the sake of convenience, see PChangesDiff for a possibility).
      if curArg == ''
        continue
      endif
      let pipeIndex = match(curArg, '\\\@<!\%(\\\\\)*\zs|')
      if pipeIndex != -1
        let pipePart = strpart(curArg, pipeIndex)
        let p4Part = strpart(curArg, 0, pipeIndex)
        if p4Part !~# s:EMPTY_STR
          let curArg = p4Part
          let s:pendingPipeArg = pipePart
        else
          let curArg = pipePart
        endif
      endif
    else
      let curArg = a:{i}
    endif

    if curArg ==# '<pfitem>'
      let curItem = s:GetCurrentItem()
      if curItem !~# s:EMPTY_STR
        let curArg = curItem
      endif
    endif

    " As we use custom completion mode, the filename meta-sequences in the
    "   arguments will not be expanded by Vim automatically, so we need to
    "   expand them manually here. On the other hand, this provides us control
    "   on what to expand, so we can avoid expanding perforce file revision
    "   numbers as buffernames (escaping is no longer required by the user on
    "   the commandline).
    let fileRev = ''
    let fileRevIndex = match(curArg, '#\(-\?\d\+\|none\|head\|have\)$')
    if fileRevIndex != -1
      let fileRev = strpart(curArg, fileRevIndex)
      let curArg = strpart(curArg, 0, fileRevIndex)
    endif
    if curArg != ''
      let curArg = UserFileExpand(curArg)
    endif
    if fileRev != ''
      let curArg = curArg.fileRev
    endif
    " Escape the spaces in the arguments such that only the spaces between
    "   them are left unprotected.
    let curArg = Escape(curArg, ' ')

    if curArg =~# '^|' || s:p4Pipe !~# s:EMPTY_STR
      let s:p4Pipe = s:p4Pipe . ' ' . curArg
      continue
    endif

    if ! s:IsAnOption(curArg) " If not an option.
      if s:p4Command =~# s:EMPTY_STR &&
            \ MvContainsElement(s:allCommands, ',', curArg)
        " If the previous one was an option to p4 that takes in an argument.
        if prevArg =~# '^-[cCdHLpPux]$' || prevArg =~# '^++o$' " See :PH usage.
          let s:p4Options = s:p4Options . ' ' . curArg
          if prevArg ==# '++o' && (curArg == '0' || curArg == 1)
            let s:outputType = curArg
          endif
        else
          let s:p4Command = curArg
        endif
      else " Argument is not a perforce command.
        if s:p4Command =~# s:EMPTY_STR
          let s:p4Options = s:p4Options . ' ' . curArg
        else
          let optArg = 0
          " Look for options that have an argument, so we can collect this
          " into p4CmdOptions instead of p4Arguments.
          if s:p4Arguments =~# s:EMPTY_STR && s:IsAnOption(prevArg)
            " We could as well just check for the option here, but combining
            " this with the command name will increase the accuracy of finding
            " the starting point for p4Arguments.
            if (prevArg[0] ==# '-' && exists('s:p4OptCmdMap{prevArg[1]}') &&
                  \ MvContainsElement(s:p4OptCmdMap{prevArg[1]}, ',',
                    \ s:p4Command)) ||
             \ (prevArg =~# '^++' && exists('s:biOptCmdMap{prevArg[2]}') &&
                  \ MvContainsElement(s:biOptCmdMap{prevArg[2]}, ',',
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
      if s:p4Arguments =~# s:EMPTY_STR
        if s:p4Command =~# s:EMPTY_STR
          if curArg =~# '^++[pfdr]$'
            if curArg ==# '++p'
              let s:commandMode = s:CM_PIPE
            elseif curArg ==# '++f'
              let s:commandMode = s:CM_FILTER
            elseif curArg ==# '++d'
              let s:commandMode = s:CM_DISPLAY
            elseif curArg ==# '++r'
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
   " The "-x -" option requires it to act like a filter.
    if s:p4Command =~# s:EMPTY_STR && prevArg ==# '-x' && curArg ==# '-'
      let s:commandMode = s:CM_FILTER
    endif

    finally " [+2s]
      if s:pendingPipeArg =~# s:EMPTY_STR
        let i = i + 1
      endif
      let prevArg = curArg
    endtry
  endwhile

  if !MvContainsElement(s:p4Options, s:SPACE_AS_SEP, '-d', ' ')
    let curDir = s:EvalExpr(s:curDirExpr, '')
    if curDir !=# ''
      let s:p4Options = s:p4Options . ' -d ' . s:EscapeFileName(curDir)
    endif
  endif

  let s:p4Options = s:CleanSpaces(s:p4Options)
  let s:p4Command = s:CleanSpaces(s:p4Command)
  let s:p4CmdOptions = s:CleanSpaces(s:p4CmdOptions)
  let s:p4Arguments = s:CleanSpaces(s:p4Arguments)
  let s:p4WinName = s:MakeWindowName()
endfunction

function! s:IsAnOption(arg)
  if a:arg =~# '^-.$' || a:arg =~# '^-d\%([cnsubw]\|\d\+\)*$' ||
        \ a:arg =~# '^-a[fmsty]$' || a:arg =~# '^-s[ader]$' ||
        \ a:arg =~# '^-qu$' || a:arg =~# '^+'
    return 1
  else
    return 0
  endif
endfunction

function! s:CleanSpaces(str)
  " Though not complete, it is enough to just say,
  "   "spaces that are not preceded by \'s".
  return substitute(substitute(a:str, '^ \+\|\%(\\\@<! \)\+$', '', 'g'),
        \ '\%(\\\@<! \)\+', ' ', 'g')
endfunction

function! s:_(set)
  if exists('b:{a:set}')
    return b:{a:set}
  elseif exists('w:{a:set}')
    return w:{a:set}
  elseif exists('s:{a:set}')
    return s:{a:set}
  else
    echoerr 'Setting not found: ' a:set
  endif
endfunction
""" END: Argument parsing }}}

""" BEGIN: Messages and dialogs {{{
function! s:SyntaxError(msg)
  let s:errCode = 1
  call s:ConfirmMessage("Syntax Error:\n".a:msg, "OK", 1, "Error")
  return s:errCode
endfunction

function! s:ShowVimError(errmsg, stack)
  call s:ConfirmMessage("There was an error executing a Vim command.\n\t" .
        \ a:errmsg.(a:stack != '' ? "\nCurrent stack: ".a:stack : ''), "OK", 1,
        \ "Error")
  echohl ErrorMsg | echomsg a:errmsg | echohl None
  if a:stack != ''
    echomsg "Current stack:" a:stack
  endif
  redraw " Cls, such that it is only available in the message list.
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
  if a:type ==# 'Error'
    let s:lastMsgGrp = 'Error'
  endif
  return confirm(a:msg, a:opts, a:def, a:type)
endfunction

function! s:PromptFor(loop, useDialogs, msg, default)
  let result = ""
  while result =~# s:EMPTY_STR
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
  " If there is a -d option existing, then it is better to use the full path
  "   name.
  if MvContainsElement(s:p4Options, s:SPACE_AS_SEP, '-d', ' ')
    let fName = fnamemodify(a:fName, ':p')
  else
    let fName = a:fName
  endif
  return Escape(fName, ' &|')
endfunction

function! s:GetCurFileName()
  " When the current window itself is a perforce window, then carry over the
  " existing value.
  return (exists('b:p4OrgFileName') &&
        \              b:p4OrgFileName !~# s:EMPTY_STR) ?
        \             b:p4OrgFileName : expand('%:p')
endfunction

function! s:GuessFileTypeForCurrentWindow()
  let fileExt = s:GuessFileType(b:p4OrgFileName)
  if fileExt =~# s:EMPTY_STR
    let fileExt = s:GuessFileType(expand("%"))
  endif
  return fileExt
endfunction

function! s:GuessFileType(name)
  let fileExt = fnamemodify(a:name, ":e")
  return matchstr(fileExt, '\w\+')
endfunction

function! s:IsDepotPath(path)
  if match(a:path, '^//' . s:p4Depot . '/') == 0
        " \ || match(a:path, '^//'. s:_('p4Client') . '/') == 0
    return 1
  else
    return 0
  endif
endfunction

function! s:PathRefersToDepot(path)
  if s:IsDepotPath(a:path) || s:GetRevisionSpecifier(a:path) !~# s:EMPTY_STR
    return 1
  else
    return 0
  endif
endfunction

function! s:GetRevisionSpecifier(fileName)
  return matchstr(a:fileName,
        \ '^\(\%(\S\|\\\@<!\%(\\\\\)*\\ \)\+\)[\\]*\zs[#@].*$')
endfunction

" Removes the //<depot> or //<client> prefix from fileName.
function! s:StripRemotePath(fileName)
  "return substitute(a:fileName, '//\%('.s:p4Depot.'\|'.s:_('p4Client').'\)', '', '')
  return substitute(a:fileName, '//\%('.s:p4Depot.'\)', '', '')
endfunction

" Client view translation {{{
" Convert perforce file wildcards ("*", "..." and "%[1-9]") to a Vim string
"   regex (see |pattern.txt|). Returns patterns that work when "very nomagic"
"   is set.
function! s:TranlsateP4Wild(p4Wild, rhsView)
  let strRegex = ''
  if a:rhsView
    if a:p4Wild[0] ==# '%'
      let pos = s:p4WildMap{a:p4Wild[1]}
    else
      let pos = s:p4WildCount
    endif
    let strRegex = '\'.pos
  else
    if a:p4Wild ==# '*'
      let strRegex = '\(\[^/]\*\)'
    elseif a:p4Wild ==# '...'
      let strRegex = '\(\.\*\)'
    elseif a:p4Wild[0] ==# '%'
      let strRegex = '\(\[^/]\*\)'
      let s:p4WildMap{a:p4Wild[1]} = s:p4WildCount
    endif
  endif
  let s:p4WildCount = s:p4WildCount + 1
  return strRegex
endfunction

" Convert perforce file regex (containing "*", "..." and "%[1-9]") to a Vim
"   string regex. No error checks for now, for simplicity.
function! s:TranslateP4FileRegex(p4Regex, rhsView)
  let s:p4WildCount = 1
  " Note: We don't expect backslashes in the views, so no special handling.
  return substitute(a:p4Regex,
        \ '\(\*\|\%(\.\)\@<!\.\.\.\%(\.\)\@!\|%\([1-9]\)\)',
        \ '\=s:TranlsateP4Wild(submatch(1), a:rhsView)', 'g')
endfunction

function! s:CondUpdateViewMappings()
  if s:useClientViewMap &&
        \ (!exists('s:toDepotMapping{s:_("p4Client")}') ||
        \  (s:toDepotMapping{s:_('p4Client')} =~# s:EMPTY_STR))
    call s:UpdateViewMappings()
  endif
endfunction

function! s:UpdateViewMappings()
  if s:_('p4Client') =~# s:EMPTY_STR
    return
  endif
  let view = ''
  call s:PushP4Context()
  try
    let view = substitute(s:PFIF(1, 4, '-c', s:_('p4Client'), 'client'),
          \ "\\_.*\nView:\\ze\n", '', 'g')
    if s:errCode != 0
      return
    endif
  finally
    call s:PopP4Context(0)
  endtry
  let s:fromDepotMapping{s:_('p4Client')} = ''
  let s:toDepotMapping{s:_('p4Client')} = ''
  call MvIterCreate(view, "\n", 'P4View')
  while MvIterHasNext('P4View')
    let nextMap = MvIterNext('P4View')
    " We need to inverse the order of mapping such that the mappings that come
    "   later in the view take more priority.
    " Also, don't care about exclusionary mappings for simplicity (this could
    "   be considered a feature too).
    exec substitute(nextMap,
          \ '\s*-\?\(//'.s:p4Depot.'/[^ ]\+\)\s*\(//'.s:_("p4Client").'/.\+\)',
          \ 'let s:fromDepotMapping{s:_("p4Client")} = s:TranslateP4FileRegex('.
          \ "'".'\1'."'".', 0)." ".s:TranslateP4FileRegex('."'".'\2'."'".
          \ ', 1)."\n".s:fromDepotMapping{s:_("p4Client")}', '')
    exec substitute(nextMap,
          \ '\s*-\?\(//'.s:p4Depot.'/[^ ]\+\)\s*\(//'.s:_("p4Client").'/.\+\)',
          \ 'let s:toDepotMapping{s:_("p4Client")} = s:TranslateP4FileRegex('.
          \ "'".'\2'."'".', 0)." ".s:TranslateP4FileRegex('."'".'\1'."'".
          \ ', 1)."\n".s:toDepotMapping{s:_("p4Client")}', '')
  endwhile
  call MvIterDestroy('P4View')
  " FIXME: '^\_s*$' should have worked.
  if s:fromDepotMapping{s:_('p4Client')} =~# '^\%(\s\|\n\)*$' ||
        \ s:fromDepotMapping{s:_('p4Client')} =~# '^\%(\s\|\n\)*$'
    let s:fromDepotMapping{s:_('p4Client')} = ''
    let s:toDepotMapping{s:_('p4Client')} = ''
  endif
endfunction

function! s:ConvertToLocalPath(path)
  let fileName = substitute(a:path, '#[^#]\+$', '', '')
  if s:IsDepotPath(fileName)
    if s:useClientViewMap
      call s:CondUpdateViewMappings()
      call MvIterCreate(s:fromDepotMapping{s:_('p4Client')}, "\n",
            \ 'ConvertToLocalPath')
      while MvIterHasNext('ConvertToLocalPath')
        let nextMap = MvIterNext('ConvertToLocalPath')
        exec substitute(nextMap, '\(//'.s:p4Depot.'/.*[^ ]\)\s*//'.
              \ s:_('p4Client').'/\(.*\)', "let lhs = '\\1'\nlet rhs = '".
              \ s:_('clientRoot')."/\\2'", '')
        if fileName =~# '\V'.lhs
          let fileName = substitute(fileName, '\V'.lhs, rhs, '')
          break
        endif
      endwhile
      call MvIterDestroy('ConvertToLocalPath')
    endif
    if s:IsDepotPath(fileName)
      let fileName = s:_('clientRoot') . s:StripRemotePath(fileName)
    endif
  endif
  return fileName
endfunction

function! s:ConvertToDepotPath(path)
  " If already a depot path, just return it without any changes.
  if s:IsDepotPath(a:path)
    let fileName = a:path
  else
    let fileName = CleanupFileName(a:path)
    if s:IsFileUnderDepot(fileName)
      if s:useClientViewMap
        call s:CondUpdateViewMappings()
        call MvIterCreate(s:toDepotMapping{s:_('p4Client')}, "\n",
              \ 'ConvertToDepotPath')
        while MvIterHasNext('ConvertToDepotPath')
          let nextMap = MvIterNext('ConvertToDepotPath')
          exec substitute(nextMap,
                \ '//'.s:_('p4Client').'/\(.*[^ ]\)\s*\(//'.s:p4Depot.'/.*\)',
                \ "let rhs = '\\2'\nlet lhs = '".s:_('clientRoot')."/\\1'", '')
          if fileName =~# '\V'.lhs
            let fileName = substitute(fileName, '\V'.lhs, rhs, '')
            break
          endif
        endwhile
        call MvIterDestroy('ConvertToDepotPath')
      endif
      if ! s:IsDepotPath(fileName)
        let fileName = substitute(fileName, '^'.s:_('clientRoot'),
              \ '//'.s:p4Depot, '')
      endif
    endif
  endif
  return fileName
endfunction
" Client view translation }}}

" Requires at least 2 arguments.
" Returns a list of alternative filenames.
function! s:PFGetAltFiles(codeline, ...)
  if a:0 == 0
    return ""
  endif

  let altCodeLine = a:codeline

  let i = 1
  let altFiles = ""
  while i <= a:0
    let fileName = a:{i}
    let fileName=CleanupFileName(fileName)
    if ! s:IsDepotPath(fileName)
      let fileName = s:ConvertToDepotPath(fileName)
    endif

    if altCodeLine ==# s:p4Depot
      " We do nothing, it is already converted to depot path.
      let altFile = fileName
    else
      " FIXME: Assumes that the current branch name has single path component.
      let altFile = substitute(fileName, '//'.s:p4Depot.'/[^/]\+',
            \ '//'.s:p4Depot.'/' . altCodeLine, "")
      let altFile = s:ConvertToLocalPath(altFile)
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
  if fileName =~? '^\V'.s:_('clientRoot')
    return 1
  else
    return 0
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
  if match(line, '//' . s:p4Depot . '/.*\(#\d\+\)\?') != -1
        " \ || match(line, '^//'. s:_('p4Client') . '/.*\(#\d\+\)\?') != -1
    let fileName = matchstr(line, '//[^/]\+/[^#]*\(#\d\+\)\?')
  elseif match(line, '\.\.\. #\d\+ .*') != -1
    " Branches, integrations etc.
    let fileVer = matchstr(line, '\d\+')
    call SaveHardPosition('Perforce')
    exec a:lineNo
    if search('^//' . s:p4Depot . '/', 'bW') == 0
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
function! s:StartBufSetup()
  " If the command created a new window, then only do setup.
  if !s:errCode
    if s:NewWindowCreated()
      if s:outputType == 1
        wincmd p
      endif

      return 1
    endif
  endif
  return 0
endfunction

function! s:EndBufSetup()
  if s:NewWindowCreated()
    if s:outputType == 1
      wincmd p
    endif
  endif
endfunction

" Goto/Open window for the current command.
" clearBuffer (number):
"   0 - clear with undo.
"   1 - clear with no undo.
"   2 - don't clear
function! s:GotoWindow(clearBuffer, p4OrgFileName, cmdCompleted)
  let bufNr = FindBufferForName(s:p4WinName)
  " FIXME: Precautionary measure to avoid accidentally matching an existing
  "   buffer and thus overwriting the contents.
  if bufNr != -1 && getbufvar(bufNr, '&buftype') == ''
    return s:BufConflictError(a:cmdCompleted)
  endif

  " If there is a window for this buffer already, then we will just move
  "   cursor into it.
  let curBufnr = bufnr('%')
  let maxBufNr = bufnr('$')
  let bufWinnr = bufwinnr(bufNr)
  let nWindows = NumberOfWindows()
  let _eventignore = &eventignore
  try
    "set eventignore=BufRead,BufReadPre,BufEnter,BufNewFile
    set eventignore=all
    if s:outputType == 1 " Preview
      let alreadyOpen = 0
      try
        wincmd P
        " No exception, meaning preview window is already open.
        if winnr() == bufWinnr
          " The buffer is already visible in the preview window. We don't have
          " to do anything in this case.
          let alreadyOpen = 1
        endif
      catch /^Vim\%((\a\+)\)\=:E441/
        " Ignore.
      endtry
      if !alreadyOpen
        call s:EditP4WinName(1, nWindows)
        wincmd P
      endif
    elseif bufWinnr != -1
      call MoveCursorToWindow(bufWinnr)
    else
      exec s:splitCommand
      call s:EditP4WinName(0, nWindows)
    endif
    if s:errCode == 0
      " FIXME: If the name didn't originally match with a buffer, we expect
      "   the s:EditP4WinName() to create a new buffer, but there is a bug in
      "   Vim, that treats "..." in filenames as ".." resulting in multiple
      "   names matching the same buffer ( "p4 diff ../.../*.java" and
      "   "p4 submit ../.../*.java" e.g.). Though I worked around this
      "   particular bug by avoiding "..." in filenames, this is a good check
      "   in any case.
      if bufNr == -1 && bufnr('%') <= maxBufNr
        return s:BufConflictError(a:cmdCompleted)
      endif
      " For navigation.
      normal! mt
    endif
  catch
    call s:ShowVimError("Exception while opening new window.\n" . v:exception,
          \ v:throwpoint)
  finally
    let &eventignore = _eventignore
  endtry
  " We now have a new window created, but may be with errors.
  if s:errCode == 0
    setlocal noreadonly
    setlocal modifiable
    if s:commandMode ==# s:CM_RUN
      if a:clearBuffer == 1
        call OptClearBuffer()
      elseif a:clearBuffer == 0
        silent! 0,$delete _
      endif
    endif

    let b:p4OrgFileName = a:p4OrgFileName
    call s:PFSetupBuf(expand('%'))
  else
    " Window is created but with an error. We might actually miss the cases
    "   where a preview operation when the preview window is already open
    "   fails, and so no additional windows are created, but detecting such
    "   cases could be error prone, so it is better to leave the buffer in
    "   this case, rather than making a mistake.
    if NumberOfWindows() > nWindows
      if winbufnr(winnr()) == curBufnr " Error creating buffer itself.
        quit
      elseif bufname('%') == s:p4WinName
        " This should even close the window.
        silent! exec "bwipeout " . bufnr('%')
      endif
    endif
  endif
  return 0
endfunction

function! s:BufConflictError(cmdCompleted)
  return s:ShowVimError('This perforce command resulted in matching an '.
        \ 'existing buffer. To prevent any demage this could cause '.
        \ 'the command will be aborted at this point.'.
        \ (a:cmdCompleted ? ("\nHowever the command completed ".
        \ (s:errCode ? 'un' : ''). 'successfully.') : ''), '')
endfunction

function! s:EditP4WinName(preview, nWindows)
  let fatal = 0
  let bug = 0
  let exception = ''
  let pWindowWasOpen = (GetPreviewWinnr() != -1)
  " Some patterns can cause problems.
  let _wildignore = &wildignore
  try
    set wildignore=
    exec (a:preview?'p':'').'edit' s:p4WinName
  catch /^Vim\%((\a\+)\)\=:E303/
    " This is a non-fatal error.
    let bug = 1 | let exception = v:exception
    let stack = v:throwpoint
  catch /^Vim\%((\a\+)\)\=:\%(E77\|E480\)/
    let bug = 1 | let exception = v:exception | let fatal = 1
    let stack = v:throwpoint
  catch
    let exception = v:exception | let fatal = 1
    let stack = v:throwpoint
  finally
    let &wildignore = _wildignore
  endtry
  if fatal
    call s:ShowVimError(exception, '')
  endif
  if bug
    echohl ERROR
    echomsg "Please report this error message:"
    echomsg "\t".exception
    echomsg
    echomsg "with the following information:"
    echomsg "\ts:p4WinName:" s:p4WinName
    echomsg "\tCurrent stack:" stack
    echohl NONE
  endif
  " For non preview operation, or for preview window operation when the preview
  "   window is not already visible, we expect the number of windows to go up.
  if !a:preview || (a:preview && !pWindowWasOpen)
    if a:nWindows >= NumberOfWindows()
      let s:errCode = 1
    endif
  endif
endfunction

function! s:MakeWindowName()
  " Let only the options that are explicitly specified appear in the window
  "   name.
  let cmdStr = 'p4 '.s:MakeP4CmdString(s:p4Options)
  let winName = cmdStr
  "let winName = DeEscape(winName)
  " HACK: Work-around for some weird handling of buffer names that have "..."
  "   (the perforce wildcard) at the end of the filename or in the middle
  "   followed by a space. The autocommand is not getting triggered to clean
  "   the buffer. If we append another character to this, I observed that the
  "   autocommand gets triggered. Using "/" instead of "'" would probably be
  "   more appropriate, but this is causing unexpected FileChangedShell
  "   autocommands on certain filenames (try "PF submit ../..." e.g.). There
  "   is also another issue with "..." (anywhere) getting treated as ".."
  "   resulting in two names matching the same buffer(
  "     "p4 diff ../.../*.java" and "p4 submit ../.../*.java" e.g.). This
  "   could also change the name of the buffer during the :cd operations
  "   (though applies only to spec buffers).
  "let winName = substitute(winName, '\.\.\%( \|$\)\@=', '&/', 'g')
  "let winName = substitute(winName, '\.\.\%( \|$\)\@=', "&'", 'g')
  let winName = substitute(winName, '\.\.\.', '..,', 'g')
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
  if ! exists('+shellslash') " Assuming UNIX environment.
    let winName = substitute(winName, '\\\@<!\(\%(\\\\\)*\\[^ ]\)', '\\\1', 'g')
    let winName = escape(winName, "'~$`{\"")
  endif
  return winName
endfunction

function! s:PFSetupBuf(bufName)
  call SetupScratchBuffer()
  let &l:bufhidden=s:p4BufHidden
endfunction

function! s:PFSetupForSpec()
  setlocal modifiable
  setlocal buftype=
  call s:PFSetupBufAutoCommand(expand('%'), 'BufWriteCmd', ':W', 1)
  call s:PFSetupBufAutoCommand(expand('%'), 'BufWipeout',
      \ ':call <SID>PFUnSetupBufAutoCommand(bufname(expand("<abuf>") + 0), '.
      \ '"*")', 0)
endfunction

function! s:WipeoutP4Buffers(...)
  let testMode = 1
  if a:0 > 0 && a:1 ==# '++y'
    let testMode = 0
  endif
  let i = 1
  let lastBuf = bufnr('$')
  let cleanedBufs = ''
  while i <= lastBuf
    if bufexists(i) && expand('#'.i) =~# '\<p4 ' && bufwinnr(i) == -1
      if testMode
        let cleanedBufs = cleanedBufs . ', ' . expand('#'.i)
      else
        silent! exec 'bwipeout' i
        let cleanedBufs = cleanedBufs + 1
      endif
    endif
    let i = i + 1
  endwhile
  if testMode
    echo "Buffers that will be wipedout (Use ++y to perform action):" .
          \ cleanedBufs
  else
    echo "Total Perforce buffers wipedout (start with 'p4 '): " . cleanedBufs
  endif
endfunction

" Arrange an autocommand such that the buffer is automatically deleted when the
"  window is quit. Delete the autocommand itself when done.
function! s:PFSetupBufAutoCommand(bufName, auName, auCmd, nested)
  let bufName = GetBufNameForAu(a:bufName)
  " Just in case the autocommands are leaking, this will curtail the leak a
  "   little bit.
  silent! exec 'au! Perforce' a:auName bufName
  exec 'au Perforce' a:auName bufName.(a:nested?' nested ':' ').a:auCmd
endfunction

function! s:PFUnSetupBufAutoCommand(bufName, auName)
  let bufName = GetBufNameForAu(a:bufName)
  silent! exec "au! Perforce" a:auName bufName
endfunction

function! s:PFRefreshActivePane()
  if exists("b:p4FullCmd")
    call SaveSoftPosition('Perforce')

    let _modifiable = &l:modifiable
    try
      setlocal modifiable
      exec '1,$call s:Filter(b:p4FullCmd, 1)'
    catch
      call s:ShowVimError(v:exception, v:throwpoint)
    finally
      let &l:modifiable=_modifiable
    endtry

    call RestoreSoftPosition('Perforce')
    call ResetSoftPosition('Perforce')
  endif
endfunction
""" END: Buffer management, etc. }}}

""" BEGIN: Testing {{{
" Ex: PFTestCmdParse -c client -u user integrate -b branch -s source target1 target2
command! -nargs=* -range=% -complete=file PFTestCmdParse
      \ :call <SID>TestParseOptions(<f-args>)
function! s:TestParseOptions(commandName, ...) range
  exec MakeArgumentString()
  exec "call s:ParseOptionsIF(a:firstline, a:lastline," .
        \ " 0, 0,  a:commandName, " . argumentString . ")"
  call s:DebugP4Status()
endfunction

function! s:DebugP4Status()
  echo "p4Options :" . s:p4Options . ":"
  echo "p4Command :" . s:p4Command . ":"
  echo "p4CmdOptions :" . s:p4CmdOptions . ":"
  echo "p4Arguments :" . s:p4Arguments . ":"
  echo "p4Pipe :" . s:p4Pipe . ":"
  echo "p4WinName :" . s:p4WinName . ":"
  echo "outputType :" . s:outputType . ":"
  echo "errCode :" . s:errCode . ":"
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
"  call s:ResetP4ContextVars()
"  echo "After reset: " . s:CreateFullCmd(s:MakeP4CmdString(''))
"  call s:PopP4Context()
"  echo "After pop1: " . s:CreateFullCmd(s:MakeP4CmdString(''))
"  call s:PopP4Context()
"  echo "After pop2: " . s:CreateFullCmd(s:MakeP4CmdString(''))
"endfunction

""" END: Testing }}}

""" BEGIN: Experimental API {{{

function! PFGet(var)
  return {a:var}
endfunction

function! PFSet(var, val)
  let {a:var} = a:val
endfunction

function! PFCall(func, ...)
  exec MakeArgumentString()
  exec "let result = {a:func}(".argumentString.")"
  return result
endfunction

function! PFEval(expr)
  exec "let result = ".a:expr
  return result
endfunction

""" END: Experimental API }}}

""" END: Infrastructure }}}
 
" Do the actual initialization.
call s:Initialize()

" Restore cpo.
let &cpo = s:save_cpo
unlet s:save_cpo

" vim6:fdm=marker et sw=2
