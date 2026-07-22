-- typewell.nvim — a distraction-free writing environment for focused prose.
--
-- Features:
--   * Zen mode      — centered fixed-width column, hidden chrome, dimmed
--                     surrounding paragraphs (focus mode).
--   * Typewriter    — the active line stays pinned; text scrolls under it.
--   * part-of-speech highlight — verbs, adjectives (and optionally nouns/adverbs) are
--                     colored as you write.
--
-- Usage:
--   require("typewell").setup({ ... })
--   :Typewell           — toggle the full focus experience
--   :Typewell zen | typewriter | syntax | off

local M = {}

M.config = nil

local zen = require("typewell.zen")
local typewriter = require("typewell.typewriter")
local syntax = require("typewell.syntax")

-- ensure config exists even if the user calls a public API entry point before
-- setup(). returns the resolved config so every entry point can guard cheaply.
function M.ensure_config()
  if not M.config then
    M.config = vim.tbl_deep_extend("force", require("typewell.config").defaults, {})
  end
  return M.config
end

-- parse "#rrggbb" or a decimal color into {r, g, b}, or nil
local function to_rgb(color)
  if type(color) == "number" then
    return {
      math.floor(color / 65536) % 256,
      math.floor(color / 256) % 256,
      color % 256,
    }
  end
  if type(color) == "string" then
    local hex = color:gsub("#", "")
    if #hex == 6 then
      return {
        tonumber(hex:sub(1, 2), 16),
        tonumber(hex:sub(3, 4), 16),
        tonumber(hex:sub(5, 6), 16),
      }
    end
  end
  return nil
end

-- blend two rgb colors; amount 0 = a, 1 = b
local function blend(rgb_a, rgb_b, amount)
  local out = {}
  for i = 1, 3 do
    out[i] = math.floor(rgb_a[i] + (rgb_b[i] - rgb_a[i]) * amount + 0.5)
  end
  return string.format("#%02x%02x%02x", out[1], out[2], out[3])
end

-- resolve the Normal highlight's fg/bg as rgb, with sane fallbacks
local function normal_colors()
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  local dark = vim.o.background == "dark"
  local fg = to_rgb(normal.fg) or (dark and { 220, 220, 220 } or { 40, 40, 40 })
  local bg = to_rgb(normal.bg) or (dark and { 30, 30, 30 } or { 250, 250, 250 })
  return fg, bg
end

-- define highlight groups from config; called on setup and ColorScheme
local function define_highlights()
  local hl = M.config.highlights
  local fg, bg = normal_colors()

  -- dimmed text: fade Normal fg toward Normal bg (same bg, greyer fg)
  local dim_fg = hl.dim_fg
  if not dim_fg then
    dim_fg = blend(fg, bg, hl.dim_blend or 0.6)
  end

  -- bright text: full-strength fg (or an explicit override)
  local bright_fg = hl.bright_fg
  if not bright_fg then
    bright_fg = string.format("#%02x%02x%02x", fg[1], fg[2], fg[3])
  end

  local map = {
    TypewellVerb = hl.verb,
    TypewellAdjective = hl.adjective,
    TypewellNoun = hl.noun,
    TypewellAdverb = hl.adverb,
    TypewellConjunction = hl.conjunction,
    -- explicit fg colors, NOT links, so dim always reads as greyed-out
    TypewellDim = { fg = dim_fg },
    TypewellBright = { fg = bright_fg },
    -- padding windows blend into the background
    TypewellPad = { link = "Normal" },
  }
  for group, spec in pairs(map) do
    vim.api.nvim_set_hl(0, group, vim.tbl_extend("keep", spec, { default = true }))
  end
end

-- deep-merge user opts over defaults
function M.setup(opts)
  local defaults = require("typewell.config").defaults
  M.config = vim.tbl_deep_extend("force", defaults, opts or {})
  define_highlights()

  -- re-apply highlight groups when the colorscheme changes
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("TypewellColors", { clear = true }),
    callback = define_highlights,
  })

  -- :Typewell [subcommand] — bare :Typewell toggles the full focus experience
  vim.api.nvim_create_user_command("Typewell", function(args)
    M.dispatch(args.args)
  end, {
    nargs = "?",
    complete = function()
      return { "zen", "typewriter", "syntax", "focus", "off" }
    end,
    desc = "typewell: [focus] | zen | typewriter | syntax | off",
  })

  return M
end

-- track combined focus state so bare :Typewell toggles cleanly
M.focus_on = false

-- is any focus component currently active in the current window/buffer?
function M.is_focus_active()
  local winid = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_get_current_buf()
  if zen.state ~= nil then
    return true
  end
  if typewriter.active[winid] then
    return true
  end
  if syntax.active[bufnr] then
    return true
  end
  return false
end

-- toggle all three together. derives on/off from actual module state so it
-- never desyncs (e.g. after enabling zen alone, or a component being toggled
-- individually).
function M.toggle_focus()
  if M.is_focus_active() then
    zen.disable()
    typewriter.disable()
    syntax.disable()
    M.focus_on = false
  else
    zen.enable()
    typewriter.enable()
    syntax.enable()
    M.focus_on = true
  end
end

-- run a subcommand; bare ("") or "focus" toggles the full experience
function M.dispatch(cmd)
  if cmd == "zen" then
    zen.toggle()
  elseif cmd == "typewriter" then
    typewriter.toggle()
  elseif cmd == "syntax" then
    syntax.toggle()
  elseif cmd == "focus" or cmd == "" then
    -- toggle all three together
    M.toggle_focus()
  elseif cmd == "off" then
    zen.disable()
    typewriter.disable()
    syntax.disable()
    M.focus_on = false
  else
    vim.notify("[typewell] unknown command: " .. cmd, vim.log.levels.WARN)
  end
end

-- public API for keymaps
M.zen = zen
M.typewriter = typewriter
M.syntax = syntax

return M
