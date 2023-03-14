local status, telescope = pcall(require, 'telescope')
if not status then return end

local actions = require('telescope.actions')
-- local fb_actions = require 'telescope'.extensions.file_browser.actions

telescope.setup {
  defaults = {
    file_ignore_patterns = { 'node_modules', 'dist', '.git' }, -- ignore in specific project
    layout_config = {
      width = 0.9,
      preview_cutoff = 120,
      preview_width = 0.6,
    },
    mappings = {
      i = {
        ['<C-j>'] = actions.move_selection_next,
        ['<C-k>'] = actions.move_selection_previous,
        ['<C-s>'] = actions.select_horizontal,
      },
      n = {
        ['<C-c>'] = actions.close,
        ['<C-s>'] = actions.select_horizontal,
      },
    },
    preview = {
      mime_hook = function(filepath, bufnr, opts)
        local is_image = function(filepath)
          local image_extensions = { "png", "jpg", "jpeg", "gif" } -- Supported image formats
          local split_path = vim.split(filepath:lower(), ".", { plain = true })
          local extension = split_path[#split_path]
          return vim.tbl_contains(image_extensions, extension)
        end
        if is_image(filepath) then
          local term = vim.api.nvim_open_term(bufnr, {})
          local function send_output(_, data, _)
            for _, d in ipairs(data) do
              vim.api.nvim_chan_send(term, d .. "\r\n")
            end
          end
          vim.fn.jobstart({
            "viu",
            "-w",
            "40",
            "-b",
            filepath,
          }, {
            on_stdout = send_output,
            stdout_buffered = true,
          })
        else
          require("telescope.previewers.utils").set_preview_message(
            bufnr,
            opts.winid,
            "Binary cannot be previewed"
          )
        end
      end,
    },
  },
  pickers = {},
  -- extensions = {
  --   file_browser = {
  --     path = '%:p:h',  -- launchs in the current buffer
  --     grouped = true,
  --     respect_gitignore = false,
  --     hidden = true,
  --     initial_mode = 'normal',
  --     -- disables netrw and use telescope-file-browser in its place
  --     hijack_netrw = true,
  --     mappings = {
  --       ['i'] = {
  --         ['C-c'] = function() vim.cmd('normal vbd') end,
  --       },
  --       ['n'] = {
  --         ['a'] = fb_actions.create,
  --         ['c'] = fb_actions.copy,
  --         ['gp'] = fb_actions.goto_parent_dir,
  --         ['/'] = function() vim.cmd('startinsert') end,
  --         -- ['<C-/>'] = fb_acti
  --
  --         -- remove key mappings of fb_actions.goto_home_dir
  --         ['?'] = false,
  --         ['e'] = false,
  --         ['C-e'] = false,
  --       },
  --     },
  --   },
  -- }
}

-- telescope.load_extension('file_browser')


--------------------------------------------
--                KEY MAPPINGS            --
--------------------------------------------
function vim.get_selected_text()
  vim.cmd('noau normal! "vy"')
  local text = vim.fn.getreg('v')
  vim.fn.setreg('v', {})

  text = string.gsub(text, '\n', '')
  if #text > 0 then
    return text
  else
    return ''
  end
end

local tele_builtin = require('telescope.builtin')
local Utils = require('steve.core.utils')
local nnoremap = Utils.nnoremap
local vnoremap = Utils.vnoremap

-- Open telescope common commands
nnoremap('<Space>t', ':Telescope<CR>')

-- Search files, text in files
nnoremap('<C-p>', function()
  tele_builtin.find_files({ hidden = true })
end)
nnoremap('<C-a>', tele_builtin.live_grep)
nnoremap('<C-l>', tele_builtin.current_buffer_fuzzy_find)

-- Search with visual selection text
vnoremap('<C-a>', function()
  local text = vim.get_selected_text()
  tele_builtin.live_grep({ default_text = text })
end)
vnoremap('<C-l>', function()
  local text = vim.get_selected_text()
  tele_builtin.current_buffer_fuzzy_find({ default_text = text })
end)

-- File browser
-- nnoremap('<C-n>', ':Telescope file_browser<CR>')
