" perforce.vim: Interface with p4 command.
" Author: Hari Krishna <hari_vim@yahoo.com>
" Last Modified: 26-Mar-2002 @ 19:36
" Created:       not sure, but sometime before 20-Apr-2001
" Requires: Vim-6.0 or higher, genutils.vim(1.0.19), multvals.vim(2.1.2)
" Version: 1.1.22
" Usage: 
"   - Adds commands and menus (if enabled) to execute perforce commands. There
"     are commands defined for most used perforce commands such as 'edit' (PE),
"     'opened' (PO) etc. The generic PF command lets you execute any arbitrary
"     perforce command, and opens a new window with the output of that
"     command. But don't execute any commands that require you to enter input
"     (such as 'submit'). There are separate commands defined for such
"     operations, such as PSubmit for 'submit' and PC for 'client'.
"   - Most commands take variable number of arguments. Some commands that
"     require a filename default to current file if you didn't pass any. If
"     you need to specify a version number, then protect the '#' symbol with
"     a backslash.
"   - When you are in a list view, such as "PF labels" or "PO", you can
"     press <Enter> to view the current item in a preview window and O to edit
"     it. You can also press D to delete the current item, when it is
"     applicable. You can also use the PItemDescribe, PItemOpen, or the
"     PItemDelete commands.
"   - In addition, if you are on a file list view, you can press P to fstat
"     the current file, D to show a diff with the depot and R to revert the
"     changes for that file. You can also use the PFileProps, PFileDiff and
"     PFileRevert commands respectively.
"   - Filelog window has a special feature to take diff between two versions.
"     To do this, select all the lines between the two version, inclusive, and
"     press D or use PFilelogDiff command.
"   - If you are on the opened or files window, then you can use O for open, R
"     for revert, P for properties (fstat) and D for diff.
"   - For convenience the sync/get and print commands take in a revision (as
"     specified by "help revisions") as the last argument and apply it to the
"     current file.
"	To see the revision 1 of the current file, type "PP \#1".
"	To see the current file as of a date, type "PP @2002/01/01".	
"   - In the perforce help window, you can use K, <CR> or mouse double click to
"     on any command name to get the help for that command. You can use Ctrl-O
"     or u and Ctrl-R and <Tab> to navigate the help history.
"   - Set the g:p4Client, g:p4User, g:p4Port and g:p4CodelineRoot variables in
"     your .vimrc, or some defaults will be chosen. 
"   - If you want to switch to a different perforce server, or just switch to a
"     different client, without leaving Vim or needing to change any environment
"     variables, then you can use the PSwitch command (or the Settings menu).
"     You can set the most used configurations as comma separated list of
"     "{port} {client} {user}" to the g:p4Presets variable and specify the
"     index (starting from 0) to this command.
"   - When you want to change any of the script options without restarting Vim,
"     you can use the PFInitialize to reinitialize the script from the
"     environmental variables.  You can e.g., disable menus by setting the
"     value of g:p4EnableMenu to 0 and run PFInitialize.
"   - You can also set g:p4DefaultOptions to options that are specified in the
"     "p4 help usage", so that these options are always passed to p4 command.
"   - To enable menus, set the g:p4EnableMenu and/or g:p4EnablePopupMenu as per
"     your taste. You can also set the g:p4UseExpandedMenu to enable more
"     complete menus, on the lines of p4Win. By default, a basic menu is
"     created. There are also g:p4EnablePopupMenu and g:p4UseExpandedPopupMenu
"     options to create the Perforce PopUp menu group.
"   - By default only 100 items are shown in the changes and jobs screens. You
"     can change this number by setting a balue to g:p4DefaultListSize. Set it
"     to a negative value to show all.
"   - If you are manually sourcing the scripts either from vimrc or from
"     commandline, make sure to source multvals.vim and genutils.vim first.
"
" Environment: 
"   Adds
"       PE (edit), PR (revert), PA (add), PD (diff), PD2 (diff2),
"       PP (print), PG (get), PSync (sync), PO (opened), PH (help),
"       PDelete (delete), PLock (lock), PSubmit (submit), PUnlock (unlock),
"       PClient (client), PClients (clients), PUser (user), PUsers (users),
"       PBranch (branch), PBranches (branches), PLabel (label),
"       PLabels (labels) PLabelsync (labelsync), PJob (job), PJobs (jobs),
"       PJobspec (jobspec), PResolve (resolve), PChange (change),
"       PChanges (changes), PDepot (depot), PDepots (depots), PHave (have),
"       PDescribe (describe), PFiles (files), PFstat (fstat), PGroup (group),
"       PGroups (groups)
"       PF & PFRaw (for generic command execution),
"       E (command to open a file from a different codeline),
"       PSwitch (command to switch between different port/client/user settings),
"       PRefreshActivePane (to refresh the current p4 window),
"       PItemDescribe (<CR>), PItemOpen (O) and PItemDelete (D) to operate on
"         the list views.
"       PLabelsSyncClient (S), PLabelsSyncLabel (C) in labels view.
"       PChangesSubmit (S), PChangesOpened (O) in the changes view.
"       PFilelogDiff (D), PFilelogSync (S), PFilelogDescribe (C) in the
"         filelog view.
"       You can also use PFileDiff (D), PFileProps (P), PFileRevert (R) in the
"         file listing views, opened, have and files.
"     commands. 
"   Adds 
"       O    - for open/edit current item (in the list view),
"       <2-LeftMouse> or
"       <CR> - for describe current item.
"       D    - for delete current item (in filelist view),
"              or diff (in filelog) current file.
"       S    - for sync to the current version (in filelog) .
"       o    - list opened files (in the current change list).
"       C    - for describe current change list (in filelog or changes).
"       P    - for print properties of the current file.
"       R    - for revert current file.
"       S    - to submit current change.
"     normal-mode mappings, only in the relevant p4 windows.
"   Adds 
"       Perforce
"     menu group in the main and Popup menus if enabled.
"   Depends on
"       g:p4CmdPath, g:p4CodelineRoot, g:p4Client, g:p4User, g:p4Port,
"       g:p4DefaultOptions, g:p4UseGUIDialogs, g:p4EnableMenu,
"       g:p4EnablePopupMenu, g:p4PromptToCheckout, g:p4UseExpandedMenu,
"       g:p4UseExpandedPopupMenu, g:p4DefaultListSize, g:p4DefaultDiffOptions
"     Environmental variables. 
"     
"
" TODO: {{{
"   Sort change lists and show those that are by the current client and others
"     separately. 
"   How can I support interactive resolves? Will it be worth doing it? 
"   Continuous operations on the preview winow is not clean. I do a pclose
"     before running the next preview command, so the previous buffer is lost
"     from the history. Since I delete buffers as soon as they are hidden,
"     there probably is no solution for this.
"   In filelist view, select the files to be operated upon. 
"   POpened should take in a branch name to show the opened files under the
"     branch (-b branchname). Also a way to open only of specified type such
"     as add, edit, delete (-t ?).
"   How can I avoid prompting for checkout when the current vim session is in
"     view mode (-R option) ???
"   Allow file names to be passed into PSubmit command. 
"   PDiff2 is not clean. 
"   The PSwitch can't change the p4CodelineRoot, it is best to read this from
"     'info' after reinitialization.
"   The script is not much intelligent wrt to obtaining the settings from p4.
"     E.g., it assumes that the local directory name is same as the branch
"     name.
"   Something to enable/disable and switch between basic and expanded menus
"     will be good.
"   The list specific menus should be disabled unless you are in that window. 
"   A command to add/remove preset, which will also add it to the menu. 
"   If there are spaces in the arguments, is it still going to work? 
"   Verify that the buffers/autocommands are not leaking.
"   Backup/Restore commands for opened files.
" END TODO }}}

if exists("loaded_perforce")
  finish
endif
let loaded_perforce=1


" We need these scripts at the time of initialization itself.
if !exists("loaded_genutils")
  runtime plugin/genutils.vim
endif
if !exists("loaded_multvals")
  runtime plugin/multvals.vim
endif


command! -nargs=0 PFInitialize :call <SID>Initialize()

function! s:Initialize() " {{{

if exists("g:p4CmdPath")
  let s:p4CmdPath = g:p4CmdPath
  unlet g:p4CmdPath
elseif !exists("s:p4CmdPath")
  let s:p4CmdPath = "p4"
endif

if exists("g:p4CodelineRoot")
  let s:codelineRoot=g:p4CodelineRoot
  unlet g:p4CodelineRoot
elseif !exists("s:codelineRoot")
  let s:codelineRoot=fnamemodify(".", ":p")
endif

if exists("g:p4DefaultListSize")
  let s:defaultListSize=g:p4DefaultListSize
  unlet g:p4DefaultListSize
elseif !exists("s:defaultListSize")
  let s:defaultListSize='100'
endif

if exists("g:p4DefaultDiffOptions")
  let s:defaultDiffOptions="'" . substitute(g:p4DefaultDiffOptions, ' ', "', '",
	\ 'g') . "'"
  unlet g:p4DefaultDiffOptions
elseif !exists("s:defaultDiffOptions")
  let s:defaultDiffOptions=''
endif

if exists("g:p4Client")
  let s:p4Client = g:p4Client
  unlet g:p4Client
elseif !exists("s:p4Client")
  let s:p4Client = $P4CLIENT
endif

if exists("g:p4User")
  let s:p4User = g:p4User
  unlet g:p4User
elseif !exists("s:p4User")
  if OnMS() && exists("$USERNAME")
    let s:p4User = $USERNAME
  elseif exists("$LOGNAME")
    let s:p4User = $LOGNAME
  endif
endif

if exists("g:p4Port")
  let s:p4Port = g:p4Port
  unlet g:p4Port
elseif !exists("s:p4Port")
  let s:p4Port = $P4PORT
endif

if exists("g:p4Presets")
  let s:p4Presets = g:p4Presets
  unlet g:p4Presets
elseif !exists("s:p4Presets")
  let s:p4Presets = ""
endif

if exists("g:p4DefaultOptions")
  let s:p4DefaultOptions = g:p4DefaultOptions
  unlet g:p4DefaultOptions
elseif !exists("s:p4DefaultOptions")
  let s:p4DefaultOptions = ""
endif

" Normally, we use consolve dialogs even in gvim, which has the advantage of
"   having an history and expression register. But if you rather prefer GUI
"   dialogs, then set this variable.
if exists("g:p4UseGUIDialogs")
  let s:useDialogs = g:p4UseGUIDialogs
  unlet g:p4UseGUIDialogs
elseif !exists("s:useDialogs")
  let s:useDialogs = 0
endif

if exists("g:p4PromptToCheckout")
  let s:promptToCheckout = g:p4PromptToCheckout
  unlet g:p4PromptToCheckout
elseif !exists("s:promptToCheckout")
  let s:promptToCheckout = 1
endif

if exists("g:p4MaxLinesInDialog")
  let s:maxLinesInDialog = g:p4MaxLinesInDialog
  unlet g:p4MaxLinesInDialog
elseif !exists("s:maxLinesInDialog")
  let s:maxLinesInDialog = 1
endif

" If the client, user and port are available, and if they are not specified in
" the p4DefaultOptions, then add them.
let s:defaultOptions = s:p4DefaultOptions
if s:p4Client != "" && (match(s:p4DefaultOptions, '-c\>') == -1)
  let s:defaultOptions = s:defaultOptions . " -c " . s:p4Client
endif
if s:p4User != "" && (match(s:p4DefaultOptions, '-u\>') == -1)
  let s:defaultOptions = s:defaultOptions . " -u " . s:p4User
endif
if s:p4Port != "" && (match(s:p4DefaultOptions, '-p\>') == -1)
  let s:defaultOptions = s:defaultOptions . " -p " . s:p4Port
endif

""" The following are some shortcut commands. Some of them are enhanced such
"""   as the help window or the filelog window.

" Equivalent to: p4 print %
command! -nargs=* -complete=file PP :call <SID>PPrint(0, <f-args>)
" Equivalent to: p4 diff %. You can pass in arguments to diff and a filename.
command! -nargs=* -complete=file PD :call <SID>PDiff(0, <f-args>)
" Equivalent to: p4 edit %
command! -nargs=* -complete=file PE :call <SID>PEdit(20, <f-args>)
" Equivalent to: p4 add %
command! -nargs=* -complete=file PA :call <SID>PAdd(20, <f-args>)
" Equivalent to: p4 delete %
command! -nargs=* -complete=file PDelete :call <SID>PDelete(20, <f-args>)
" Equivalent to: p4 lock %
command! -nargs=* -complete=file PLock :call <SID>PLock(20, <f-args>)
" Equivalent to: p4 unlock %
command! -nargs=* -complete=file PUnlock :call <SID>PUnlock(20, <f-args>)
" Equivalent to: p4 revert %
command! -nargs=* -complete=file PR :call <SID>PRevert(20, <f-args>)
" Equivalent to: p4 get/sync %
command! -nargs=* -complete=file PSync :call <SID>PSync(20, <f-args>)
command! -nargs=* -complete=file PG :call <SID>PSync(20, <f-args>)
" Equivalent to: p4 opened
command! -nargs=* PO :call <SID>POpened(0, <f-args>)
" Equivalent to: p4 have
command! -nargs=* PHave :call <SID>PHave(0, <f-args>)
" Equivalent to: p4 describe
command! -nargs=* PDescribe :call <SID>PDescribe(0, <f-args>)
" Equivalent to: p4 files
command! -nargs=* PFiles :call <SID>PFiles(0, <f-args>)
" Equivalent to: p4 labelsync
command! -nargs=* PLabelsync :call <SID>PFIF(0, 0, 0, "labelsync", <f-args>)
" Equivalent to: p4 filelog. You can press <Enter> to view the revision, or
"   press S to sync to that revision. You can also press C to describe the
"   change.
command! -nargs=* PFilelog :call <SID>PFilelog(0, <f-args>)
" Equivalent to: p4 diff2 %. You will be prompted for the two revisions. You
"   can pass in arguments diff2, but not a filename. The current filename is
"   always assumed.
command! -nargs=* -complete=file PD2 :call <SID>PDiff2(0, <f-args>)
" Equivalent to: p4 fstat %.
command! -nargs=* -complete=file PFstat :call <SID>PFstat(0, <f-args>)
" Same as: p4 help. You can drill down the help by pressing <Enter>
command! -nargs=* PH :call <SID>PHelp(5, <f-args>)


""" Some list view commands.
""" Just so that user expects them.
command! -nargs=* PChanges :call <SID>PChanges(0, <f-args>)
command! -nargs=* PBranches :PF branches <args>
command! -nargs=* PLabels :call <SID>PLabels(0, <f-args>)
command! -nargs=* PClients :PF clients <args>
command! -nargs=* PUsers :PF users <args>
command! -nargs=* PJobs :call <SID>PJobs(0, <f-args>)
command! -nargs=* PDepots :PF depots <args>
command! -nargs=* PGroups :PF groups <args>


""" The following support some p4 operations that normally involve some
"""   interaction with the user (they are more than just shortcuts).

" Same as: p4 change. You can edit and save change spec. by using :W command.
command! -nargs=* PChange :call <SID>PChange(0, <f-args>)
" Same as: p4 branch. You can edit and save branch spec. by using :W command.
command! -nargs=* PBranch :call <SID>PBranch(0, <f-args>)
" Same as: p4 label. You can edit and save label spec. by using :W command.
command! -nargs=* PLabel :call <SID>PLabel(0, <f-args>)
" Same as: p4 client. You can edit and save client spec. by using :W command.
command! -nargs=* PClient :call <SID>PClient(0, <f-args>)
" Same as: p4 user. You can edit and save user spec. by using :W command.
command! -nargs=* PUser :call <SID>PUser(0, <f-args>)
" Same as: p4 job. You can edit and save job spec. by using :W command.
command! -nargs=* PJob :call <SID>PJob(0, <f-args>)
" Same as: p4 jobspec. You can edit and save jobspec. by using :W command.
command! -nargs=* PJobspec :call <SID>PJobspec(0, <f-args>)
" Same as: p4 depot. You can edit and save depot spec. by using :W command.
command! -nargs=* PDepot :call <SID>PDepot(0, <f-args>)
" Same as: p4 group. You can edit and save group spec. by using :W command.
command! -nargs=* PGroup :call <SID>PGroup(0, <f-args>)
" Generates a template for p4 submit. You can edit and submit using the :W
"   command.
command! -nargs=0 PSubmit :call <SID>PSubmit(0)
" Currently just a shortcut for "p4 resolve", but hope to implement something
" better.
command! -nargs=* PResolve :call <SID>PResolve(0, <f-args>)

""" Other utility commands.

" E <codeline> [files: default %]
" You can open a file that you are viewing from a different codeline by using
" this command. You can specify more than one file in which case the first one
" is still opened, but the remaining files are just added to the buffer list.
command! -nargs=* -complete=file E :call <SID>PFOpenAltFile(<f-args>)
" No args: Print presets and prompt user to select a preset.
" Number: Select that numbered preset (index starts from 0). 
" Usage: PSwitch port [client] [user]
command! -nargs=* PSwitch :call <SID>PSwitch(<f-args>)
" Refresh the active pane.
command! -nargs=0 PRefreshActivePane :call <SID>PRefreshActivePane()
" You can specify any p4 command using this command. The command is executed
" and the output is placed in a new window. But don't run the commands that
" require user input such as "p4 submit".
command! -nargs=* -complete=file PF :call <SID>PFIF(0, 0, 0, <f-args>)
" Same as PF, but a raw output is generated.
command! -nargs=* -complete=file PFRaw :call <SID>PFRaw(0, <f-args>)
" Write the current file contents as input into the specified p4 command. You
" can specify a range.
command! -nargs=* -complete=file -range=% PW
      \ :<line1>,<line2>call <SID>PW(<f-args>)
command! -nargs=* W :echohl WarningMsg |
      \ echo "Use PW if you want to write current buffer into a perforce command"
      \ | echohl NONE

function! s:CreateDummyCommand(cmdName)
  exec "command! " . a:cmdName . " echohl WarningMsg | " .
	\ "echo 'This command is not defined for this buffer.' | echohl NONE"
endfunction
call s:CreateDummyCommand('PItemDescribe')
call s:CreateDummyCommand('PItemOpen')
call s:CreateDummyCommand('PItemDelete')
call s:CreateDummyCommand('PFilelogSync')
call s:CreateDummyCommand('PFilelogDescribe')
call s:CreateDummyCommand('PChangesSubmit')
call s:CreateDummyCommand('PChangesOpened')
call s:CreateDummyCommand('PLabelsSyncClient')
call s:CreateDummyCommand('PLabelsSyncLabel')
call s:CreateDummyCommand('PFileDiff')
call s:CreateDummyCommand('PFileProps')
call s:CreateDummyCommand('PFileRevert')
delfunction s:CreateDummyCommand


let s:changesExpr  = "matchstr(getline(\".\"), " . "'" . '^Change \zs\d\+\ze ' .
      \ "'" . ")"
let s:branchesExpr = "matchstr(getline(\".\"), " . "'" .
      \ '^Branch \zs[^ ]\+\ze ' . "'" . ")"
let s:labelsExpr   = "matchstr(getline(\".\"), " . "'" .
      \ '^Label \zs[^ ]\+\ze ' . "'" . ")"
let s:clientsExpr  = "matchstr(getline(\".\"), " . "'" .
      \ '^Client \zs[^ ]\+\ze ' . "'" . ")"
let s:usersExpr    = "matchstr(getline(\".\"), " . "'" .
      \ '^[^ ]\+\ze <[^@>]\+@[^>]\+> ([^)]\+)' . "'" . ")"
let s:jobsExpr     = "matchstr(getline(\".\"), " . "'" . '^[^ ]\+\ze on ' .
      \ "'" . ")"
let s:depotsExpr   = "matchstr(getline(\".\"), " . "'" .
      \ '^Depot \zs[^ ]\+\ze ' . "'" . ")"
"let s:openedExpr   = "s:ConvertToLocalPath(expand('<cfile>'))"
"let s:describeExpr = "s:ConvertToLocalPath(expand('<cfile>'))"
"let s:filesExpr    = "s:ConvertToLocalPath(expand('<cfile>'))"
let s:openedExpr   = "s:ConvertToLocalPath(s:GetCurrentDepotFile(line('.')))"
"let s:describeExpr = "s:ConvertToLocalPath(s:GetCurrentDepotFile(line('.')))"
let s:describeExpr = "s:DescribeGetCurrentItem()"
let s:filesExpr    = "s:ConvertToLocalPath(s:GetCurrentDepotFile(line('.')))"
let s:haveExpr     = "s:ConvertToLocalPath(s:GetCurrentDepotFile(line('.')))"
let s:filelogExpr  = "s:GetCurrentDepotFile(line('.'))"
let s:groupsExpr   = "expand('<cword>')"

" If an explicit handler is defined, then it will override the default rule of
" finding the command with the singular form.
let s:filelogItemHandler = "s:PPrint"
let s:changesItemHandler = "s:PChange"
let s:openedItemHandler = "s:OpenFile"
let s:describeItemHandler = "s:OpenFile"
let s:filesItemHandler = "s:OpenFile"
let s:haveItemHandler = "s:OpenFile"



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
  endif

  if ! a:expanded
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Opened\ Files :PO<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Refresh\ Active\ Pane ' .
          \ ':PRefreshActivePane<CR>'
  exec 'amenu <silent> ' . a:sub . '&Perforce.-Sep5- :'
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
              \ . escape(nextSet, ' ') . ' :PSwitch ' . index . '<CR>'
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
          \ '&Edit\ Current\ Changelist :PItemOpen<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Changelist.' .
          \ 'Descri&be\ Current\ Changelist :PItemDescribe<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Changelist.' .
          \ '&Delete\ Current\ Changelist :PItemDelete<CR>'
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
          \ '&Edit\ Current\ BranchSpec :PItemOpen<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Branch.' .
          \ 'Descri&be\ Current\ BranchSpec :PItemDescribe<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Branch.' .
          \ '&Delete\ Current\ BranchSpec :PItemDelete<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Branch.-Sep- :'
    exec 'amenu <silent> ' . a:sub .
          \ '&Perforce.&Branch.&View\ BranchSpecs :PBranches<CR>'
  endif

  if ! a:expanded
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Label :PLabel<CR>'
  else
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Label.&New :PLabel<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Label.' .
          \ '&Edit\ Current\ LabelSpec :PItemOpen<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Label.' .
          \ 'Descri&be\ Current\ LabelSpec :PItemDescribe<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Label.' .
          \ '&Delete\ Current\ LabelSpec :PItemDelete<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Label.-Sep1- :'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Label.' .
          \ '&Sync\ Client\ ' . s:p4Client . '\ to\ Current\ Label ' .
          \ ':PLabelsSyncClient<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Label.' .
          \ '&Replace\ Files\ in\ Current\ Label\ with\ Client\ ' . s:p4Client .
          \ '\ files ' . ':PLabelsSyncLabel<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Label.-Sep2- :'
    exec 'amenu <silent> ' . a:sub .
          \ '&Perforce.&Label.&View\ Labels :PLabels<CR>'
  endif

  if ! a:expanded
    exec 'amenu <silent> ' . a:sub . '&Perforce.Cl&ient :PClient<CR>'
  else
    exec 'amenu <silent> ' . a:sub .
          \ '&Perforce.Cl&ient.&New :call s:NewClient()<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.Cl&ient.' .
          \ '&Edit\ Current\ ClientSpec :PItemOpen<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.Cl&ient.' .
          \ 'Descri&be\ Current\ ClientSpec :PItemDescribe<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.Cl&ient.' .
          \ '&Delete\ Current\ ClientSpec :PItemDelete<CR>'
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
          \ '&Perforce.&User.&New :call s:NewUser()<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&User.' .
          \ '&Edit\ Current\ UserSpec :PItemOpen<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&User.' .
          \ 'Descri&be\ Current\ UserSpec :PItemDescribe<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&User.' .
          \ '&Delete\ Current\ UserSpec :PItemDelete<CR>'
    exec 'amenu <silent> ' . a:sub .
          \ '&Perforce.&User.&Edit\ ' . escape(s:p4User, ' ') . ' :PSU<CR>'
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
          \ '&Edit\ Current\ JobSpec :PItemOpen<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Job.' .
          \ 'Descri&be\ Current\ JobSpec :PItemDescribe<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Job.' .
          \ '&Delete\ Current\ JobSpec :PItemDelete<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Job.-Sep1- :'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Job.&Edit\ Job&Spec ' .
	  \ ':PJobspec<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Job.-Sep2- :'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Job.&View\ Jobs :PJobs<CR>'
  endif

  if a:expanded
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Depot.&New :PDepot<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Depot.' .
          \ '&Edit\ Current\ DepotSpec :PItemOpen<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Depot.' .
          \ 'Descri&be\ Current\ DepotSpec :PItemDescribe<CR>'
    exec 'amenu <silent> ' . a:sub . '&Perforce.&Depot.' .
          \ '&Delete\ Current\ DepotSpec :PItemDelete<CR>'
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

  exec 'amenu <silent> ' . a:sub . '&Perforce.-Sep4- :'
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
endfunction

"
" Add menu entries if user wants.
"

if exists("g:p4UseExpandedMenu")
  let s:useExpandedMenu = g:p4UseExpandedMenu
  unlet g:p4UseExpandedMenu
elseif !exists("s:useExpandedMenu")
  let s:useExpandedMenu = 0
endif

if exists("g:p4UseExpandedPopupMenu")
  let s:useExpandedPopupMenu = g:p4UseExpandedPopupMenu
  unlet g:p4UseExpandedPopupMenu
elseif !exists("s:useExpandedPopupMenu")
  let s:useExpandedPopupMenu = 0
endif

if exists("g:p4EnableMenu")
  let s:enableMenu = g:p4EnableMenu
  unlet g:p4EnableMenu
elseif !exists("s:enableMenu")
  let s:enableMenu = 0
endif

silent! unmenu Perforce
silent! unmenu! Perforce
if s:enableMenu
  call s:CreateMenu('', s:useExpandedMenu)
endif

if exists("g:p4EnablePopupMenu")
  let s:enablePopupMenu = g:p4EnablePopupMenu
  unlet g:p4EnablePopupMenu
elseif !exists("s:enablePopupMenu")
  let s:enablePopupMenu = 0
endif

silent! unmenu PopUp.Perforce
silent! unmenu! PopUp.Perforce
if s:enablePopupMenu
  call s:CreateMenu('PopUp.', s:useExpandedPopupMenu)
endif

aug P4
au!
if s:promptToCheckout
  au FileChangedRO * nested :call <SID>CheckOutFile()
endif
aug END


" Initialize some script variables.
function! s:ResetP4Vars()
  let s:p4Options = ""
  let s:p4Command = ""
  let s:p4Arguments = ""
  let s:p4LastArg = ""
  let s:p4WinName = ""
endfunction
call s:ResetP4Vars()

" Determine the script id.
function! s:MyScriptId()
  map <SID>xx <SID>xx
  let s:sid = maparg("<SID>xx")
  unmap <SID>xx
  return substitute(s:sid, "xx$", "", "")
endfunction
let s:myScriptId = s:MyScriptId()
delfunction s:MyScriptId

" On cygwin bash, p4 sometimes gets confused with the PWD env variable???
if OnMS() && match(&shell, '\<bash\>') != -1
  let s:p4CommandPrefix = "unset PWD && "
else
  let s:p4CommandPrefix = ""
endif

let s:p4KnownCmds = "add,admin,branch,branches,change,changes,client,clients," .
      \ "counter,counters,delete,depot,depots,describe,diff,diff2,dirs,edit," .
      \ "filelog,files,fix,fixes,flush,fstat,group,groups,have,help,info," .
      \ "integrate,integrated,job,jobs,jobspec,label,labels,labelsync,lock," .
      \ "logger,obliterate,opened,passwd,print,protect,rename,reopen,resolve," .
      \ "resolved,revert,review,reviews,set,submit,sync,triggers,typemap," .
      \ "unlock,user,users,verify,where,"

let s:p4SubmitTemplate = "Change:\tnew\n\n" .
      \ "Client:\t" . s:p4Client . "\n\n" .
      \ "User:\t" . s:p4User . "\n\n" .
      \ "Status:\tnew\n\n" .
      \ "Description:\n\t<enter description here>\n\n" .
      \ "Files:\n"

let s:helpWinName = 'P4\ help'

" Delete unnecessary stuff.
delfunction s:CreateMenu

endfunction " s:Initialize }}}
call s:Initialize()


function! s:PPrint(outputType, ...)
  exec g:makeArgumentString
  exec "let err = s:PFIF(1, a:outputType, '12', 'print', " . argumentString .
	\ ")"

  if !err && s:StartBufSetup(a:outputType)
    let &ft=s:GuessFileTypeForCurrentWindow()

    call s:EndBufSetup(a:outputType)
  endif
endfunction


function! s:PFiles(outputType, ...)
  exec g:makeArgumentString
  exec "let err = s:PFIF(1, a:outputType, 0, 'files', " . argumentString . ")"
  if !err && s:StartBufSetup(a:outputType)
    call s:SetupFileBrowse(a:outputType)

    call s:EndBufSetup(a:outputType)
  endif
endfunction


function! s:POpened(outputType, ...)
  exec g:makeArgumentString
  exec "let err = s:PFIF(1, a:outputType, 0, 'opened', " . argumentString . ")"
  if !err && s:StartBufSetup(a:outputType)
    call s:SetupFileBrowse(a:outputType)

    call s:EndBufSetup(a:outputType)
  endif
endfunction


" Default to current file.
function! s:PHave(outputType, ...)
  exec g:makeArgumentString
  exec "let err = s:PFIF(1, a:outputType, 1, 'have', " . argumentString . ")"
  if !err && s:StartBufSetup(a:outputType)
    call s:SetupFileBrowse(a:outputType)

    call s:EndBufSetup(a:outputType)
  endif
endfunction


function! s:PDescribe(outputType, ...)
  exec g:makeArgumentString
  let argumentString = s:AddDiffOptions(argumentString)

  exec "let err = s:PFIF(1, a:outputType, 1, 'describe', " . argumentString .
        \ ")"
  if !err && s:StartBufSetup(a:outputType)
    call s:SetupFileBrowse(a:outputType)
    if match(argumentString, '-s\>') != -1
      setlocal modifiable
      call append('$', "\t<SHOW DIFFS>")
      setlocal nomodifiable
    endif

    call s:EndBufSetup(a:outputType)
  endif
endfunction


function! s:DescribeGetCurrentItem()
  if getline(".") == "\t<SHOW DIFFS>"
    let b:p4FullCmd = substitute(b:p4FullCmd, '-s\>', '', '')
    call s:PRefreshActivePane()
    return ""
  else
    return s:ConvertToLocalPath(s:GetCurrentDepotFile(line('.')))
  endif
endfunction


function! s:PDiff(outputType, ...)
  exec g:makeArgumentString
  let argumentString = s:AddDiffOptions(argumentString)

  exec "let err = s:PFIF(1, a:outputType, 1, 'diff', " . argumentString . ")"
  if !err && s:StartBufSetup(a:outputType)
    set ft=diff

    call s:EndBufSetup(a:outputType)
  endif
endfunction


function! s:PEdit(outputType, ...)
  exec g:makeArgumentString
  let _autoread = &autoread
  set autoread
  exec "let err = s:PFIF(1, " . a:outputType . ", 1, 'edit', " .
        \ argumentString . ")"
  checktime
  let &autoread = _autoread
endfunction


function! s:PAdd(outputType, ...)
  exec g:makeArgumentString
  exec "let err = s:PFIF(1, " . a:outputType . ", 1, 'add', " . argumentString .
        \ ")"
endfunction


function! s:PFstat(outputType, ...)
  exec g:makeArgumentString
  exec "let err = s:PFIF(1, " . a:outputType . ", 1, 'fstat', " .
        \ argumentString . ")"
endfunction


function! s:PDelete(outputType, ...)
  exec g:makeArgumentString
  exec "let err = s:PFIF(1, " . a:outputType . ", 1, 'delete', " .
        \ argumentString . ")"
  checktime
endfunction


function! s:PLock(outputType, ...)
  exec g:makeArgumentString
  exec "let err = s:PFIF(1, " . a:outputType . ", 1, 'lock', " .
        \ argumentString . ")"
endfunction


function! s:PUnlock(outputType, ...)
  exec g:makeArgumentString
  exec "let err = s:PFIF(1, " . a:outputType . ", 1, 'unlock', " .
        \ argumentString . ")"
endfunction


function! s:PRevert(outputType, ...)
  let option = confirm("Reverting file(s) will overwrite any edits to the " .
        \ "files(s)\n Proceed with Revert?", "&Yes\n&No", 2, "Question")
  if option == 2
    return
  endif

  exec g:makeArgumentString
  let _autoread = &autoread
  set autoread
  exec "let err = s:PFIF(1, " . a:outputType . ", 1, 'revert', " .
        \ argumentString . ")"
  checktime
  let &autoread = _autoread
endfunction


function! s:PSync(outputType, ...)
  exec g:makeArgumentString
  let _autoread = &autoread
  set autoread
  exec "let err = s:PFIF(1, " . a:outputType . ", '12', 'sync', " .
        \ argumentString . ")"
  checktime
  let &autoread = _autoread
endfunction


function! s:PDiff2(outputType, ...)
  " TODO: This check is not sufficient, as the arguments could include the
  " diff options also.
  if a:0 < 2
    if a:0 == 0
      let argumentString = ""
      let file = expand("%")
    else
      exec g:makeArgumentString
      " Get the last argument as a file and remove it from argumentString.
      exec "let file = a:" . a:0
      let argumentString = MvRemoveElement(argumentString, ',', (a:0 - 1))
    endif
    let ver1 = s:PromptFor(0, s:useDialogs, "Version1? ", '')
    let ver2 = s:PromptFor(0, s:useDialogs, "Version2? ", '')
    let argumentString = MvAddElement(argumentString, ',',
          \ " '" . file . '#' . ver1 . "'")
    let argumentString = MvAddElement(argumentString, ',',
          \ " '" . file . '#' . ver2 . "'")
  else
    exec g:makeArgumentString
  endif

  let argumentString = s:AddDiffOptions(argumentString)
  exec "let err = s:PFIF(1, a:outputType, 0, 'diff2', " . argumentString . ")"
  if !err && s:StartBufSetup(a:outputType)
    set ft=diff

    call s:EndBufSetup(a:outputType)
  endif
endfunction


" Open a file from an alternative codeline.
" First argument is expected to be codeline, and the remaining arguments are
" expected to be filenames. 
function! s:PFOpenAltFile(...)
  if a:0 == 0
    " Prompt for codeline.
    let codeline = s:PromptFor(0, s:useDialogs,
          \ "Enter the alternative codeline: ", '')
    if codeline == ""
      echohl Error | echo "Codeline required." | echohl NONE
      return
    endif
  else
    let codeline = a:1
  endif
  " If the filenanme argument is mising, then assume it is for the current file.
  if a:0 < 2
    let argumentString = "'" . codeline . "'"
    let argumentString = argumentString . ", '" . expand("%") . "'"
  else
    exec g:makeArgumentString
  endif

  exec "let altFileNames = s:PFGetAltFiles(" . argumentString . ")"
  if a:0 == 1
    let n = 1
  else
    let n = MvNumberOfElements(altFileNames, ';')
  endif
  if n == 1
    execute ":edit " . altFileNames
  else
    call MvIterCreate(altFileNames, ';', "Perforce")
    while MvIterHasNext("Perforce")
      execute ":badd " . MvIterNext("Perforce")
    endwhile
    call MvIterDestroy("Perforce")
    execute ":edit " . MvElementAt(altFileNames, ";", 0)
  endif
endfunction


" Interactively change the port/client/user.
function! s:SwitchPortClientUser()
  let p4Port = s:PromptFor(0, s:useDialogs, "Port: ", s:p4Port)
  let p4Client = s:PromptFor(0, s:useDialogs, "Client: ", s:p4Client)
  let p4User = s:PromptFor(0, s:useDialogs, "User: ", s:p4User)
  call s:PSwitch(p4Port, p4Client, p4User)
endfunction


" No args: Print presets and prompt user to select a preset.
" Number: Select that numbered preset. 
" port [client] [user]: Set the specified settings.
function! s:PSwitch(...)
  let nSets = MvNumberOfElements(s:p4Presets, ',')
  if a:0 == 0
    if nSets == 0
      echohl ERROR | echo "No sets to select from." | echohl None
      return
    endif

    let selectedSetting = MvPromptForElement(s:p4Presets, ',', 0,
          \ "Select the setting: ", -1, s:useDialogs)
    call s:PSwitchHelper(selectedSetting)
    return
  else
    if match(a:1, '^\d\+') == 0
      let index = a:1 + 0
      if index >= nSets
        echohl ERROR | echo "Not that many sets." | echohl None
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
    call s:Initialize()
  endif
endfunction


function! s:PSwitchHelper(settingStr)
  if a:settingStr != ""
    let settingStr = substitute(a:settingStr, '\s\+', "','", 'g')
    let settingStr = substitute(settingStr, '^', "'", '')
    let settingStr = substitute(settingStr, '$', "'", '')
    exec 'call s:PSwitch(' . settingStr . ')'
  endif
endfunction


function! s:PChange(outputType, ...)
  exec g:makeArgumentString
  exec "call s:InteractiveCommand(a:outputType, 'change', 'interactive', " .
        \ " 'none', '^<enter description here>\\|^Description:', " .
        \ argumentString . ")"
endfunction


function! s:PBranch(outputType, ...)
  exec g:makeArgumentString
  exec "call s:InteractiveCommand(a:outputType, 'branch', 'interactive', " .
        \ "'ask', '^View:', " . argumentString . ")"
endfunction


function! s:PLabel(outputType, ...)
  exec g:makeArgumentString
  exec "call s:InteractiveCommand(a:outputType, 'label', 'interactive', " .
        \ "'ask', '^View:', " . argumentString . ")"
endfunction


function! s:NewClient()
  let clientName = s:PromptFor(0, s:useDialogs, "Client name: ", '')
  if clientName == ""
    echohl Error | echo "Client name required." | echohl NONE
    return
  endif
  call s:PClient(0, clientName)
endfunction


function! s:PClient(outputType, ...)
  exec g:makeArgumentString
  exec "call s:InteractiveCommand(a:outputType, 'client', 'interactive', " .
        \ "'none', '^View:', " . argumentString . ")"
endfunction


function! s:PJob(outputType, ...)
  exec g:makeArgumentString
  exec "call s:InteractiveCommand(a:outputType, 'job', 'interactive', " .
        \ "'none', '^Job:', " . argumentString . ")"
endfunction


function! s:PJobspec(outputType, ...)
  exec g:makeArgumentString
  exec "call s:InteractiveCommand(a:outputType, 'jobspec', 'interactive', " .
        \ "'none', '^Fields:', " . argumentString . ")"
endfunction


function! s:NewUser()
  let userName = s:PromptFor(0, s:useDialogs, "User name: ", '')
  if userName == ""
    echohl Error | echo "Client name required." | echohl NONE
    return
  endif
  call s:PUser(0, userName)
endfunction


function! s:PUser(outputType, ...)
  exec g:makeArgumentString
  exec "call s:InteractiveCommand(a:outputType, 'user', 'interactive', " .
        \ "'none', '^User:', " . argumentString . ")"
endfunction


function! s:PDepot(outputType, ...)
  exec g:makeArgumentString
  exec "call s:InteractiveCommand(a:outputType, 'depot', 'interactive', " .
        \ "'ask', '^Description:', " . argumentString . ")"
endfunction


function! s:PGroup(outputType, ...)
  exec g:makeArgumentString
  exec "call s:InteractiveCommand(a:outputType, 'group', 'interactive', " .
        \ "'ask', '^Users:', " . argumentString . ")"
endfunction


function! s:PResolve(outputType, ...)
  exec g:makeArgumentString
  exec "call s:ParseOptions(" . argumentString . ")"
  if s:p4Command == ""
    exec "call s:ParseOptions('resolve', " . argumentString . ")"
  endif

  if (match(s:p4Arguments, '-a[fmsty]\>') == -1) &&
        \ (match(s:p4Arguments, '-n\>') == -1)
    echohl Error | echo "Interactive resolve not implemented (yet)." | echohl None
    return
  endif
  exec "let err = s:PFIF(1, a:outputType, 0, 'resolve', " . argumentString . ")"
endfunction


" Create a template for submit.
function! s:PSubmit(outputType, ...)
  exec g:makeArgumentString
  exec "call s:ParseOptions(" . argumentString . ")"
  if s:p4Command == ""
    exec "call s:ParseOptions('submit', " . argumentString . ")"
  endif

  if s:p4Arguments == ""
    call s:ResetP4Vars()
    let s:p4Command = "submit"
    let s:p4WinName = 'P4\ submit'

    call s:PFImpl(a:outputType, "", 2, s:p4SubmitTemplate)
    $
    -mark t
    $call s:PW("opened")
    let _saveSearch = @/
    let @/ = "^"
    silent! 't+1,$s//\t/
    let @/ = _saveSearch
    command! -buffer -nargs=* W :1,$call <SID>PW("submit", "-i", <f-args>)
    if search('<enter description here>', 'w') != 0
      normal! zz
    endif
    redraw | echo "When done, submit the change by using the :W command. " .
          \ "Undo if you see an error."
  else
    if match(s:p4Arguments, '-s\>') != -1 "|| match(argumentString, '-i\>') != -1
      echohl ERROR | echo "Unsupported usage of submit command." | echohl NONE
      return
    endif
    exec "let err = s:PFIF(1, a:outputType, 0, 'submit', " . argumentString .
          \ ")"
  endif
endfunction


function! s:PFilelog(outputType, ...)
  exec g:makeArgumentString
  exec "let err = s:PFIF(1, a:outputType, 1, 'filelog', " . argumentString . ")"

  if !err && s:StartBufSetup(a:outputType)
    set ft=perforce
    silent! nunmap <buffer> D " No meaning for delete.
    silent! delcommand PItemDelete
    silent! nunmap <buffer> O " No meaning for open/edit.
    silent! delcommand PItemOpen
    command! -range -buffer -nargs=0 PFilelogDiff
          \ :call s:FilelogDiff2(<line1>, <line2>)
    vnoremap <silent> <buffer> D :PFilelogDiff<CR>
    command! -buffer -nargs=0 PFilelogSync :call <SID>FilelogSyncToCurrentItem()
    nnoremap <silent> <buffer> S :PFilelogSync<CR>
    command! -buffer -nargs=0 PFilelogDescribe
          \ :call <SID>FilelogDescribeChange()
    nnoremap <silent> <buffer> C :PFilelogDescribe<CR>

    call s:EndBufSetup(a:outputType)
  endif
endfunction


function! s:RunLimitListCommand(outputType, commandName, ...)
  exec g:makeArgumentString
  if match(argumentString, '-m\>') == -1 && s:defaultListSize > -1
    " Insert -m <size> arguments just after the command name.
    if match(argumentString, '\<' . a:commandName . '\>') != -1
      let argumentString = substitute(argumentString, '\<' . a:commandName .
	    \ '\>', a:commandName . "', '-m', '" . s:defaultListSize, '')
    else
      let argumentString = "'-m', '" . s:defaultListSize . "', " .
	    \ argumentString
  endif
  exec "let err = s:PFIF(1, a:outputType, 1, a:commandName, " .
	\ argumentString . ")"
  return err
endfunction


function! s:PJobs(outputType, ...)
  exec g:makeArgumentString
  exec "let err = s:RunLimitListCommand(a:outputType, 'jobs', " .
	\ argumentString . ")"
endfunction


function! s:PChanges(outputType, ...)
  exec g:makeArgumentString
  exec "let err = s:RunLimitListCommand(a:outputType, 'changes', " .
	\ argumentString . ")"

  if !err && s:StartBufSetup(a:outputType)
    command! -buffer -nargs=0 PItemDescribe :call <SID>PDescribe(1, '-s',
          \ <SID>GetCurrentItem())
    command! -buffer -nargs=0 PChangesSubmit
          \ :call <SID>ChangesSubmitChangeList()
    nnoremap <silent> <buffer> S :PChangesSubmit<CR>
    command! -buffer -nargs=0 PChangesOpened :call <SID>POpened(0, '-c',
          \ <SID>GetCurrentItem())
    nnoremap <silent> <buffer> o :PChangesOpened<CR>

    call s:EndBufSetup(a:outputType)
  endif
endfunction


function! s:PLabels(outputType, ...)
  exec g:makeArgumentString
  exec "let err = s:PFIF(1, a:outputType, 0, 'labels', " . argumentString . ")"

  if !err && s:StartBufSetup(a:outputType)
    command! -buffer -nargs=0 PLabelsSyncClient
          \ :call <SID>LabelsSyncClientToLabel()
    nnoremap <silent> <buffer> S :PLabelsSyncClient<CR>
    command! -buffer -nargs=0 PLabelsSyncLabel
          \ :call <SID>LabelsSyncLabelToClient()
    nnoremap <silent> <buffer> C :PLabelsSyncLabel<CR>

    call s:EndBufSetup(a:outputType)
  endif
endfunction


function! s:InteractiveCommand(outputType, commandName, commandType,
      \ argExpected, pattern, ...)

  exec g:makeArgumentString
  " First check if the commandName is already passed in, if not then specify
  " it and try again.
  exec "call s:ParseOptions(" . argumentString . ")"
  if s:p4Command == ""
    exec "call s:ParseOptions('" . a:commandName . "', " . argumentString . ")"
  elseif s:p4Command != a:commandName
    echohl ERROR | echo "Invalid command usage... try 'PH " . a:commandName .
          \ "'" | echohl NONE
    return
  endif

  " Check not sufficient if the user gives other arguments and forgets to give
  "   name.
  if s:p4LastArg == "" || s:p4Arguments == ""
    let additionalArg = ""
    if a:argExpected == "ask"
      let additionalArg = s:PromptFor(0, s:useDialogs,
            \ "Enter the " . a:commandName . " name: ", '')
      if additionalArg == ""
        echohl Error | echo substitute(a:commandName, "^.", '\U&', '') .
              \ " name required." | echohl NONE
        return
      endif
    elseif a:argExpected == "curfile"
      let additionalArg = expand("%")
    endif
    if additionalArg != ""
      let s:p4Arguments = MvAddElement(s:p4Arguments, ' ', additionalArg)
    endif
  endif

  " If the command is to be run in interactive mode, then make sure the -o
  " options is specified.
  let interactiveMode = 0
  if a:commandType == "interactive"
    if match(s:p4Arguments, '-d\>') == -1
      let s:p4Arguments = "-o " . s:p4Arguments
      if a:outputType == 0 " Only if in the edit mode.
      endif
      " Go into interactive mode only if the user intends to edit the output.
      if a:outputType == 0
        let interactiveMode = 1
      endif
    endif
  endif

  if s:PFImpl(a:outputType, s:p4CommandPrefix, 0, "") != 0
    return
  endif

  if s:StartBufSetup(a:outputType)
    if a:pattern != "" && search(a:pattern, 'w') != 0
      normal! zz
    endif
    set ft=perforce

    " Set some options for text editing.
    setlocal tabstop=8
    setlocal softtabstop=0
    setlocal shiftwidth=8
    setlocal noexpandtab
    setlocal autoindent

    call s:EndBufSetup(a:outputType)
  endif

  if interactiveMode
    setlocal modifiable
    exec 'command! -buffer -nargs=* W :1,$call <SID>PW("' . a:commandName .
          \ '", "-i", <f-args>)'
    redraw | echo "When done, save " . a:commandName .
          \ " spec by using the :W command. Undo if you see an error."
  endif
endfunction


function! s:PHelp(outputType, ...)
  call SaveWindowSettings2("PerforceHelp", 0)
  " If there is a help window already open, then we need to reuse it.
  exec g:makeArgumentString

  exec "let err = s:PFIF(1, a:outputType, 0, 'help', " . argumentString . ")"

  if !err && s:StartBufSetup(a:outputType)
    call s:SetupSelectHelp()
    " Maximize the window, like vim help window.
    wincmd K
    wincmd _
    redraw | echo "Press <Enter> or K to drilldown on perforce help keywords."

    call s:EndBufSetup(a:outputType)
  endif
endfunction


function! s:CheckOutFile()
  if filereadable(expand("%")) && ! filewritable(expand("%"))
    let option = confirm("Readonly file, do you want to checkout from perforce?"
          \, "&Yes\n&No", 1, "Question")
    if option == 1
      call s:PEdit(2)
    endif
    edit!
  endif
endfunction


" Filter contents through p4.
function! s:PW(...) range
  exec g:makeArgumentString
  exec "call s:ParseOptions(" . argumentString . ")"

  setlocal modifiable
  call s:PFImpl(4, a:firstline . ',' . a:lastline . '!' . s:p4CommandPrefix, 1,
        \ "")
endfunction


" The commandName may not be the commandName always when the user types in,
"   but at least it is (and should be), for the scriptOrigin.
" argOptions: A combination string of one or more of the following flags.
"   0 - No special handling.
"   1 - Default to current file. 
"   2 - Treat the number arg as a version to the current file. 
function! s:PFIF(scriptOrigin, outputType, argOptions, commandName, ...)
  exec g:makeArgumentString
    " For scriptOrigin, there is a possibility of having the commandName
    "   already in the var. args.
  if MvContainsElement(s:p4KnownCmds, ',', a:commandName) && a:scriptOrigin
    exec "call s:ParseOptions(" . argumentString . ")"
    " Add a:commandName only if it doesn't already exist in the var args. 
    " Handles cases like "PF help submit" and "PF -c <client> help submit",
    "   where the commandName need not be at the starting and there could be
    "   more than one valid commandNames (help and submit).
    if s:p4Command != a:commandName
      exec "call s:ParseOptions('" . a:commandName . "', " . argumentString .
            \ ")"
    endif
  else
    exec "call s:ParseOptions('" . a:commandName . "', " . argumentString . ")"
  endif

  if ! a:scriptOrigin
    let redirect = s:getCommandHandler(s:p4Command)
    if redirect != ""
      exec "call " . redirect . "(" . a:outputType . ", '" . a:commandName .
            \ "', " . argumentString . ")"
      return 0
    endif
  endif

  " Handle arguments based on the argOptions.
  if a:argOptions =~ "1" && s:p4LastArg == ""
    " I expect s:p4Arguments to be empty in this case, but just in case...
    let s:p4Arguments = MvAddElement(s:p4Arguments, ' ', expand("%"))
  endif
  if a:argOptions =~ "2" && s:p4LastArg =~ '^[\\]\+#\(\d\+\|none\|head\|have\)$'
    let s:p4Arguments = substitute(s:p4Arguments,
          \ '[\\]\+#\(\d\+\|none\|head\|have\)$', expand("%") . '\\#\1', '')
  endif
  if a:argOptions =~ "2" && s:p4LastArg =~ '^@\S\+$'
    let s:p4Arguments = substitute(s:p4Arguments, '@\S\+$',
          \ expand("%") . '&', '')
    let s:p4Arguments = expand("%") . s:p4LastArg
  endif

  if s:p4Command == 'help' 
    " Use simple window name for all the help commands.
    let s:p4WinName = s:helpWinName
  endif

  let err = s:PFImpl(a:outputType, s:p4CommandPrefix, 0, "")
  if err != 0
    return err
  endif

  if s:StartBufSetup(a:outputType)
    " If this command has a handler for the individual items, then enable the
    " item selection commands.
    if s:getCommandItemHandler(s:p4Command) != ""
      call s:SetupSelectItem()
    endif
    set ft=perforce

    call s:EndBufSetup(a:outputType)
  endif

  return 0
endfunction


function! s:LookupValue(key, type)
  exec 'return s:' . a:key . '_' . a:type
endfunction


" Generate raw output into a new window.
function! s:PFRaw(outputType, ...)
  exec g:makeArgumentString
  exec "call s:ParseOptions(" . argumentString . ")"

  call s:PFImpl(a:outputType, s:p4CommandPrefix, 0, "")
endfunction


" Handler for opened command.
function! s:OpenFile(outputType, fileName)
  if filereadable(a:fileName)
    if a:outputType == 0
      exec "split " . a:fileName
    else
      pclose
      exec "pedit " . a:fileName
    endif
  else
    call s:PPrint(a:outputType, a:fileName)
  endif
endfunction


function! s:getCommandHandler(command)
  let handler = 's:P' . substitute(a:command,'.','\U&','')
  if exists('*' . handler)
    return handler
  else
    return ""
  endif
endfunction


function! s:getCommandItemHandler(command)
  let handlerCmd = ""
  if exists("s:" . a:command . "ItemHandler")
    exec "let handlerCmd = s:" . a:command . "ItemHandler"
  elseif match(a:command, 'e\?s$') != -1
    let handlerCmd = substitute(a:command, 'e\?s$', '', '')
    let handlerCmd = 's:P' . substitute(handlerCmd,'.','\U&','')
  endif
  return handlerCmd
endfunction


function! s:OpenCurrentItem(outputType)
  let curItem = s:GetCurrentItem()
  if curItem != ""
    let commandHandler = s:getCommandItemHandler(b:p4Command)
    if commandHandler != ""
      exec 'call ' . commandHandler . '(' . a:outputType . ', ' .
            \ "'" . curItem . "'" . ')'
    endif
  endif
endfunction


function! s:GetCurrentItem()
  if exists("b:p4Command") && exists("s:" . b:p4Command . "Expr")
    exec "let expr = s:" . b:p4Command . "Expr"
    if expr == ""
      return
    endif
    exec "return " expr
  endif
  return ""
endfunction


function! s:DeleteCurrentItem()
  let curItem = s:GetCurrentItem()
  if curItem != ""
    let answer = confirm("Are you sure you want to delete " . curItem . "?",
          \ "&Yes\n&No", 2, "Question")
    if answer == 1
      let options = "'-d', '-f', "
      exec 'call ' . s:getCommandItemHandler(b:p4Command) . '(2, ' . options .
          \ "'" . curItem . "'" . ')'
      if v:shell_error == ""
        call s:PRefreshActivePane()
      endif
    endif
  endif
endfunction


function! s:FilelogDiff2(line1, line2)
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
      call s:PDiff2(0, file2, file1)
    endif
  endif
endfunction


function! s:FilelogSyncToCurrentItem()
  let curItem = s:GetCurrentItem()
  if curItem != ""
    let answer = confirm("Do you want to sync to: " . curItem . " ?",
          \ "&Yes\n&No", 2, "Question")
    if answer == 1
      call s:PSync(2, curItem)
    endif
  endif
endfunction


function! s:ChangesSubmitChangeList()
  let curItem = s:GetCurrentItem()
  if curItem != ""
    let answer = confirm("Do you want to submit change list: " . curItem .
          \ " ?", "&Yes\n&No", 2, "Question")
    if answer == 1
      exec 'call s:PSubmit(0, "-c", ' . "'" . curItem . "'" . ')'
    endif
  endif
endfunction



function! s:LabelsSyncClientToLabel()
  let curItem = s:GetCurrentItem()
  if curItem != ""
    let answer = confirm("Do you want to sync client to the label: " . curItem .
          \ " ?", "&Yes\n&No", 2, "Question")
    if answer == 1
      exec 'let err = s:PFIF(1, 1, 0, "sync", ' . "'//depot/...@" . curItem .
            \ "'" . ')'
    endif
  endif
endfunction


function! s:LabelsSyncLabelToClient()
  let curItem = s:GetCurrentItem()
  if curItem != ""
    let answer = confirm("Do you want to sync label: " . curItem .
          \ " to client " . s:p4Client . " ?", "&Yes\n&No", 2, "Question")
    if answer == 1
      exec 'let err = s:PFIF(1, 1, 0, "labelsync", "-l", ' . "'" . curItem .
            \ "'" . ')'
    endif
  endif
endfunction


function! s:FilelogDescribeChange()
  let changeNo = matchstr(getline("."), ' change \zs\d\+\ze ')
  if changeNo != ""
    exec "call s:PChange(1, " . changeNo . ")"
  endif
endfunction


function! s:AddDiffOptions(argString)
  let argumentString = a:argString
  if s:defaultDiffOptions != ""
    if match(argumentString, '\<diff\>') == -1
      let argumentString = s:defaultDiffOptions . ', ' . argumentString
    else
      let argumentString = substitute(argumentString, "\\<diff\\>'", "diff', " .
	    \ s:defaultDiffOptions, '')
    endif
  endif
  return argumentString
endfunction


function! s:SetupFileBrowse(outputType)
  set ft=perforce
  " For now, assume that a new window is created and we are in the new window.
  exec "setlocal includeexpr=" . s:myScriptId . "ConvertToLocalPath(v:fname)"

  silent! nunmap <buffer> D " No meaning for delete.
  silent! delcommand PItemDelete
  command! -buffer -nargs=0 PFileDiff :call <SID>PDiff(1,
	\ <SID>ConvertToLocalPath(<SID>GetCurrentDepotFile(line("."))))
  nnoremap <silent> <buffer> D :PFileDiff<CR>
  command! -buffer -nargs=0 PFileProps :call <SID>PFstat(0, '-C',
	\ <SID>ConvertToLocalPath(<SID>GetCurrentDepotFile(line("."))))
  nnoremap <silent> <buffer> P :PFileProps<CR>
  command! -buffer -nargs=0 PFileRevert :call <SID>PRevert(2,
	\ <SID>ConvertToLocalPath(<SID>GetCurrentDepotFile(line("."))))
  nnoremap <silent> <buffer> R :PFileRevert<CR>
endfunction


function! s:SetupSelectItem()
  nnoremap <buffer> <silent> D :PItemDelete<CR>
  nnoremap <buffer> <silent> O :PItemOpen<CR>
  nnoremap <buffer> <silent> <CR> :PItemDescribe<CR>
  nnoremap <buffer> <silent> <2-LeftMouse> :PItemDescribe<CR>
  command! -buffer -nargs=0 PItemDescribe :call <SID>OpenCurrentItem(1)
  command! -buffer -nargs=0 PItemOpen :call <SID>OpenCurrentItem(0)
  command! -buffer -nargs=0 PItemDelete :call <SID>DeleteCurrentItem()
endfunction


function! s:SetupSelectHelp()
  nnoremap <silent> <buffer> <CR> :call <SID>PHelp(5, expand("<cword>"))<CR>
  nnoremap <silent> <buffer> K :call <SID>PHelp(5, expand("<cword>"))<CR>
  nnoremap <silent> <buffer> <2-LeftMouse>
	\ :call <SID>PHelp(5, expand("<cword>"))<CR>
  nnoremap <silent> <buffer> <C-O> :call <SID>NavigateBack()<CR>
  nnoremap <silent> <buffer> <Tab> :call <SID>NavigateForward()<CR>
  call s:PFUnSetupBufAutoClean(s:helpWinName)
  call AddNotifyWindowClose(s:helpWinName, s:myScriptId . "RestoreWindows")
endfunction


function! s:RestoreWindows(dummy)
  echomsg "Perforce.RestoreWindows: " . a:dummy . " nwindows = " . NumberOfWindows()
  call RestoreWindowSettings2("PerforceHelp")
  call s:PFExecBufClean(s:helpWinName)
endfunction


function! s:NavigateBack()
  call s:Navigate('u')
endfunction


function! s:NavigateForward()
  call s:Navigate("\<C-R>")
endfunction


function! s:Navigate(key)
  let _modifiable = &l:modifiable
  setlocal modifiable
  normal mt
  exec "normal" a:key
  if line("'t")
    normal `t
  endif
  let &l:modifiable = _modifiable
endfunction

"
" Infrastructure.
"


" Assumes that the arguments are already parsed and are ready to be used in
"   the script variables.
" Low level interface with the p4 command.
" outputType:
"   0 - Execute p4 and place the output in a new window.
"   1 - Same as above, but use preview window.
"   2 - Execute p4 and show the output in a dialog for confirmation.
"   3 - Execute p4 and echo the output.
"   4 - Execute p4 but discard output.
"   5 - Same as 0, but try to reuse an existing window with the same name. 
"  20 - Execute p4 and if the output is less than s:maxLinesInDialog number of
"	lines, display a dialog (mode 2), otherwise display in a new window
"	(mode 0)
" commandType:
"   0 - Execute p4 using system() or its equivalent.
"   1 - Execute p4 as a filter for the current window contents. Use 
"         commandPrefix to restrict the filter range.
"   2 - Don't execute p4. The output is already passed in. 
" Returns non-zero error-code on failure. 
function! s:PFImpl(outputType, commandPrefix, commandType, output)
  let outputType = a:outputType
  let _report = &report
  set report=99999

  " Otherwise it may causes some trouble for cygwin BASH.
  let fullCmd = a:commandPrefix . s:p4CmdPath . ' ' . s:defaultOptions . ' ' .
        \ s:MakeOptions()
  let g:p4FullCmd = fullCmd " Debug.
  " save the name of the current file.
  let p4CurFileName = expand("%")

  let error = 0
  if a:commandType == 0
    " If it placing the output in a new window, then we shouldn't use system()
    "   for efficiency reasons.
    if outputType != 0 && outputType != 1 && outputType != 5
      " Assume the shellredir is set correctly to capture the error messages.
      let output = system(fullCmd)

      let error = s:CheckShellError(output)
    else
      let output = ""
    endif
  elseif a:commandType == 1
    silent! exec fullCmd
    let output = ""

    let error = s:CheckShellError(output)
  elseif a:commandType == 2
    let output = a:output
  endif

  if error == 0
    if outputType == 20
      let nLines = strlen(substitute(output, "[^\n]", "", "g"))
      if nLines > s:maxLinesInDialog
	let outputType = 0
      else
	let outputType = 2
      endif
    endif

    let newWindowCreated = 0
    " If the output has to be shown in a dialog, bringup a dialog with the
    "   output, otherwise show it in a new window.
    if outputType == 0 || outputType == 5 
      if outputType == 5
	" If there is a window with this buffer, then we will just move cursor
	"   into it.
	let winnr = FindWindowForBuffer(s:p4WinName, 1)
	if winnr != -1 " If there is a window that is already existing.
	  call MoveCursorToWindow(winnr)
	  normal mt
	else
	  " If there is no window already existing, then let it be created, just
	  " like outputType == 0
	  let outputType = 0
	endif
      endif

      if outputType == 0
	split
	let w:p4CurFileName = p4CurFileName

	exec ":edit " . s:p4WinName
      endif

      setlocal modifiable
      1,$d " Just in case.
      if a:commandType == 0 && output == ""
	exec ".!" . fullCmd
	let error = s:CheckShellError(output)
      else
	put! =output
      endif
      call s:PFSetupBuf(s:p4WinName)
      " Even if outputType==5, and we found an existing window for it, we
      "	  still want set certain variables.
      let newWindowCreated = 1
    elseif outputType == 1
      pclose
      exec ":pedit " . s:p4WinName
      wincmd p
      let w:p4CurFileName = p4CurFileName

      setlocal modifiable
      1,$d " Just in case.
      if a:commandType == 0 && output == ""
        exec ".!" . fullCmd
        let error = s:CheckShellError(output)
      else
        put! =output
      endif
      call s:PFSetupBuf(s:p4WinName)
      let newWindowCreated = 1
    elseif outputType == 2
      call confirm(output, "OK", 1, "Info")
    elseif outputType == 3
      echo output
    elseif outputType == 4
      " Do nothing.
    endif
    if newWindowCreated
      let b:p4Command = s:p4Command
      let b:p4FullCmd = fullCmd
      if outputType == 1
        wincmd p
      endif
    endif
  endif
  let &report = _report
  return error
endfunction


function! s:CheckShellError(output)
  let output = a:output
  if v:shell_error != 0
    let output = "There was an error executing external p4 command.\n" . output
    if output == ""
      let output = output . "\nSet the shellredir option correctly to be able" .
            \ "to capture the error message."
    endif
    call confirm(output, "OK", 1, "Error")
  endif
  return v:shell_error
endfunction

" Parses the arguments into 4 parts, "options to p4", "p4 command",
" "options to p4 command", "actual arguments". Also generates the window name.
function! s:ParseOptions(...)
  call s:ResetP4Vars()
  let s:p4WinName = "P4"

  if a:0 == 0
    return
  endif

  let i = 1
  while i <= a:0
    exec "let curArg = a:" . i
    let winArg = curArg
    if match(curArg, '^-') < 0
      if s:p4Command == "" && MvContainsElement(s:p4KnownCmds, ',', curArg)
        let s:p4Command = curArg
      else
        " Don't clean the filenames that are depot specs.
        if match(winArg, '^//depot/') == -1
          let winArg = CleanupFileName(winArg)
        endif
        let winArg = escape(winArg, '#')

        if s:p4Command == ""
          let s:p4Options = s:p4Options . ' ' . curArg
        else
          " Most probably a filename, cook it.
          let curArg = winArg
          if match(curArg, '^//') == 0 && match(curArg, '^//depot/') == -1
            let curArg = strpart(curArg, 1, strlen(curArg) - 1)
          endif
          let curArg = escape(curArg, " \t") " Escape white space.
          let curArg = escape(curArg, "\\") " For bash???
          let s:p4LastArg = curArg

          let s:p4Arguments = s:p4Arguments . ' ' . curArg
        endif
      endif
    else
      if s:p4Command == ""
        let s:p4Options = s:p4Options . ' ' . curArg
      else
        let s:p4Arguments = s:p4Arguments . ' ' . curArg
      endif
    endif
    " HACK: Work-around for some weird handling of buffer names that end with
    "   "...". The autocommand doesn't get triggered to clean it up.
    if match(winArg, '\.\.\.$') != -1
      let winArg = winArg . '/'
    endif
    let winArg = escape(winArg, ' ')
    let s:p4WinName = s:p4WinName . '\ ' . winArg
    let i = i + 1
  endwhile
endfunction


" Generates a command string as the user typed, using the script variables.
function! s:MakeOptions()
  return s:p4Options . ' ' . s:p4Command . ' ' . s:p4Arguments
endfunction


function! s:GuessFileTypeForCurrentWindow()
  let fileExt = s:GuessFileType(w:p4CurFileName)
  if fileExt == ""
    let fileExt = s:GuessFileType(expand("%"))
  endif
  return fileExt
endfunction


function! s:GuessFileType(name)
  let fileExt = fnamemodify(a:name, ":e")
  return matchstr(fileExt, '\w\+')
endfunction


function! s:ConvertToLocalPath(depotName)
  let fileName = a:depotName
  if match(a:depotName, '^//depot/') == 0 ||
        \ match(a:depotName, '^//'. s:p4Client . '/') == 0
    let fileName = s:codelineRoot . substitute(fileName, '^//[^/]\+', '', '')
  endif
  let fileName = substitute(fileName, '#[^#]\+$', '', '')
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
  let root=CleanupFileName(s:codelineRoot) . "/"
  while i <= a:0
    exec "let fileName = a:" . i
    let fileName=CleanupFileName(fnamemodify(fileName, ":p"))
    " We have only one slash after the cleanup is done.
    if match(fileName, '^/depot/') == 0 ||
          \ match(fileName, '^/'. s:p4Client . '/') == 0
      let fileName = root . substitute(fileName, '^//[^/]\+/', '', '')
    elseif match(fileName, '^/') == -1
      if match(fileName, '^[a-zA-Z]:') < 0 && !OnMS()
        let fileName=getcwd() . "/" . fileName
      endif
    endif
    " One final cleanup, just in case.
    let fileName=CleanupFileName(fileName)

    let altFiles = MvAddElement(altFiles, ';',
          \ substitute(fileName, root . '[^/]\+', root . altCodeLine, ""))
    let i = i + 1
  endwhile
  " Remove the last separator, so the the list is ready to be used for 1
  " element case.
  let altFiles = strpart(altFiles, 0, strlen(altFiles) - 1) 
  return altFiles
endfunction


" This better take the line as argument, but I need the context of current
"   buffer contents anyway...
function! s:GetCurrentDepotFile(lineNo)
  " Local submissions.
  let fileName = ""
  let line = getline(a:lineNo)
  if match(line, '//depot/.*\(#\d\+\)\?') != -1 ||
        \ match(line, '^//'. s:p4Client . '/.*\(#\d\+\)\?') != -1
    let fileName = matchstr(line, '//[^/]\+/[^#]*\(#\d\+\)\?')
  elseif match(line, '\.\.\. #\d\+ .*') != -1
    let fileVer = matchstr(line, '\d\+')
    call SaveHardPosition('Perforce')
    exec a:lineNo
    if search('//depot/', 'bW') == -1
      return ""
    endif
    let fileName = substitute(s:GetCurrentDepotFile(line(".")), '#\d\+$', '',
          \ '')
    let fileName = fileName . "#" . fileVer
    call RestoreHardPosition('Perforce')
  " Branches, integrations etc.
  endif
  return fileName
endfunction


" Must be followed by a call to s:EndBufSetup()
function! s:StartBufSetup(outputType)
  " If this outputType created a new window, then only do setup.
  if a:outputType == 0 || a:outputType == 1 || a:outputType == 5
    if a:outputType == 1
      wincmd p
    endif

    return 1
  else
    return 0
  endif
endfunction


function! s:EndBufSetup(outputType)
  if a:outputType == 1
    wincmd p
  endif
endfunction


function! s:PFSetupBuf(bufName)
" call input("PFfilelogSetup")
  call SetupScratchBuffer()
  setlocal nomodified
  setlocal nomodifiable
  call s:PFSetupBufAutoClean(a:bufName)
endfunction


" Arrange an autocommand such that the buffer is automatically deleted when the
"  window is quit. Delete the autocommand itself when done.
function! s:PFSetupBufAutoClean(bufName)
  aug Perforce
  " Just in case the autocommands are leaking, this will curtail the leak a
  "   little bit.
  exec "au! BufWinLeave " . a:bufName
  exec "au BufWinLeave " . a:bufName .
        \ " :call <SID>PFExecBufClean('" . a:bufName . "')"
  aug END
endfunction


function! s:PFUnSetupBufAutoClean(bufName)
  aug Perforce
  exec "au! BufWinLeave " . a:bufName
  aug END
endfunction


" Find and delete the buffer. Delete the autocommand itself after that.
function! s:PFExecBufClean(bufName)
  let bufNo = FindBufferForName(a:bufName)
  if bufNo == -1
    " Should not happen
    echoerr "perforce.vim: Internal ERROR detected. Please report this message."
    return
  endif
  let _report=&report
  set report=99999
  exec "silent! bwipeout! ". bufNo
  let &report=_report
  aug Perforce
  exec "au! BufWinLeave " . a:bufName
  aug END
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


function! s:PRefreshActivePane()
  if exists("b:p4FullCmd")
    let _modifiable = &l:modifiable
    setlocal modifiable
    exec "1,$!" . b:p4FullCmd
    let &l:modifiable=_modifiable
  endif
endfunction
" vim6:fdm=marker
