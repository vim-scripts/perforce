" perforceutils.vim: Additional utilities for for perforce plugin.
" Author: Hari Krishna (hari_vim at yahoo dot com)
" Last Change: 19-Apr-2004 @ 19:04
" Created:     19-Apr-2004
" Requires:    Vim-6.2
" Version:     1.0.0
" Licence: This program is free software; you can redistribute it and/or
"          modify it under the terms of the GNU General Public License.
"          See http://www.gnu.org/copyleft/gpl.txt 

" Make sure line-continuations won't cause any problem. This will be restored
"   at the end
let s:save_cpo = &cpo
set cpo&vim

" CAUTION: Don't assume the existence of plugin/perforce.vim (or any other
"   plugins) at the time this file is sourced.

" DiffLink {{{

command! -nargs=0 PFDiffLink :call <SID>DiffOpenSrc(0)
command! -nargs=0 PFDiffPLink :call <SID>DiffOpenSrc(1)
aug P4DiffLink
  au!
  au FileType * :if expand('<amatch>') ==# 'diff' && exists('b:p4OrgFileName') |
        \   call <SID>SetupDiffLink() |
        \ endif
aug END
 
" Open the source line for the current line from the diff.
function! s:DiffOpenSrc(preview) " {{{
  let s:EMPTY_STR = PFEval('s:EMPTY_STR')
  if PFEval('s:GetCurrentItem()') !~# s:EMPTY_STR
    PItemOpen
  endif
  call SaveHardPosition('DiffOpenSrc')
  " Search backwards to find the header for this diff (could contain two
  " depot files or one depot file with or without a local file).
  let filePat = '\zs[^#]\+\%(#\d\+\)\=\ze\%( ([^)]\+)\)\='
  if search('^==== '.filePat.'\%( - '.filePat.'\)\= ====', 'bW')
    let firstFile = matchstr(getline('.'), '^==== \zs'.filePat.
          \ '\%( - \| ====\)')
    let secondFile = matchstr(getline('.'), ' - '.filePat.' ====',
          \ strlen(firstFile)+5)
    let foundHeader = 1

  " GNU diff header.
  elseif search('^--- '.filePat.'.*\n\_^+++ '.filePat, 'bW')
    let firstFile = matchstr(getline(line('.')-1), '^--- \zs.\{-}\ze\t')
    let secondFile = matchstr(getline('.'), '^+++ \zs.\{-}\ze\t')
    let foundHeader = 1
  else
    let foundHeader = 0
  endif
  if foundHeader
    call RestoreHardPosition('DiffOpenSrc')
    if firstFile =~# s:EMPTY_STR
      return
    elseif secondFile =~# s:EMPTY_STR
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
      if getline('.') =~# '^>'
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
      if getline('.') =~# '^-'
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
      if getline('.') =~# '^-'
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
        if offOffset > 0
          silent! undo
          call RestoreHardPosition('DiffOpenSrc')
        endif
        let offset = line('.') - segStLine - 1 - offOffset
      finally
        let &l:modifiable = _ma
      endtry
    endif

    if context ==# 'depot' && firstFile =~# s:EMPTY_STR
      " Assume previous revision as the "before" file if none specified.
      if PFCall('s:IsDepotPath', secondFile) && secondFile =~# '#\d\+'
        let depotRev = s:GetFileRevision(secondFile)
        if depotRev == ''
          return
        endif
        let firstFile = substitute(secondFile, '#\d\+', '', '').'#'.(depotRev-1)
      else
        return
      endif
    endif
    if context ==# 'local'
      let file = secondFile
    else
      let file = firstFile
    endif
    " If the path refers to a depot file, check if the local file is currently
    " open in Vim and if so has the same version number as the depot file.
    if context ==# 'local' && PFCall('s:IsDepotPath', file)
      let localFile = PFCall('s:ConvertToLocalPath', file)
      let bufNr = bufnr(localFile) + 0
      if bufNr != -1
        let haveRev = getbufvar(bufNr, 'p4HaveRev')
        let depotRev = s:GetFileRevision(file)
        if haveRev == depotRev
          let file = localFile
        endif
      " else " We could also try to run 'fstat' command and open up the file.
      endif
    endif
    if PFCall('s:IsDepotPath', file)
      call PFCall('s:printHdlr', 0, a:preview, file)
      let offset = offset + 1 " For print header.
    else
      call PFCall('s:OpenFile', 1, a:preview, CleanupFileName(file))
    endif
    if PFEval('s:errCode') == 0
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

function! s:SetupDiffLink()
  command! -buffer -nargs=0 PDiffLink :PFDiffLink
  command! -buffer -nargs=0 PDiffPLink :PFDiffPLink
  nnoremap <buffer> <silent> O :PDiffLink<CR>
  nnoremap <buffer> <silent> <CR> :PDiffPLink<CR>
endfunction

function! s:GetFileRevision(depotPath)
  let rev = matchstr(a:depotPath, '#\zs\d\+$')
  return (rev !~# s:EMPTY_STR) ? rev + 0 : ''
endfunction

" DiffLink }}}

" ShowConflicts {{{
command! PFShowConflicts :call <SID>ShowConflicts()

function! s:ShowConflicts()
  let _splitright = &splitright
  set splitright
  try
    let curFile = expand('%:p:t')
    "exec 'split' curFile.'.Original'
    exec 'edit' curFile.'.Original'
    silent! exec 'read' curFile
    silent! 1delete _
    call PFCall('s:SilentSub', '^==== THEIRS \_.\{-}\%(^<<<<$\)\@=', '%s///e')
    call PFCall('s:SilentDel', '\%(^>>>> ORIGINAL \|^==== THEIRS\|^==== YOURS \|^<<<<$\)')
    call SetupScratchBuffer()
    setlocal nomodifiable
    diffthis

    exec 'vsplit' curFile.'.Theirs'
    silent! exec 'read' curFile
    1delete _
    call PFCall('s:SilentSub', '^>>>> ORIGINAL \_.\{-}\%(^==== THEIRS \)\@=', '%s///e')
    call PFCall('s:SilentSub', '^==== YOURS \_.\{-}\%(^<<<<$\)\@=', '%s///e')
    call PFCall('s:SilentDel', '\%(^>>>> ORIGINAL \|^==== THEIRS\|^==== YOURS \|^<<<<$\)')
    call SetupScratchBuffer()
    setlocal nomodifiable
    diffthis

    exec 'vsplit' curFile.'.Yours'
    silent! exec 'read' curFile
    1delete _
    call PFCall('s:SilentSub', '^>>>> ORIGINAL \_.\{-}\%(^==== YOURS \)\@=', '%s///e')
    call PFCall('s:SilentDel', '\%(^>>>> ORIGINAL \|^==== THEIRS\|^==== YOURS \|^<<<<$\)')
    call SetupScratchBuffer()
    setlocal buftype=
    setlocal nomodified
    call PFCall('s:PFSetupBufAutoCommand', expand('%'), 'BufWriteCmd',
          \ ':if confirm("Do you want to accept the changes in \"".expand("%")'.
          \              '."\"?", "&Yes\n&No", 2, "Question") == 1 | w! '.
          \              curFile . ' | '.
          \   'endif')
    diffthis
  finally
    let &splitright = _splitright
  endtry
endfunction
" ShowConflicts }}}

" Restore cpo.
let &cpo = s:save_cpo
unlet s:save_cpo

" vim6:fdm=marker et sw=2
