" perforcebugrep.vim: Generate perforcebugrep.txt for perforce plugin.
" Author: Hari Krishna (hari_vim at yahoo dot com)
" Last Change: 11-Dec-2003 @ 19:34
" Created:     07-Nov-2003
" Requires:    Vim-6.2, perforce.vim(3.0), multvals.vim(3.4)
" Version:     1.0.2
" Licence: This program is free software; you can redistribute it and/or
"          modify it under the terms of the GNU General Public License.
"          See http://www.gnu.org/copyleft/gpl.txt 

if !exists("loaded_perforce")
  runtime plugin/perforce.vim
endif
if !exists("loaded_perforce") || loaded_perforce != 300
  echomsg "perforcebugrep: You need a newer version of perforce.vim plugin"
  finish
endif
if !exists("loaded_multvals")
  runtime plugin/multvals.vim
endif
if !exists("loaded_multvals") || loaded_multvals < 304
  echomsg "perforcebugrep: You need a newer version of multvals.vim plugin"
  finish
endif

" Make sure line-continuations won't cause any problem. This will be restored
"   at the end
let s:save_cpo = &cpo
set cpo&vim

" Based on $VIM/bugreport.vim
let _more = &more
try
  set nomore
  call delete('perforcebugrep.txt')
  if has("unix")
    !echo "uname -a" >perforcebugrep.txt
    !uname -a >>perforcebugrep.txt
  endif

  redir >>perforcebugrep.txt
  version

  echo "Perforce plugin version: " . loaded_perforce
  echo "Multvals plugin version: " . loaded_multvals
  echo "Genutils plugin version: " . loaded_genutils

  echo "--- Perforce Plugin Settings ---"
  call MvIterCreate(PFGet('s:settings'), ',', 'PFDumpSettings')
  while MvIterHasNext('PFDumpSettings')
    let nextSetting = MvIterNext('PFDumpSettings')
    let value = PFCall('s:GetSettingValue', nextSetting)
    echo nextSetting.': '.value
  endwhile
  call MvIterDestroy('PFDumpSettings')
  echo "s:p4Contexts: " . PFGet('s:p4Contexts')
  echo "s:p4Depot: " . PFGet('s:p4Depot')
  echo "s:defaultOptions: " . PFGet('s:defaultOptions')
  echo "s:ignoreDefPattern: " . PFGet('s:ignoreDefPattern')
  echo "s:ignoreUsrPattern: " . PFGet('s:ignoreUsrPattern')
  echo "s:p4HideOnBufHidden: " . PFGet('s:p4HideOnBufHidden')
  echo "s:curClientExpr: " . PFGet('s:curClientExpr')
  echo "s:curUserExpr: " . PFGet('s:curUserExpr')
  echo "s:curPortExpr: " . PFGet('s:curPortExpr')
  echo "s:curPasswdExpr: " . PFGet('s:curPasswdExpr')
  echo "s:curDirExpr: " . PFGet('s:curDirExpr')
  echo "s:curPreset: " . PFGet('s:curPreset')

  echo "--- Current Buffer ---"
  echo "Current buffer: " . expand('%')
  echo "Current directory: " . getcwd()
  let tempDir = PFGet('s:tempDir')
  if isdirectory(tempDir)
    echo 'temp directory "' . tempDir . '" exists'
  else
    echo 'temp directory "' . tempDir . '" does NOT exist'
  endif
  if exists('b:p4OrgFileName')
    echo 'b:p4OrgFileName: ' . b:p4OrgFileName
  endif
  if exists('b:p4Command')
    echo 'b:p4Command: ' . b:p4Command
  endif
  if exists('b:p4Options')
    echo 'b:p4Options: ' . b:p4Options
  endif
  if exists('b:p4FullCmd')
    echo 'b:p4FullCmd: '. b:p4FullCmd
  endif
  if exists('g:p4FullCmd')
    echo 'g:p4FullCmd: '. g:p4FullCmd
  endif
  setlocal

  echo "--- Perforce Settings ---"
  echo PFCall('s:PFIF', '1', '4', 'info')

  set all
finally
  redir END
  let &more = _more
  sp perforcebugrep.txt
endtry

" Restore cpo.
let &cpo = s:save_cpo
unlet s:save_cpo

" vim6:fdm=marker et sw=2
