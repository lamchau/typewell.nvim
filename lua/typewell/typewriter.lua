-- typewriter scrolling.
--
-- Keeps the active line locked at a fixed vertical position (default: middle
-- of the window) and scrolls the text underneath it as you type or move.
-- This is the "typewriter mode": the line you're writing never shifts up and
-- down.
--
-- IMPORTANT: we never use `:normal! <C-e>` here. Running normal-mode commands
-- from a TextChangedI/CursorMovedI autocmd corrupts the buffer (stray "0",
-- reordered characters). Instead we adjust the *view* only:
--   * for a centered anchor (0.5) we lean on a large window-local `scrolloff`
--     (owned by the shared center module), which Neovim keeps satisfied for
--     free;
--   * for any other anchor we set the window's topline with `winrestview`,
--     which changes the viewport without ever touching text.

local center = require("typewell.center")

local M = {}

-- winid -> true while typewriter is active for that window
M.active = {}

-- winid -> true when we acquired centering for that window (so disable
-- releases exactly what enable acquired, even if the anchor config changed)
M.acquired = {}

-- true when the anchor is close enough to the middle to use scrolloff
local function is_centered(anchor)
  return math.abs(anchor - 0.5) < 0.02
end

-- reposition the viewport so the cursor line sits at the anchor fraction,
-- using winrestview (view-only, safe in insert mode)
local function recenter(winid)
  local anchor = require("typewell").ensure_config().typewriter.anchor
  if is_centered(anchor) then
    -- scrolloff already keeps the cursor centered; nothing to do
    return
  end
  if not vim.api.nvim_win_is_valid(winid) then
    return
  end

  -- operate explicitly on the target window, not whatever is current
  vim.api.nvim_win_call(winid, function()
    local height = vim.api.nvim_win_get_height(winid)
    local target_row = math.floor(height * anchor)
    if target_row < 1 then
      target_row = 1
    end

    local cursor_line = vim.api.nvim_win_get_cursor(winid)[1]
    local view = vim.fn.winsaveview()
    -- desired first visible line so the cursor lands on target_row
    local topline = cursor_line - target_row + 1
    if topline < 1 then
      topline = 1
    end
    view.topline = topline
    vim.fn.winrestview(view)
  end)
end

function M.enable(winid)
  winid = winid or vim.api.nvim_get_current_win()
  -- guard double-enable: it would acquire scrolloff twice and register
  -- duplicate autocmds
  if M.active[winid] then
    return
  end
  M.active[winid] = true

  local anchor = require("typewell").ensure_config().typewriter.anchor
  local bufnr = vim.api.nvim_win_get_buf(winid)

  -- for a centered anchor, a large window-local scrolloff pins the cursor
  -- line to the middle with no per-keystroke work. shared owner handles
  -- save/restore so zen and typewriter don't clobber each other.
  if is_centered(anchor) then
    center.acquire(winid)
    M.acquired[winid] = true
  end

  local group = vim.api.nvim_create_augroup("TypewellTypewriter" .. winid, { clear = true })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "TextChangedI" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      recenter(winid)
    end,
  })
  -- drop our state if the window closes underneath us
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(winid),
    callback = function()
      M.disable(winid)
    end,
  })

  recenter(winid)
end

function M.disable(winid)
  winid = winid or vim.api.nvim_get_current_win()
  if not M.active[winid] then
    return
  end
  M.active[winid] = nil
  pcall(vim.api.nvim_del_augroup_by_name, "TypewellTypewriter" .. winid)

  if M.acquired[winid] then
    center.release(winid)
    M.acquired[winid] = nil
  end
end

function M.toggle(winid)
  winid = winid or vim.api.nvim_get_current_win()
  if M.active[winid] then
    M.disable(winid)
  else
    M.enable(winid)
  end
end

return M
