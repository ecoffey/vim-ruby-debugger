" *** Public interface ***

let RubyDebugger = { 'commands': {}, 'variables': {}, 'settings': {} }

function! RubyDebugger.start() dict
  let rdebug = 'rdebug-ide -p ' . s:rdebug_port . ' -- script/server &'
  let debugger = 'ruby ' . expand(s:runtime_dir . "/bin/ruby_debugger.rb") . ' ' . s:rdebug_port . ' ' . s:debugger_port . ' ' . v:progname . ' ' . v:servername . ' "' . s:tmp_file . '" &'
  call system(rdebug)
  exe 'sleep 2'
  call system(debugger)
endfunction


function! RubyDebugger.receive_command() dict
  let cmd = join(readfile(s:tmp_file), "")
  " Clear command line
  if !empty(cmd)
    if match(cmd, '<breakpoint ') != -1
      call g:RubyDebugger.commands.jump_to_breakpoint(cmd)
    elseif match(cmd, '<breakpointAdded ') != -1
      call g:RubyDebugger.commands.set_breakpoint(cmd)
    elseif match(cmd, '<variables>') != -1
      call g:RubyDebugger.commands.set_variables(cmd)
    endif
  endif
endfunction


function! RubyDebugger.open_variables() dict
"  if g:RubyDebugger.variables == {}
"    echo "You are not in the running program"
"  else
    call s:variables_window.open()
"  endif
endfunction


function! RubyDebugger.set_breakpoint() dict
  let line = line(".")
  let file = s:get_filename()
  let message = 'break ' . file . ':' . line
  call s:send_message_to_debugger(message)
endfunction


" *** End of public interface




" *** RubyDebugger Commands *** 


" <breakpoint file="test.rb" line="1" threadId="1" />
function! RubyDebugger.commands.jump_to_breakpoint(cmd) dict
  let attrs = s:get_tag_attributes(a:cmd) 
  call s:jump_to_file(attrs.file, attrs.line)
  call s:send_message_to_debugger('var local')
endfunction


" <breakpointAdded no="1" location="test.rb:2" />
function! RubyDebugger.commands.set_breakpoint(cmd)
  let attrs = s:get_tag_attributes(a:cmd)
  let file_match = matchlist(attrs.location, '\(.*\):\(.*\)')
  exe ":sign place " . attrs.no . " line=" . file_match[2] . " name=breakpoint file=" . file_match[1]
endfunction


" <variables>
"   <variable name="array" kind="local" value="Array (2 element(s))" type="Array" hasChildren="true" objectId="-0x2418a904"/>
" </variables>
function! RubyDebugger.commands.set_variables(cmd)
  let tags = s:get_tags(a:cmd)
  let list_of_variables = []
  for tag in tags
    let attrs = s:get_tag_attributes(tag)
    let variable = s:Var.new(attrs)
    call add(list_of_variables, variable)
  endfor
  if g:RubyDebugger.variables == {}
    let g:RubyDebugger.variables = s:VarParent.new({'hasChildren': 'true'})
    let g:RubyDebugger.variables.is_open = 1
    let g:RubyDebugger.variables.children = []
  endif
  if has_key(g:RubyDebugger, 'current_variable')
    let variable = g:RubyDebugger.variables.find_variable({'name': g:RubyDebugger.current_variable})
    unlet g:RubyDebugger.current_variable
    if variable != {}
      call variable.add_childs(list_of_variables)
      let s:variables_window.data = g:RubyDebugger.variables
      call s:variables_window.open()
    else
      return 0
    endif
  else
    if g:RubyDebugger.variables.children == []
      call g:RubyDebugger.variables.add_childs(list_of_variables)
      let s:variables_window.data = g:RubyDebugger.variables
    endif
  endif
endfunction

" *** End of debugger Commands ***




" *** Abstract Class for creating window. Should be inherited. ***

let s:Window = {} 
let s:Window['next_buffer_number'] = 1 
let s:Window['position'] = 'botright'
let s:Window['size'] = 10


function! s:Window.new(name, title, data) dict
  let new_variable = copy(self)
  let new_variable.name = a:name
  let new_variable.title = a:title
  let new_variable.data = a:data
  return new_variable
endfunction


function! s:Window.clear() dict
  silent 1,$delete _
endfunction


function! s:Window.close() dict
  if !self.is_open()
    throw "RubyDebug: Window " . self.name . " is not open"
  endif

  if winnr("$") != 1
    call self.focus()
    close
    exe "wincmd p"
  else
    :q
  endif
endfunction


function! s:Window.get_number() dict
  if self._exist_for_tab()
    return bufwinnr(self._buf_name())
  else
    return -1
  endif
endfunction


function! s:Window.display()
  call self.focus()
  setlocal modifiable

  let current_line = line(".")
  let current_column = col(".")
  let top_line = line("w0")

  call self.clear()

  call setline(top_line, self.title)
  call cursor(top_line + 1, current_column)

  call self._insert_data()
  call self._restore_view(top_line, current_line, current_column)

  setlocal nomodifiable
endfunction


function! s:Window.focus() dict
  exe self.get_number() . " wincmd w"
endfunction


function! s:Window.is_open() dict
    return self.get_number() != -1
endfunction


function! s:Window.open() dict
    if !self.is_open()
      " create the variables tree window
      silent exec self.position . ' ' . self.size . ' new'

      if !self._exist_for_tab()
        call self._set_buf_name(self._next_buffer_name())
        silent! exec "edit " . self._buf_name()
        " This function does not exist in Window class and should be declared in
        " childrens
        call self.bind_mappings()
      else
        silent! exec "buffer " . self._buf_name()
      endif

      " set buffer options
      setlocal winfixwidth
      setlocal noswapfile
      setlocal buftype=nofile
      setlocal nowrap
      setlocal foldcolumn=0
      setlocal nobuflisted
      setlocal nospell
      iabc <buffer>
      setlocal cursorline
      setfiletype ruby_debugger_window
    endif
    call self.display()
endfunction


function! s:Window.toggle() dict
  if self._exist_for_tab() && self.is_open()
    call self.close()
  else
    call self.open()
  end
endfunction


function! s:Window._buf_name() dict
  return t:window_{self.name}_buf_name
endfunction


function! s:Window._exist_for_tab() dict
  return exists("t:window_" . self.name . "_buf_name") 
endfunction


function! s:Window._insert_data() dict
  let old_p = @p
  let @p = self.data.render()
  silent put p
  let @p = old_p
endfunction


function! s:Window._next_buffer_name() dict
  let name = self.name . s:Window.next_buffer_number
  let s:Window.next_buffer_number += 1
  return name
endfunction


function! s:Window._restore_view(top_line, current_line, current_column) dict
 "restore the view
  let old_scrolloff=&scrolloff
  let &scrolloff=0
  call cursor(a:top_line, 1)
  normal! zt
  call cursor(a:current_line, a:current_column)
  let &scrolloff = old_scrolloff 
endfunction


function! s:Window._set_buf_name(name) dict
  let t:window_{self.name}_buf_name = a:name
endfunction









" Inherits VarParent from VarChild
let s:WindowVariables = copy(s:Window)

function! s:WindowVariables.bind_mappings()
  nnoremap <buffer> <2-leftmouse> :call <SID>window_variables_activate_node()<cr>
  nnoremap <buffer> o :call <SID>window_variables_activate_node()<cr>"
endfunction


" TODO: Is there some way to call s:WindowVariables.activate_node from mapping
" command?
function! s:window_variables_activate_node()
  let variable = s:Var.get_selected()
  if variable != {} && variable.type == "VarParent"
    if variable.is_open
      call variable.close()
    else
      call variable.open()
    endif
  endif
endfunction




let s:Var = {}

" This is a proxy method for creating new variable
function! s:Var.new(attrs)
  if has_key(a:attrs, 'hasChildren') && a:attrs['hasChildren'] == 'true'
    return s:VarParent.new(a:attrs)
  else
    return s:VarChild.new(a:attrs)
  end
endfunction


function! s:Var.get_selected()
  let line = getline(".") 
  let match = matchlist(line, '[| ]\+[+\-\~]\+\(.\{-}\)\s') 
  let name = get(match, 1)
  let variable = g:RubyDebugger.variables.find_variable({'name' : name})
  let g:RubyDebugger.current_variable = variable
  return variable
endfunction


" *** Start of variables ***
let s:VarChild = {}


" Initializes new variable without childs
function! s:VarChild.new(attrs)
  let new_variable = copy(self)
  let new_variable.attributes = a:attrs
  let new_variable.parent = {}
  let new_variable.type = "VarChild"
  return new_variable
endfunction


" Renders data of the variable
function! s:VarChild.render()
  return self._render(0, 0, [], len(self.parent.children) ==# 1)
endfunction


function! s:VarChild._render(depth, draw_text, vertical_map, is_last_child)
  let output = ""
  if a:draw_text ==# 1
    let tree_parts = ''

    "get all the leading spaces and vertical tree parts for this line
    if a:depth > 1
      for j in a:vertical_map[0:-2]
        if j ==# 1
          let tree_parts = tree_parts . '| '
        else
          let tree_parts = tree_parts . '  '
        endif
      endfor
    endif
    
    "get the last vertical tree part for this line which will be different
    "if this node is the last child of its parent
    if a:is_last_child
      let tree_parts = tree_parts . '`'
    else
      let tree_parts = tree_parts . '|'
    endif

    "smack the appropriate dir/file symbol on the line before the file/dir
    "name itself
    if self.is_parent()
      if self.is_open
        let tree_parts = tree_parts . '~'
      else
        let tree_parts = tree_parts . '+'
      endif
    else
      let tree_parts = tree_parts . '-'
    endif
    let line = tree_parts . self.to_s()
    let output = output . line . "\n"

  endif

  if self.is_parent() && self.is_open

    if len(self.children) > 0

      "draw all the nodes children except the last
      let last_index = len(self.children) - 1
      if last_index > 0
        for i in self.children[0:last_index - 1]
          let output = output . i._render(a:depth + 1, 1, add(copy(a:vertical_map), 1), 0)
        endfor
      endif

      "draw the last child, indicating that it IS the last
      let output = output . self.children[last_index]._render(a:depth + 1, 1, add(copy(a:vertical_map), 0), 1)

    endif
  endif

  return output

endfunction


function! s:VarChild.open()
  return 0
endfunction


function! s:VarChild.close()
  return 0
endfunction


function! s:VarChild.is_parent()
  return has_key(self.attributes, 'hasChildren') && get(self.attributes, 'hasChildren') ==# 'true'
endfunction


function! s:VarChild.to_s()
  return get(self.attributes, "name", "undefined") . ' ' . get(self.attributes, "type", "undefined") . ' ' . get(self.attributes, "value", "undefined")
endfunction


function! s:VarChild.find_variable(attrs)
  if self._match_attributes(a:attrs)
    return self
  else
    return {}
  endif
endfunction


function! s:VarChild._match_attributes(attrs)
  let conditions = 1
  for attr in keys(a:attrs)
    let conditions = conditions && (has_key(self.attributes, attr) && self.attributes[attr] == a:attrs[attr]) 
  endfor
  
  return conditions
endfunction




" Inherits VarParent from VarChild
let s:VarParent = copy(s:VarChild)


" Renders data of the variable
function! s:VarParent.render()
  return self._render(0, 0, [], len(self.children) ==# 1)
endfunction



" Initializes new variable with childs
function! s:VarParent.new(attrs)
  if !has_key(a:attrs, 'hasChildren') || a:attrs['hasChildren'] != 'true'
    throw "RubyDebug: VarParent must be initialized with hasChildren = true"
  endif
  let new_variable = copy(self)
  let new_variable.attributes = a:attrs
  let new_variable.parent = {}
  let new_variable.is_open = 0
  let new_variable.children = []
  let new_variable.type = "VarParent"
  return new_variable
endfunction


function! s:VarParent.open()
  let self.is_open = 1
  call self._init_children()
  return 0
endfunction


function! s:VarParent.close()
  let self.is_open = 0
  call g:RubyDebugger.variables.update()
  return 0
endfunction



function! s:VarParent._init_children()
  "remove all the current child nodes
  let self.children = []
  if !has_key(self.attributes, "name")
    return 0
  endif

  let g:RubyDebugger.current_variable = self.attributes.name
  if has_key(self.attributes, 'objectId')
    call s:send_message_to_debugger('var instance ' . self.attributes.objectId)
  endif

endfunction


function! s:VarParent.add_childs(childs)
  if type(a:childs) == type([])
    for child in a:childs
      let child.parent = self
    endfor
    call extend(self.children, a:childs)
  else
    let a:childs.parent = self
    call add(self.children, a:childs)
  end
endfunction


function! s:VarParent.find_variable(attrs)
  if self._match_attributes(a:attrs)
    return self
  else
    for child in self.children
      let result = child.find_variable(a:attrs)
      if result != {}
        return result
      endif
    endfor
  endif
  return {}
endfunction


function! s:get_tags(cmd)
  let tags = []
  let cmd = a:cmd
  let inner_tags_match = matchlist(cmd, '^<.\{-}>\(.\{-}\)<\/.\{-}>$')
  if empty(inner_tags_match) == 0
    let pattern = '<.\{-}\/>' 
    let inner_tags = inner_tags_match[1]
    let tagmatch = matchlist(inner_tags, pattern)
    while empty(tagmatch) == 0
      call add(tags, tagmatch[0])
      let inner_tags = substitute(inner_tags, tagmatch[0], '', '')
      let tagmatch = matchlist(inner_tags, pattern)
    endwhile
  endif
  return tags
endfunction


function! s:get_tag_attributes(cmd)
  let attributes = {}
  let cmd = a:cmd
  let pattern = '\(\w\+\)="\(.\{-}\)"'
  let attrmatch = matchlist(cmd, pattern) 
  while empty(attrmatch) == 0
    let attributes[attrmatch[1]] = attrmatch[2]
    let cmd = substitute(cmd, attrmatch[0], '', '')
    let attrmatch = matchlist(cmd, pattern) 
  endwhile
  return attributes
endfunction


function! s:get_filename()
  return bufname("%")
endfunction


function! s:send_message_to_debugger(message)
  call system("ruby -e \"require 'socket'; a = TCPSocket.open('localhost', 39768); a.puts('" . a:message . "'); a.close\"")
endfunction


function! s:jump_to_file(file, line)
  " If no buffer with this file has been loaded, create new one
  if !bufexists(bufname(a:file))
     exe ":e! " . l:fileName
  endif

  let l:winNr = bufwinnr(bufnr(a:file))
  if l:winNr != -1
     exe l:winNr . "wincmd w"
  endif

  " open buffer of a:file
  if bufname(a:file) != bufname("%")
     exe ":buffer " . bufnr(a:file)
  endif

  " jump to line
  exe ":" . a:line
  normal z.
  if foldlevel(a:line) != 0
     normal zo
  endif

  return bufname(a:file)

endfunction




map <Leader>b  :call RubyDebugger.set_breakpoint()<CR>
map <Leader>v  :call RubyDebugger.open_variables()<CR>
command! Rdebugger :call RubyDebugger.start() 

" if exists("g:loaded_ruby_debugger")
"     finish
" endif
" if v:version < 700
"     echoerr "RubyDebugger: This plugin requires Vim >= 7."
"     finish
" endif
" let g:loaded_ruby_debugger = 1

let s:rdebug_port = 39767
let s:debugger_port = 39768
let s:runtime_dir = split(&runtimepath, ',')[0]
let s:tmp_file = s:runtime_dir . '/tmp/ruby_debugger'

let s:variables_window = s:WindowVariables.new("variables", "Variables_Window", g:RubyDebugger.variables)

let RubyDebugger.settings.variables_win_position = 'botright'
let RubyDebugger.settings.variables_win_size = 10


" Init breakpoing signs
hi breakpoint  term=NONE    cterm=NONE    gui=NONE
sign define breakpoint  linehl=breakpoint  text=>>
