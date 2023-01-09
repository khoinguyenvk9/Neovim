
local ffi = require("ffi")
local api = vim.api
local fn = vim.fn
local o, wo, bo = vim.o, vim.wo, vim.bo
local augroup = api.nvim_create_augroup('fold_preview', { clear = true })
local M = {}

ffi.cdef('int curwin_col_off(void);')

---Raise a warning message
---@param msg string
local function warn(msg)
   vim.schedule(function()
      vim.notify_once('[pretty-fold.nvim] '..msg, vim.log.levels.WARN)
   end)
end

---@class fold-preview.Config
---@field border string | string[]
---@field default_keybindings boolean
---@field border_shift integer[] Shift of the preview window due to the thikness of each of 4 parts of the border: {up, right, down, left}

---@type fold-preview.Config
M.config = {
   default_keybindings = true,
   border = { ' ', '', ' ', ' ', ' ', ' ', ' ', ' ' },
}

---@param config? table
function M.setup(config)
   if fn.has('nvim-0.7') ~= 1 then
      warn('Neovim v0.7 or higher is required')
      return
   end

   config = vim.tbl_deep_extend('force', M.config, config or {}) --[[@as fold-preview.Config]]
   M.config = config

   config.border_shift = {}
   if type(config.border) == 'string' then
      if config.border == 'none' then
         config.border_shift = { 0, 0, 0, 0 }
      elseif vim.tbl_contains({ 'single', 'double', 'rounded', 'solid' }, config.border)
      then
         config.border_shift = { -1, -1, -1, -1 }
      elseif config.border == 'shadow' then
         config.border_shift = { 0, -1, -1, 0 }
      end
   elseif type(config.border) == 'table' then
      for i = 1, 4 do
         M.config.border_shift[i] = config.border[i*2] == '' and 0 or -1
      end
   else
      assert(false, 'Invalid border type or value')
   end

   M.fold_preview_cocked = true
   if M.config.default_keybindings then
      local ok, keymap_amend = pcall(require, 'keymap-amend')
      if not ok then
        warn('The "anuvyklack/keymap-amend.nvim" plugin is required for preview key mappings to work')
        return
      end
      keymap_amend('n', 'h',  M.mapping.show_close_preview_open_fold)
      keymap_amend('n', 'l',  M.mapping.close_preview_open_fold)
      keymap_amend('n', 'zo', M.mapping.close_preview)
      keymap_amend('n', 'zO', M.mapping.close_preview)
      keymap_amend('n', 'zc', M.mapping.close_preview_without_defer)
      keymap_amend('n', 'zR', M.mapping.close_preview)
      keymap_amend('n', 'zM', M.mapping.close_preview_without_defer)
   end

   api.nvim_set_hl(0, 'FoldPreview', { link = 'NormalFloat', default = true })
   api.nvim_set_hl(0, 'FoldPreviewBorder', { link = 'FloatBorder', default = true })
end

---Open popup window with folded text preview. Also set autocommands to close
---popup window and change its size on scrolling and vim resizing.
function M.show_preview()
   local fold_start = fn.foldclosed('.') -- '.' is the current line
   if fold_start == -1 then
      return false
   end
   local fold_end = fn.foldclosedend('.')
   local config = M.config

   ---Current window ID, i.e window from which preview was opened.
   local curwin = api.nvim_get_current_win()

   -- Some plugins (for example 'beauwilliams/focus.nvim') change this option,
   -- but we need it to make scrolling work correctly.
   local winminheight = o.winminheight
   o.winminheight = 1

   ---The number of folded lines.
   local fold_size = fold_end - fold_start + 1

   ---The maximum line length of the folded region.
   local max_line_len = 0

   local folded_lines = api.nvim_buf_get_lines(0, fold_start - 1, fold_end, true)
   local indent = #(folded_lines[1]:match('^%s+') or '')
   for i, line in ipairs(folded_lines) do
      if indent > 0 then
         line = line:sub(indent + 1)
      end
      folded_lines[i] = line
      local line_len = fn.strdisplaywidth(line)
      if line_len > max_line_len then max_line_len = line_len end
   end

   local bufnr = api.nvim_create_buf(false, true)
   api.nvim_buf_set_lines(bufnr, 0, 1, false, folded_lines)
   bo[bufnr].filetype = bo.filetype
   bo[bufnr].modifiable = false

   ---The width of offset of a window, occupied by line number column,
   ---fold column and sign column.
   ---@type integer
   local text_offset = ffi.C.curwin_col_off() ---@diagnostic disable-line

   ---The number of columns from the left boundary of the preview window to the
   ---right boundary of the current window.
   local room_right = api.nvim_win_get_width(0) - text_offset - indent

   ---The height of the winbar.
   local winbar = (wo.winbar ~= '') and 1 or 0

   ---The number of window rows from the current cursor line to the end of the
   ---window. I.e. room below for float window.
   local room_below = api.nvim_win_get_height(0) - winbar - fn.winline()
   if room_below == 0 then
      return false
   end

   local winid = api.nvim_open_win(bufnr, false, {
      border = config.border,
      relative = 'win',
      bufpos = {
         fold_start - 1, -- zero-indexed, that's why minus one
         indent,
      },
      -- The position of the window relative to 'bufpos' field.
      row = config.border_shift[1],
      col = config.border_shift[4],
      width = (max_line_len + 2 < room_right) and max_line_len + 1 or room_right - 1,
      height = fold_size < room_below and fold_size or room_below,
      style = 'minimal',
      focusable = false,
      noautocmd = true
   })
   o.eventignore = 'all'
   wo[winid].winhighlight = 'NormalFloat:FoldPreview,FloatBorder:FoldPreviewBorder'
   wo[winid].foldenable = false
   wo[winid].signcolumn = 'no'
   wo[winid].conceallevel = wo[curwin].conceallevel
   o.eventignore = nil

   function M.close_preview()
      if api.nvim_win_is_valid(winid) then
         api.nvim_win_close(winid, false)
      end
      if api.nvim_buf_is_valid(bufnr) then
         api.nvim_buf_delete(bufnr, { force = true, unload = false })
      end
      vim.o.winminheight = winminheight
      api.nvim_clear_autocmds({ group = augroup })
      M.close_preview = nil
      M.fold_preview_cocked = true
   end

   ---Current buffer ID
   local curbufnr = api.nvim_get_current_buf()

   -- close
   api.nvim_create_autocmd({ 'CursorMoved', 'ModeChanged', 'BufLeave' }, {
      group = augroup,
      once = true,
      buffer = curbufnr,
      callback = M.close_preview
   })

   -- window scrolled
   api.nvim_create_autocmd('WinScrolled', {
      group = augroup,
      buffer = curbufnr,
      callback = function()
         room_below = api.nvim_win_get_height(0) - fn.winline() + 1
         api.nvim_win_set_height(winid,
            fold_size < room_below and fold_size or room_below)
      end
   })

   -- vim resize
   api.nvim_create_autocmd('VimResized', {
      group = augroup,
      buffer = curbufnr,
      callback = function()
         room_right = api.nvim_win_get_width(0) - text_offset - indent --[[@as integer]]
         api.nvim_win_set_width(winid,
            max_line_len < room_right and max_line_len or room_right)
      end
   })

   return true
end

function M.toggle_preview()
   if M.close_preview then
      -- For smoothness to avoid annoying screen flickering.
      vim.defer_fn(M.close_preview, 1)
      return true
   else
      return M.show_preview()
   end
end

---Functions in this table are meant to be used with the next plugin:
--- https://github.com/anuvyklack/keymap-amend.nvim
M.mapping = {}

---Show preview, if preview opened — close it and open fold.
---If no closed fold under the cursor, execute original mapping.
---@param original function
function M.mapping.show_close_preview_open_fold(original)
   if fn.foldclosed('.') ~= -1 then -- fold exist
      if M.fold_preview_cocked then
         local ok = M.show_preview()
         if ok then
            M.fold_preview_cocked = false
         end
      else
         api.nvim_command('normal! zv') -- open fold
         vim.defer_fn(function() -- For smoothness to avoid annoying screen flickering.
            if M.close_preview then M.close_preview() end
         end, 1)
      end
   else
      original()
   end
end

---Close preview and open fold or execute original mapping.
---@param original function
function M.mapping.close_preview_open_fold(original)
   if fn.foldclosed('.') ~= -1 then -- fold exist
      api.nvim_command('normal! zv') -- open fold
      if not M.fold_preview_cocked then
         vim.defer_fn(function() -- For smoothness to avoid annoying screen flickering.
            if M.close_preview then M.close_preview() end
         end, 1)
      end
   else
      original()
   end
end

---Close preview and execute original mapping.
---@param original function
function M.mapping.close_preview(original)
   vim.defer_fn(function()
      if M.close_preview then M.close_preview() end
   end, 1)
   original()
end

---Close preview immediately (without very small defer which was added to avoid
---flickering during opening fold) and execute original mapping. This function
---should be used, when you want to close fold-preview without opening fold.
---@param original function
function M.mapping.close_preview_without_defer(original)
   if M.close_preview then M.close_preview() end
   original()
end

return M
