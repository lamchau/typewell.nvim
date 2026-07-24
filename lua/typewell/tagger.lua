-- lightweight part-of-speech tagging.
--
-- A full statistical part-of-speech tagger is the ideal. We can't ship one in pure
-- Lua, so this module combines a curated dictionary of common words with
-- morphological suffix heuristics. It is intentionally biased toward *recall*
-- for verbs/adjectives/adverbs so the visual highlight feels useful while
-- writing. It will never be perfect — that's fine for a writing aid.
--
-- The word lists live in editable plain-text files under `data/tagger/` (one
-- word per line, `#` comments and blank lines allowed) so the dictionary can
-- grow without touching this code. The suffix rules below stay in Lua because
-- they are logic, not data.

local M = {}

-- locate `data/tagger/` relative to this source file, so lookups work no matter
-- the current working directory. this file is at lua/typewell/tagger.lua, and the
-- data lives at data/tagger/ from the plugin root (three levels up).
local function data_dir()
  local source = debug.getinfo(1, "S").source:sub(2)
  local this_dir = source:match("(.*)[/\\]") or "."
  -- this_dir = <root>/lua/typewell -> go up two to <root>
  return this_dir .. "/../../data/tagger"
end

-- read a word-list file into a set { word = true }. missing files yield an
-- empty set rather than erroring, so a partial install degrades gracefully.
local function load_wordlist(name)
  local set = {}
  local path = data_dir() .. "/" .. name
  local file = io.open(path, "r")
  if not file then
    return set
  end
  for line in file:lines() do
    -- strip surrounding whitespace
    local word = line:gsub("^%s+", ""):gsub("%s+$", "")
    -- skip blanks and comments
    if word ~= "" and word:sub(1, 1) ~= "#" then
      set[word:lower()] = true
    end
  end
  file:close()
  return set
end

-- word lists are loaded lazily on first classify() so requiring this module
-- (which happens at plugin load, via syntax.lua) costs nothing. parsing the
-- full dictionary only happens once you actually tag a buffer.
local STOPWORDS = {}
local VERBS = {}
local ADJECTIVES = {}
local CONJUNCTIONS = {}
local EXCEPTIONS = {}
local loaded = false

-- (re)read every word list from disk. call M.reload() to pick up edits to the
-- data files without restarting Neovim.
function M.reload()
  STOPWORDS = load_wordlist("stopwords.txt")
  VERBS = load_wordlist("verbs.txt")
  ADJECTIVES = load_wordlist("adjectives.txt")
  CONJUNCTIONS = load_wordlist("conjunctions.txt")
  EXCEPTIONS = load_wordlist("exceptions.txt")
  loaded = true
end

-- load the dictionary the first time it's needed
local function ensure_loaded()
  if not loaded then
    M.reload()
  end
end

-- Suffix-based guesses. Order matters: first match wins.
local SUFFIX_RULES = {
  { pattern = "ly$",  tag = "adverb" },      -- quickly, slowly
  { pattern = "ing$", tag = "verb" },        -- running, thinking
  { pattern = "ery$", tag = "adjective" },   -- watery (before "ed" ambiguity)
  { pattern = "ed$",  tag = "verb" },        -- walked, jumped
  { pattern = "ize$", tag = "verb" },        -- organize
  { pattern = "ise$", tag = "verb" },        -- realise
  { pattern = "ify$", tag = "verb" },        -- clarify
  { pattern = "ate$", tag = "verb" },        -- create, activate
  { pattern = "ous$", tag = "adjective" },   -- famous, curious
  { pattern = "ful$", tag = "adjective" },   -- helpful, careful
  { pattern = "less$", tag = "adjective" },  -- careless
  { pattern = "able$", tag = "adjective" },  -- readable
  { pattern = "ible$", tag = "adjective" },  -- visible
  { pattern = "ive$", tag = "adjective" },   -- active, creative
  { pattern = "al$",  tag = "adjective" },   -- normal, formal
  { pattern = "ic$",  tag = "adjective" },   -- basic, classic
  { pattern = "ish$", tag = "adjective" },   -- reddish
}

-- Classify a single lowercase word into a part of speech, or nil.
-- `enabled` is the config.syntax table so we skip disabled categories early.
function M.classify(word, enabled)
  if #word < 2 then
    return nil
  end
  ensure_loaded()

  if enabled.conjunctions and CONJUNCTIONS[word] then
    return "conjunction"
  end

  -- stopwords short-circuit everything except conjunctions (handled above)
  if STOPWORDS[word] then
    return nil
  end

  if enabled.verbs and VERBS[word] then
    return "verb"
  end
  if enabled.adjectives and ADJECTIVES[word] then
    return "adjective"
  end

  -- known false positives: common nouns whose endings collide with a suffix
  -- rule. dictionary hits above already returned, so this only blocks the
  -- morphological guesses below.
  if EXCEPTIONS[word] then
    return nil
  end

  for _, rule in ipairs(SUFFIX_RULES) do
    if word:find(rule.pattern) then
      local tag = rule.tag
      if tag == "verb" and enabled.verbs then
        return "verb"
      elseif tag == "adjective" and enabled.adjectives then
        return "adjective"
      elseif tag == "adverb" and enabled.adverbs then
        return "adverb"
      elseif tag == "noun" and enabled.nouns then
        return "noun"
      end
      -- suffix matched but that category is disabled: stop looking so we
      -- don't mis-tag with a lower-priority rule
      return nil
    end
  end

  return nil
end

return M
