-- zen / focus mode.
--
-- Centers the text in a fixed-width column, hides UI chrome (line numbers,
-- sign column, statusline), and optionally dims everything except the current
-- focus region. Implemented with side padding windows so it works without any
-- external dependency.

local center = require("typewell.center")

local M = {}

-- single active-zen state (zen owns global chrome like laststatus/showtabline,
-- so only one zen session makes sense at a time)
M.state = nil

local dim_namespace = vim.api.nvim_create_namespace("typewell_dim")

-- window-local options we override, captured from a specific window
local function snapshot_win_options(winid)
  return {
    number = vim.wo[winid].number,
    relativenumber = vim.wo[winid].relativenumber,
    signcolumn = vim.wo[winid].signcolumn,
    cursorline = vim.wo[winid].cursorline,
    fillchars = vim.wo[winid].fillchars,
  }
end

-- global options we override
local function snapshot_global_options()
  return {
    laststatus = vim.o.laststatus,
    cmdheight = vim.o.cmdheight,
    showtabline = vim.o.showtabline,
  }
end

-- create empty scratch buffers on the left/right to squeeze the text column.
-- returns the two padding window handles (or nil, nil if too narrow to pad).
local function make_padding(main_win, total_width, text_width)
  local pad = math.floor((total_width - text_width) / 2)
  if pad < 1 then
    return nil, nil
  end

  vim.api.nvim_set_current_win(main_win)

  -- left pad
  vim.cmd("topleft " .. pad .. "vnew")
  local left = vim.api.nvim_get_current_win()
  local left_buf = vim.api.nvim_get_current_buf()

  vim.api.nvim_set_current_win(main_win)

  -- right pad
  vim.cmd("botright " .. pad .. "vnew")
  local right = vim.api.nvim_get_current_win()
  local right_buf = vim.api.nvim_get_current_buf()

  -- make the padding buffers inert and invisible
  for _, buf in ipairs({ left_buf, right_buf }) do
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].modifiable = false
    -- keep them out of the bufferline / :ls / :bnext cycle
    vim.bo[buf].buflisted = false
  end
  for _, win in ipairs({ left, right }) do
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = "no"
    vim.wo[win].cursorline = false
    vim.wo[win].winhighlight = "Normal:TypewellPad,EndOfBuffer:TypewellPad"
    vim.wo[win].statuscolumn = ""
    vim.wo[win].fillchars = "eob: "
  end

  vim.api.nvim_set_current_win(main_win)
  return left, right
end

-- read line `lnum` (1-based) from a specific buffer without touching the
-- current-buffer state that vim.fn.getline() implicitly depends on
local function buf_line(bufnr, lnum)
  return vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ""
end

-- compute the [start_line, end_line] focus region around `cursor_line` for the
-- configured granularity. all bounds are 1-based inclusive.
local function focus_region(bufnr, mode, cursor_line, total)
  if mode == "line" then
    -- typewriter focus: only the current line stays bright
    return cursor_line, cursor_line
  elseif mode == "sentence" then
    -- widen to the nearest sentence-ending punctuation on either side,
    -- but never cross a blank line
    local start_line = cursor_line
    while start_line > 1
      and buf_line(bufnr, start_line - 1):match("%S")
      and not buf_line(bufnr, start_line - 1):match("[.!?]%s*$") do
      start_line = start_line - 1
    end
    local end_line = cursor_line
    while end_line < total
      and buf_line(bufnr, end_line):match("%S")
      and not buf_line(bufnr, end_line):match("[.!?]%s*$") do
      end_line = end_line + 1
    end
    return start_line, end_line
  end

  -- default: paragraph (blank-line delimited)
  local start_line = cursor_line
  while start_line > 1 and buf_line(bufnr, start_line - 1):match("%S") do
    start_line = start_line - 1
  end
  local end_line = cursor_line
  while end_line < total and buf_line(bufnr, end_line + 1):match("%S") do
    end_line = end_line + 1
  end
  return start_line, end_line
end

-- dim all VISIBLE lines except the current focus region. only the viewport is
-- painted (cheap on large documents); scrolling repaints via WinScrolled.
local function apply_dim(winid, bufnr, mode)
  -- bail if zen was torn down before this (possibly scheduled) call ran
  if not M.state or M.state.win ~= winid then
    return
  end
  if not vim.api.nvim_win_is_valid(winid) or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local total = vim.api.nvim_buf_line_count(bufnr)

  -- resolve cursor + viewport from the zen window specifically
  local cursor_line = vim.api.nvim_win_get_cursor(winid)[1]
  local first = vim.fn.line("w0", winid)
  local last = vim.fn.line("w$", winid)
  if first < 1 then
    first = 1
  end
  if last < 1 or last > total then
    last = total
  end

  local start_line, end_line = focus_region(bufnr, mode, cursor_line, total)

  -- clear only the viewport band, then repaint it
  vim.api.nvim_buf_clear_namespace(bufnr, dim_namespace, first - 1, last)

  for lnum = first, last do
    if lnum < start_line or lnum > end_line then
      -- dim to the end of this line only. we deliberately do NOT use
      -- `end_row = lnum` (which points one row past the last line and makes
      -- treesitter's fold reader call nvim_buf_get_text out of bounds).
      -- `hl_eol` + a same-line `end_col` covers the whole line including
      -- trailing space without spilling into the next row.
      local line_len = #buf_line(bufnr, lnum)
      vim.api.nvim_buf_set_extmark(bufnr, dim_namespace, lnum - 1, 0, {
        end_row = lnum - 1,
        end_col = line_len,
        hl_group = "TypewellDim",
        hl_eol = true,
        -- very high priority so it overrides treesitter / render-markdown
        -- header highlights, which otherwise stay bright
        priority = 10000,
      })
    end
  end
end

function M.enable()
  if M.state then
    return
  end

  local cfg = require("typewell").ensure_config().zen
  local main_win = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(main_win)

  -- refuse to zen special (non-normal) buffers: terminal, help, quickfix,
  -- prompt, nofile, floating windows — splitting/chrome-hiding those is wrong
  local buftype = vim.bo[bufnr].buftype
  local is_float = vim.api.nvim_win_get_config(main_win).relative ~= ""
  if buftype ~= "" or is_float then
    vim.notify("[typewell] zen needs a normal buffer window", vim.log.levels.WARN)
    return
  end

  local saved_win = snapshot_win_options(main_win)
  local saved_global = snapshot_global_options()

  -- turn off render-markdown's decorations inside zen so header backgrounds
  -- and icons don't stay bright over the dim. only re-enable on exit if it
  -- was actually enabled when we entered.
  local render_markdown_was_on = false
  local ok, render_markdown = pcall(require, "render-markdown")
  if ok and render_markdown then
    -- render-markdown exposes state via .get() in recent versions; fall back
    -- to assuming it was on if we can't tell
    local enabled = true
    if type(render_markdown.get) == "function" then
      local state_ok, state = pcall(render_markdown.get)
      if state_ok and type(state) == "table" and state.enabled ~= nil then
        enabled = state.enabled
      end
    end
    if enabled and type(render_markdown.disable) == "function" then
      render_markdown_was_on = true
      pcall(render_markdown.disable)
    end
  end

  -- hide chrome on the writing window (scoped explicitly to that window)
  if cfg.hide.number then
    vim.wo[main_win].number = false
  end
  if cfg.hide.relativenumber then
    vim.wo[main_win].relativenumber = false
  end
  if cfg.hide.signcolumn then
    vim.wo[main_win].signcolumn = "no"
  end
  if cfg.hide.cursorline then
    vim.wo[main_win].cursorline = false
  end
  if cfg.hide.statusline then
    vim.o.laststatus = 0
    -- also hide the tabline / bufferline for a truly clean canvas
    vim.o.showtabline = 0
  end
  if cfg.hide.cmdheight then
    vim.o.cmdheight = 0
  end
  vim.wo[main_win].fillchars = "eob: "

  -- keep the cursor line vertically centered via shared window-local scrolloff
  center.acquire(main_win)

  -- resolve the target text-column width: explicit `width` wins, otherwise
  -- use `ratio` of the window, capped by `max_width`
  local total_width = vim.api.nvim_win_get_width(main_win)
  local text_width = cfg.width
  if not text_width then
    text_width = math.floor(total_width * (cfg.ratio or 0.66))
    if cfg.max_width and text_width > cfg.max_width then
      text_width = cfg.max_width
    end
  end

  local left, right = make_padding(main_win, total_width, text_width)

  local group = vim.api.nvim_create_augroup("TypewellZen", { clear = true })

  M.state = {
    win = main_win,
    bufnr = bufnr,
    saved_win = saved_win,
    saved_global = saved_global,
    left = left,
    right = right,
    group = group,
    dim = cfg.dim,
    render_markdown_was_on = render_markdown_was_on,
  }

  if cfg.dim then
    local mode = cfg.focus or "line"
    -- repaint on cursor movement, edits, and scrolling (viewport-limited)
    vim.api.nvim_create_autocmd(
      { "CursorMoved", "CursorMovedI", "TextChanged", "TextChangedI", "WinScrolled" },
      {
        group = group,
        buffer = bufnr,
        callback = function()
          -- defer so our extmarks land after treesitter's current parse pass,
          -- avoiding a race with the fold reader on freshly-changed lines
          vim.schedule(function()
            apply_dim(main_win, bufnr, mode)
          end)
        end,
      }
    )
    apply_dim(main_win, bufnr, mode)
  end

  -- leave zen automatically if the writing window/buffer is closed
  vim.api.nvim_create_autocmd("BufWinLeave", {
    group = group,
    buffer = bufnr,
    callback = function()
      M.disable()
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(main_win),
    callback = function()
      M.disable()
    end,
  })
end

function M.disable()
  if not M.state then
    return
  end
  local state = M.state
  M.state = nil

  pcall(vim.api.nvim_del_augroup_by_id, state.group)

  -- re-enable render-markdown only if we turned it off on the way in
  if state.render_markdown_was_on then
    local ok, render_markdown = pcall(require, "render-markdown")
    if ok and render_markdown and type(render_markdown.enable) == "function" then
      pcall(render_markdown.enable)
    end
  end

  -- close padding windows
  for _, win in ipairs({ state.left, state.right }) do
    if win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end

  -- clear dim marks
  if vim.api.nvim_buf_is_valid(state.bufnr) then
    vim.api.nvim_buf_clear_namespace(state.bufnr, dim_namespace, 0, -1)
  end

  -- release centering (restores the window's original scrolloff)
  center.release(state.win)

  -- restore window-local options on the ORIGINAL writing window
  if vim.api.nvim_win_is_valid(state.win) then
    local saved = state.saved_win
    vim.wo[state.win].number = saved.number
    vim.wo[state.win].relativenumber = saved.relativenumber
    vim.wo[state.win].signcolumn = saved.signcolumn
    vim.wo[state.win].cursorline = saved.cursorline
    vim.wo[state.win].fillchars = saved.fillchars
  end

  -- restore global options
  local saved_global = state.saved_global
  vim.o.laststatus = saved_global.laststatus
  vim.o.cmdheight = saved_global.cmdheight
  vim.o.showtabline = saved_global.showtabline
end

function M.toggle()
  if M.state then
    M.disable()
  else
    M.enable()
  end
end

return M
