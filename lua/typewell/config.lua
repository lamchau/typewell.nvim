-- default configuration, merged with user opts in init.setup()
local M = {}

M.defaults = {
  zen = {
    -- text column as a fraction of the window width (0.66 == two-thirds),
    -- capped by `max_width`. Set `width` to a number to force fixed columns.
    ratio = 0.66,
    max_width = 100,
    width = nil,
    -- dim everything except the current focus region
    dim = true,
    -- focus granularity: "line" (single current line, typewriter style),
    -- "sentence", or "paragraph" (blank-line delimited block)
    focus = "line",
    -- ui elements to hide while zen is active
    hide = {
      number = true,
      relativenumber = true,
      signcolumn = true,
      cursorline = false,
      statusline = true, -- laststatus -> 0
      cmdheight = false, -- keep the cmdline visible by default
    },
  },
  typewriter = {
    -- keep the cursor pinned to this fraction of the window height
    -- 0.5 == vertical center. keeps the active line put and
    -- scrolls the text underneath it ("no shift").
    anchor = 0.5,
  },
  syntax = {
    -- parts of speech to highlight; toggle individually
    verbs = true,
    adjectives = true,
    nouns = false,
    adverbs = false,
    conjunctions = false,
  },
  highlights = {
    -- link groups; users can override with their own colors
    verb = { link = "Function" },
    adjective = { link = "Type" },
    noun = { link = "Identifier" },
    adverb = { link = "Constant" },
    conjunction = { link = "Statement" },
    -- dim/bright are resolved at runtime from the colorscheme (see
    -- init.lua define_highlights). `dim_fg`/`bright_fg` let you override
    -- the exact colors; leave nil to auto-derive.
    dim_fg = nil,     -- e.g. "#5c6370"
    bright_fg = nil,  -- e.g. "#ffffff"; nil = use Normal fg
    -- how far to fade the dimmed text toward the background (0..1).
    -- 0 = same as normal fg, 1 = invisible. 0.6 keeps it readable.
    dim_blend = 0.6,
  },
}

return M
