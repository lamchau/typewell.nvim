-- unit tests for the part-of-speech classifier.

local tagger = require("typewell.tagger")

-- enable every category so the classifier's full behavior is exercised
local ALL = {
  verbs = true,
  adjectives = true,
  nouns = true,
  adverbs = true,
  conjunctions = true,
}

describe("tagger.classify", function()
  it("tags irregular verbs from the dictionary", function()
    assert.equals("verb", tagger.classify("walked", ALL))
    assert.equals("verb", tagger.classify("wrote", ALL))
    assert.equals("verb", tagger.classify("is", ALL))
  end)

  it("tags verbs by suffix", function()
    assert.equals("verb", tagger.classify("running", ALL))
    assert.equals("verb", tagger.classify("organize", ALL))
    assert.equals("verb", tagger.classify("activate", ALL))
    assert.equals("verb", tagger.classify("clarify", ALL))
  end)

  it("tags adjectives from the dictionary", function()
    assert.equals("adjective", tagger.classify("good", ALL))
    assert.equals("adjective", tagger.classify("bright", ALL))
  end)

  it("tags adjectives by suffix", function()
    assert.equals("adjective", tagger.classify("beautiful", ALL))
    assert.equals("adjective", tagger.classify("famous", ALL))
    assert.equals("adjective", tagger.classify("readable", ALL))
    assert.equals("adjective", tagger.classify("active", ALL))
  end)

  it("tags adverbs by the -ly suffix", function()
    assert.equals("adverb", tagger.classify("quickly", ALL))
    assert.equals("adverb", tagger.classify("slowly", ALL))
  end)

  it("tags conjunctions", function()
    assert.equals("conjunction", tagger.classify("because", ALL))
    assert.equals("conjunction", tagger.classify("although", ALL))
  end)

  it("ignores stopwords", function()
    assert.is_nil(tagger.classify("the", ALL))
    assert.is_nil(tagger.classify("of", ALL))
    assert.is_nil(tagger.classify("with", ALL))
  end)

  it("ignores single-character words", function()
    assert.is_nil(tagger.classify("a", ALL))
    assert.is_nil(tagger.classify("x", ALL))
  end)

  it("respects disabled categories", function()
    local verbs_only = { verbs = true, adjectives = false, adverbs = false, nouns = false, conjunctions = false }
    assert.equals("verb", tagger.classify("running", verbs_only))
    -- adjective suffix matches but the category is off -> nil, and it must
    -- NOT fall through to a lower-priority rule
    assert.is_nil(tagger.classify("beautiful", verbs_only))
    assert.is_nil(tagger.classify("quickly", verbs_only))
  end)

  it("prioritizes conjunctions over the stopword filter", function()
    -- "and"/"but" are both stopwords and conjunctions; conjunction wins
    assert.equals("conjunction", tagger.classify("and", ALL))
    assert.equals("conjunction", tagger.classify("but", ALL))
  end)

  it("loads its dictionary from the data files", function()
    -- words that only exist in the richer text-file dictionary, not the old
    -- inline lists — proves the files are found and parsed
    assert.equals("verb", tagger.classify("swum", ALL))
    assert.equals("adjective", tagger.classify("brave", ALL))
    -- exceptions.txt entries suppress suffix mis-tags
    assert.is_nil(tagger.classify("hospital", ALL))
    assert.is_nil(tagger.classify("morning", ALL))
  end)

  it("reload() re-reads the word lists without error", function()
    tagger.reload()
    -- still classifies correctly after a reload
    assert.equals("verb", tagger.classify("walked", ALL))
  end)
end)
