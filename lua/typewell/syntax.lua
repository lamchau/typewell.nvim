-- part-of-speech highlighting via extmarks.
--
-- Re-tags visible lines of a buffer on change/scroll and paints each word
-- with the highlight group for its part of speech.

local tagger = require("typewell.tagger")

local M = {}

local namespace = vim.api.nvim_create_namespace("typewell_tagger")

-- map a part-of-speech tag -> highlight group name defined in highlights.lua
local TAG_HL = {
  verb = "TypewellVerb",
  adjective = "TypewellAdjective",
  noun = "TypewellNoun",
  adverb = "TypewellAdverb",
  conjunction = "TypewellConjunction",
}

-- buffers we've attached to, keyed by bufnr -> true
M.active = {}

-- highlight one line's words using the classifier
local function highlight_line(bufnr, lnum, line, enabled)
  -- iterate word spans; %a is a letter, apostrophes allowed inside words
  local col = 1
  while col <= #line do
    local start_col, end_col = line:find("[%a][%a']*", col)
    if not start_col then
      break
    end

    local word = line:sub(start_col, end_col):lower()
    local tag = tagger.classify(word, enabled)
    if tag then
      local group = TAG_HL[tag]
      if group then
        vim.api.nvim_buf_set_extmark(bufnr, namespace, lnum, start_col - 1, {
          end_col = end_col,
          hl_group = group,
          priority = 100,
        })
      end
    end

    col = end_col + 1
  end
end

-- re-highlight the currently visible window range for the buffer
function M.refresh(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not M.active[bufnr] then
    return
  end

  local enabled = require("typewell").ensure_config().syntax

  -- resolve the viewport from a window actually showing this buffer, not
  -- whatever window happens to be current (they can differ under autocmds
  -- or when the buffer is shown in multiple splits)
  local winid = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(winid) ~= bufnr then
    winid = nil
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == bufnr then
        winid = win
        break
      end
    end
    if not winid then
      return
    end
  end

  -- only paint the visible viewport; cheaper on large documents
  local first = vim.fn.line("w0", winid) - 1
  local last = vim.fn.line("w$", winid)
  if first < 0 then
    first = 0
  end

  vim.api.nvim_buf_clear_namespace(bufnr, namespace, first, last)

  local lines = vim.api.nvim_buf_get_lines(bufnr, first, last, false)
  for index, line in ipairs(lines) do
    highlight_line(bufnr, first + index - 1, line, enabled)
  end
end

-- turn highlighting on for a buffer and wire up refresh autocommands
function M.enable(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  M.active[bufnr] = true

  local group = vim.api.nvim_create_augroup("TypewellPos" .. bufnr, { clear = true })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "WinScrolled" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      M.refresh(bufnr)
    end,
  })

  M.refresh(bufnr)
end

-- turn highlighting off and clear marks
function M.disable(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  M.active[bufnr] = nil
  pcall(vim.api.nvim_del_augroup_by_name, "TypewellPos" .. bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
end

function M.toggle(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if M.active[bufnr] then
    M.disable(bufnr)
  else
    M.enable(bufnr)
  end
end

return M
