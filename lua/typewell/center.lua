-- shared cursor-centering via window-local scrolloff.
--
-- Both zen and typewriter want the cursor line vertically centered, which is
-- achieved with a very large `scrolloff`. Managing that naively double-saves
-- and leaks (feature A saves the original, feature B then saves A's 999 as the
-- "original", and teardown restores 999 forever). This module owns scrolloff
-- for a window with a reference count: the FIRST acquirer captures the true
-- original, the LAST releaser restores it. scrolloff is set window-local
-- (vim.wo[win]) so other splits are never affected.

local M = {}

-- winid -> { count = <refs>, saved = <original window-local scrolloff> }
M.refs = {}

local CENTER_SCROLLOFF = 999

function M.acquire(winid)
  winid = winid or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(winid) then
    return
  end

  local ref = M.refs[winid]
  if not ref then
    -- first acquirer captures the true original before we clobber it
    ref = { count = 0, saved = vim.wo[winid].scrolloff }
    M.refs[winid] = ref
  end
  ref.count = ref.count + 1
  vim.wo[winid].scrolloff = CENTER_SCROLLOFF
end

function M.release(winid)
  winid = winid or vim.api.nvim_get_current_win()
  local ref = M.refs[winid]
  if not ref then
    return
  end

  ref.count = ref.count - 1
  if ref.count <= 0 then
    if vim.api.nvim_win_is_valid(winid) then
      vim.wo[winid].scrolloff = ref.saved
    end
    M.refs[winid] = nil
  end
end

return M
