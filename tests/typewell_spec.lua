-- integration tests: setup, commands, and each mode's observable effects.

local typewell = require("typewell")

-- build a normal scratch-like buffer with the given lines and focus it in a
-- window. buftype is cleared to "" so zen (which refuses special buffers)
-- treats it as a normal writing buffer.
local function scratch(lines)
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].buftype = ""
  return buf
end

local function dim_marks(buf)
  local ns = vim.api.nvim_create_namespace("typewell_dim")
  return vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
end

local function pos_marks(buf)
  local ns = vim.api.nvim_create_namespace("typewell_tagger")
  return vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
end

describe("setup", function()
  it("merges user opts over defaults", function()
    typewell.setup({ zen = { ratio = 0.8 }, syntax = { adverbs = true } })
    assert.equals(0.8, typewell.config.zen.ratio)
    assert.is_true(typewell.config.syntax.adverbs)
    -- untouched defaults survive the merge
    assert.equals(0.5, typewell.config.typewriter.anchor)
    assert.is_true(typewell.config.syntax.verbs)
  end)

  it("registers the user command", function()
    typewell.setup({})
    local cmds = vim.api.nvim_get_commands({})
    assert.is_not_nil(cmds.Typewell)
  end)

  it("defines the dim and bright highlight groups", function()
    typewell.setup({})
    -- these are always created; fg is resolved from the colorscheme
    assert.is_not_nil(vim.api.nvim_get_hl(0, { name = "TypewellDim" }))
    assert.is_not_nil(vim.api.nvim_get_hl(0, { name = "TypewellBright" }))
  end)

  it("ensure_config provides defaults without setup (M9 regression)", function()
    typewell.config = nil
    local cfg = typewell.ensure_config()
    assert.is_not_nil(cfg)
    assert.equals(0.5, cfg.typewriter.anchor)
    assert.equals(0.66, cfg.zen.ratio)
  end)
end)

describe("zen dimming", function()
  before_each(function()
    typewell.setup({})
  end)
  after_each(function()
    typewell.zen.disable()
  end)

  it("dims every line except the current one in line focus", function()
    local buf = scratch({ "one", "two", "three", "four", "five" })
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    typewell.setup({ zen = { focus = "line" } })
    typewell.zen.enable()

    local marks = dim_marks(buf)
    assert.equals(4, #marks) -- 5 lines, 1 bright
    for _, mark in ipairs(marks) do
      assert.are_not.equal(2, mark[2]) -- row 2 (line 3) must not be dimmed
    end
  end)

  it("keeps extmarks within their own row (no out-of-bounds end_row)", function()
    local buf = scratch({ "alpha", "beta", "gamma" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    typewell.zen.enable()

    for _, mark in ipairs(dim_marks(buf)) do
      local row = mark[2]
      local details = mark[4]
      -- end_row must equal the start row: spilling into row+1 crashes
      -- treesitter's fold reader
      assert.equals(row, details.end_row)
    end
  end)

  it("restores options and closes padding on disable", function()
    scratch({ "a", "b", "c" })
    local windows_before = #vim.api.nvim_tabpage_list_wins(0)
    typewell.zen.enable()
    assert.is_true(#vim.api.nvim_tabpage_list_wins(0) > windows_before)
    typewell.zen.disable()
    assert.equals(windows_before, #vim.api.nvim_tabpage_list_wins(0))
  end)

  it("hides cursorline only when hide.cursorline is true (C2 regression)", function()
    scratch({ "a", "b", "c" })
    local win = vim.api.nvim_get_current_win()
    vim.wo[win].cursorline = true

    -- default hide.cursorline=false -> cursorline must be left ON
    typewell.setup({})
    typewell.zen.enable()
    assert.is_true(vim.wo[win].cursorline)
    typewell.zen.disable()

    -- hide.cursorline=true -> cursorline turned OFF, restored after
    typewell.setup({ zen = { hide = { cursorline = true } } })
    typewell.zen.enable()
    assert.is_false(vim.wo[win].cursorline)
    typewell.zen.disable()
    assert.is_true(vim.wo[win].cursorline)
  end)

  it("refuses to zen a special (non-normal) buffer", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "x" })
    vim.api.nvim_set_current_buf(buf)
    local windows_before = #vim.api.nvim_tabpage_list_wins(0)
    typewell.zen.enable()
    -- no padding windows created, no state
    assert.equals(windows_before, #vim.api.nvim_tabpage_list_wins(0))
    assert.is_nil(typewell.zen.state)
  end)
end)

describe("typewriter", function()
  before_each(function()
    typewell.setup({})
  end)
  after_each(function()
    typewell.typewriter.disable()
  end)

  it("does not corrupt buffer text when typing", function()
    local buf = scratch({ "" })
    typewell.typewriter.enable()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("normal ihello world")
    assert.equals("hello world", vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
  end)

  it("sets a large scrolloff for a centered anchor and restores it", function()
    scratch({ "x", "y", "z" })
    local win = vim.api.nvim_get_current_win()
    local before = vim.wo[win].scrolloff
    typewell.typewriter.enable()
    assert.equals(999, vim.wo[win].scrolloff)
    typewell.typewriter.disable()
    assert.equals(before, vim.wo[win].scrolloff)
  end)

  it("does not leak scrolloff after combined focus toggle (C1 regression)", function()
    scratch({ "x", "y", "z" })
    local win = vim.api.nvim_get_current_win()
    vim.wo[win].scrolloff = 7
    -- bare :Typewell enables zen + typewriter (both want centering)
    typewell.dispatch("")
    assert.equals(999, vim.wo[win].scrolloff)
    -- and off restores the true original, not 999
    typewell.dispatch("")
    assert.equals(7, vim.wo[win].scrolloff)
  end)
end)

describe("syntax highlighting", function()
  before_each(function()
    typewell.setup({})
  end)
  after_each(function()
    typewell.syntax.disable()
  end)

  it("paints extmarks for verbs and adjectives", function()
    local buf = scratch({ "the beautiful writer walked home" })
    typewell.syntax.enable(buf)
    -- "beautiful" (adj) + "walked" (verb) -> at least 2 marks
    assert.is_true(#pos_marks(buf) >= 2)
  end)

  it("clears marks on disable", function()
    local buf = scratch({ "running quickly" })
    typewell.syntax.enable(buf)
    typewell.syntax.disable(buf)
    assert.equals(0, #pos_marks(buf))
  end)
end)

describe("focus toggle", function()
  it("turns everything on and back off via bare :Typewell", function()
    typewell.setup({})
    scratch({ "some words here", "more words there" })
    typewell.dispatch("")
    assert.is_true(typewell.focus_on)
    typewell.dispatch("")
    assert.is_false(typewell.focus_on)
  end)
end)
