# typewell.nvim

A distraction-free writing environment for Neovim.

<img width="975" height="988" alt="image" src="https://github.com/user-attachments/assets/f189f22b-1f0f-4517-95a1-3b92bcb751a6" />


## Features

- **Zen mode** — centers your text in a fixed-width column, hides line numbers,
  sign column and statusline, and dims everything except your current focus
  region. By default the focus is a **single line** (single-line typewriter
  style); set `focus = "sentence"` or `"paragraph"` to widen it.
- **Typewriter mode** — pins the active line to a fixed vertical position and
  scrolls the text underneath it, so the line you're typing never shifts ("no
  shift").
- **Syntax highlighting** — colors verbs and adjectives as you write (nouns,
  adverbs and conjunctions are available but off by default).

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "lamchau/typewell.nvim",
  ft = { "markdown", "text" },
  config = function()
    require("typewell").setup({})
  end,
}
```

## Usage

Run bare `:Typewell` to toggle the full experience (all three modes) on and off,
or drive each piece individually:

```vim
:Typewell             " toggle zen + typewriter + syntax together
:Typewell focus       " same as bare :Typewell (toggle all three)
:Typewell zen         " toggle zen / focus column
:Typewell typewriter  " toggle typewriter scrolling
:Typewell syntax      " toggle verb/adjective highlighting
:Typewell off         " turn everything off
```

| Command | Effect |
| --- | --- |
| `:Typewell` | Toggle zen + typewriter + syntax as one |
| `:Typewell focus` | Same as bare `:Typewell` (toggle all three) |
| `:Typewell zen` | Centered dimmed column |
| `:Typewell typewriter` | Cursor-line stays vertically centered |
| `:Typewell syntax` | Verb / adjective highlighting |
| `:Typewell off` | Disable everything |

Suggested keymaps:

```lua
vim.keymap.set("n", "<leader>wf", "<cmd>Typewell<cr>", { desc = "typewell focus" })
vim.keymap.set("n", "<leader>wz", "<cmd>Typewell zen<cr>",   { desc = "typewell zen" })
vim.keymap.set("n", "<leader>wt", "<cmd>Typewell typewriter<cr>", { desc = "typewriter" })
vim.keymap.set("n", "<leader>ws", "<cmd>Typewell syntax<cr>", { desc = "part-of-speech highlight" })
```

## Configuration

Defaults (pass overrides to `setup`):

```lua
require("typewell").setup({
  zen = {
    ratio = 0.66,    -- text column as a fraction of window width (2/3)
    max_width = 100, -- cap the column on very wide screens
    width = nil,     -- set a number to force fixed columns instead of ratio
    dim = true,      -- dim surrounding text
    focus = "line",  -- "line" (single current line), "sentence", or "paragraph"
    hide = { number = true, relativenumber = true, signcolumn = true, cursorline = false, statusline = true, cmdheight = false },
  },
  typewriter = {
    anchor = 0.5,    -- 0.5 = keep cursor line centered
  },
  syntax = {
    verbs = true,
    adjectives = true,
    nouns = false,
    adverbs = false,
    conjunctions = false,
  },
  highlights = {
    verb = { link = "Function" },
    adjective = { link = "Type" },
    noun = { link = "Identifier" },
    adverb = { link = "Constant" },
    conjunction = { link = "Statement" },
    dim_fg = nil,      -- override dimmed fg, e.g. "#5c6370" (nil = auto-derive)
    bright_fg = nil,   -- override current-line fg (nil = Normal fg)
    dim_blend = 0.6,   -- 0 = no fade, 1 = invisible; how grey dimmed text is
  },
})
```

## How part-of-speech detection works

A full statistical tagger is the gold standard. This plugin ships a pure-Lua
approximation: a curated dictionary of common words plus morphological suffix
rules (`-ing`/`-ed` → verb, `-ous`/`-ful`/`-ive` → adjective, `-ly` → adverb,
...). It favors recall over precision, so expect notable false positives in
ordinary prose: common nouns ending in `-al`/`-ic`/`-ate`/`-ing` (hospital,
music, climate, morning) can be mis-tagged. Treat the coloring as an
approximate visual aid, not a linguistics engine or a reliable grammar checker.

The dictionary lives in editable plain-text files under `data/tagger/` — one word
per line, blank lines and `#` comments allowed:

```
data/tagger/
├── stopwords.txt      function words never tagged
├── verbs.txt          dictionary verbs (base + inflected forms)
├── adjectives.txt     dictionary adjectives
├── conjunctions.txt   coordinating / subordinating conjunctions
└── exceptions.txt     common nouns whose endings collide with suffix rules
```

Add words to any file to enrich tagging — no code changes needed. Call
`require("typewell.tagger").reload()` to pick up edits without restarting Neovim.
The suffix rules themselves live in `lua/typewell/tagger.lua`.

## Project layout

```
lua/typewell/
├── init.lua        setup(), :Typewell command, highlight groups
├── config.lua      defaults
├── zen.lua         centered column + chrome hiding + focus dimming
├── typewriter.lua  cursor-line centering ("no shift")
├── center.lua      shared window-local scrolloff owner (cursor centering)
├── syntax.lua      extmark part-of-speech painter
└── tagger.lua      verb / adjective / adverb classifier
data/tagger/           editable dictionary word lists (see above)
tests/
├── minimal_init.lua   runtimepath bootstrap for headless runs
├── tagger_spec.lua       unit tests for the classifier
└── typewell_spec.lua integration tests for setup + each mode
```

## Development

Tests use [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)'s busted
harness. With plenary installed (any lazy.nvim setup has it), run:

```sh
make test
```

This launches headless Neovim, loads the plugin and plenary via
`tests/minimal_init.lua`, and runs every `*_spec.lua` under `tests/`.

The suite covers:

- **`tagger_spec.lua`** — dictionary + suffix tagging, stopword handling, and that
  disabled categories don't fall through to the wrong rule.
- **`typewell_spec.lua`** — option merging, command registration, single-line
  dimming, the extmark bounds that keep treesitter's fold reader happy,
  typewriter not corrupting buffer text, scrolloff save/restore, part-of-speech painting,
  and the bare `:Typewell` toggle.

