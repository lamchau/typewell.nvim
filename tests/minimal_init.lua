-- minimal init for running the test suite headless with plenary.
--
--   nvim --headless -u tests/minimal_init.lua \
--     -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"
--
-- (the Makefile wraps this — just run `make test`.)

-- put this plugin and plenary on the runtimepath
local this_file = debug.getinfo(1, "S").source:sub(2)
local plugin_root = vim.fn.fnamemodify(this_file, ":p:h:h")
vim.opt.runtimepath:append(plugin_root)

-- locate plenary from the standard lazy.nvim install path
local plenary = vim.fn.stdpath("data") .. "/lazy/plenary.nvim"
if vim.fn.isdirectory(plenary) == 1 then
  vim.opt.runtimepath:append(plenary)
else
  error("plenary.nvim not found at " .. plenary)
end

vim.cmd("runtime plugin/plenary.vim")
