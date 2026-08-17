-- Where the dialogue painter asks for quote geometry.
--
-- The painter runs quote detection over the whole paragraph, so a quote split across two
-- screen lines is still found. But boxesForRange was written for the other case: it adds
-- the *line's* own start offset (the number after the dot in the xpointer) to the offsets
-- it is given. Feeding it paragraph-relative offsets therefore double-counted, and the
-- tint landed that many characters too far to the right -- but only on a paragraph
-- continued from the previous page, because the first line of a paragraph starts at
-- offset 0 where the two conventions agree. The top paragraph of a page is exactly the
-- common case.
--
-- Both modules load without KOReader.
--
-- Run from the plugin root:
--   python3 runlua.py <plugin_dir> <plugin_dir>/tests/dialogue_offset_spec.lua

local function pluginRoot()
    local here = debug.getinfo(1, "S").source:sub(2)
    local root = here:match("^(.*[/\\])tests[/\\][^/\\]*$")
    if root and root:find("typefolio%.koplugin") then return root end
    return "../typefolio.koplugin/"
end
local ROOT = pluginRoot()

local DialogueLayout = dofile(ROOT .. "painters/dialogue_layout.lua")
local BookContext = dofile(ROOT .. "core/book_context.lua")

local checks, failures = 0, 0
local function check(label, ok)
    checks = checks + 1
    if ok then
        print("ok " .. label)
    else
        failures = failures + 1
        print("FAIL " .. label)
    end
end

local NARRATION = "前面这段叙述有十一字"      -- 10 characters
local QUOTE = "“你好啊”"
local TAIL = "后面还有一段不算短的叙述"
local PARAGRAPH = NARRATION .. QUOTE .. TAIL
local LINE_START = 11                        -- this line begins at char 11 of the node
local BASE = "/body/DocFragment[2]/body/p"

-- What the answer has to be: the 0-based character index of the opening quote mark
-- inside the paragraph, and of the closing mark, both measured from the node start.
local QUOTE_FIRST_CHAR = BookContext.charCount(NARRATION, #NARRATION)
local QUOTE_LAST_CHAR = QUOTE_FIRST_CHAR + BookContext.charCount(QUOTE, #QUOTE)

check("the fixture puts the quote 10 characters in", QUOTE_FIRST_CHAR == 10)
check("the fixture's quote is 5 characters long", QUOTE_LAST_CHAR - QUOTE_FIRST_CHAR == 5)
check("the fixture is not almost entirely quoted (that path skips the resolver)",
    not DialogueLayout.isPureQuoteLine(PARAGRAPH, "all"))

-- A document that records what it was asked for instead of resolving anything.
local function recordingContext(asked)
    return {
        ui = {
            document = {
                getScreenBoxesFromPositions = function(_, xp0, xp1)
                    table.insert(asked, { xp0 = xp0, xp1 = xp1 })
                    return { { x = 0, y = 0, w = 10, h = 10 } }
                end,
            },
        },
        _page = function() return { viewport = { w = 600, h = 800 } } end,
    }
end

local function runBuild(node)
    local asked = {}
    local context = recordingContext(asked)
    local snapshot = {
        page = { viewport = { w = 600, h = 800 } },
        nodes = { node },
    }
    DialogueLayout.build(snapshot, {
        enabled = true,
        mode = "tint",
        lang = "all",
        thickness = 1,
        quote_boxes = function(n, range, text, text_scope)
            return BookContext.boxesForRange(context, n.pos0 or n.xpointer,
                range.first, range.last, text, text_scope)
        end,
    })
    return asked
end

local function offsetsOf(entry)
    return tonumber(entry.xp0:match("%.(%d+)$")), tonumber(entry.xp1:match("%.(%d+)$"))
end

-- ------------------------------------------- a paragraph continued from the last page

do
    local asked = runBuild{
        box = { x = 40, y = 100, w = 500, h = 30 },
        pos0 = BASE .. "." .. LINE_START,
        text = PARAGRAPH,
        html = "<p>" .. PARAGRAPH .. "</p>",
        screen_text = QUOTE .. TAIL,
    }
    check("the resolver was asked once", #asked == 1)
    local first, last = offsetsOf(asked[1])
    check("the quote's start is measured from the node, not the line (got "
        .. tostring(first) .. ")", first == QUOTE_FIRST_CHAR)
    check("the quote's end likewise (got " .. tostring(last) .. ")",
        last == QUOTE_LAST_CHAR)
    -- The specific wrong answer the old code produced.
    check("the line's own start offset is not added on top",
        first ~= QUOTE_FIRST_CHAR + LINE_START)
    check("the element path is preserved",
        asked[1].xp0:match("^(.*)%.%d+$") == BASE)
end

-- ------------------------------------------------- a paragraph that starts on this page

do
    local asked = runBuild{
        box = { x = 40, y = 100, w = 500, h = 30 },
        pos0 = BASE .. ".0",
        text = PARAGRAPH,
        screen_text = PARAGRAPH,
    }
    local first = offsetsOf(asked[1])
    check("a first line is unaffected (it always was)", first == QUOTE_FIRST_CHAR)
end

-- ------------------------------------------------------------- line-scoped text still adds

do
    -- No text and no html: nodeText stitches together the screen_text of every line of
    -- this paragraph still on the page. That text starts at the earliest of those lines,
    -- so its offset -- not zero, and not necessarily this line's -- is the right base.
    -- This is the case boxesForRange was originally written for.
    local line_text = QUOTE .. TAIL
    local asked = runBuild{
        box = { x = 40, y = 100, w = 500, h = 30 },
        pos0 = BASE .. "." .. LINE_START,
        screen_text = line_text,
    }
    check("the stitched fallback was resolved", #asked == 1)
    local first = offsetsOf(asked[1])
    check("stitched text is measured from the earliest visible line (got "
        .. tostring(first) .. ")", first == LINE_START)
end

do
    -- Two lines of one paragraph, the first starting at char 11. Offsets computed over
    -- the pair must count from 11, whichever line is being resolved.
    local asked = {}
    local context = recordingContext(asked)
    local snapshot = {
        page = { viewport = { w = 600, h = 800 } },
        nodes = {
            { box = { x = 40, y = 100, w = 500, h = 30 }, pos0 = BASE .. "." .. LINE_START,
              screen_text = NARRATION },
            { box = { x = 40, y = 130, w = 500, h = 30 },
              pos0 = BASE .. "." .. (LINE_START + 10), screen_text = QUOTE .. TAIL },
        },
    }
    DialogueLayout.build(snapshot, {
        enabled = true, mode = "tint", lang = "all", thickness = 1,
        quote_boxes = function(n, range, text, text_origin)
            return BookContext.boxesForRange(context, n.pos0 or n.xpointer,
                range.first, range.last, text, text_origin)
        end,
    })
    check("a two-line paragraph resolves once", #asked == 1)
    local first = offsetsOf(asked[1])
    check("the second line's own offset is not used as the base (got "
        .. tostring(first) .. ")", first == LINE_START + QUOTE_FIRST_CHAR)
end

-- --------------------------------------------------------------- the origin itself

do
    local seen = {}
    local snapshot = {
        page = { viewport = { w = 600, h = 800 } },
        nodes = {
            { box = { x = 0, y = 0, w = 100, h = 20 }, pos0 = BASE .. ".5",
              text = PARAGRAPH, screen_text = QUOTE },
        },
    }
    DialogueLayout.build(snapshot, {
        enabled = true, mode = "tint", lang = "all", thickness = 1,
        quote_boxes = function(_, _, text, text_origin)
            table.insert(seen, { text = text, origin = text_origin })
            return nil
        end,
    })
    check("paragraph text is reported as starting at the node's own start",
        #seen > 0 and seen[1].origin == 0 and seen[1].text == PARAGRAPH)

    -- node.text is preferred over stripping node.html by hand: semantic_index builds it
    -- with entities decoded and soft hyphens removed so the offsets stay true.
    local prefer = {}
    DialogueLayout.build({
        page = { viewport = { w = 600, h = 800 } },
        nodes = {
            { box = { x = 0, y = 0, w = 100, h = 20 }, pos0 = BASE .. ".0",
              text = PARAGRAPH, html = "<p>" .. NARRATION .. "“别的”" .. TAIL .. "</p>",
              screen_text = QUOTE },
        },
    }, {
        enabled = true, mode = "tint", lang = "all", thickness = 1,
        quote_boxes = function(_, _, text) table.insert(prefer, text); return nil end,
    })
    check("node.text wins over a hand-stripped node.html",
        #prefer > 0 and prefer[1] == PARAGRAPH)
end

print(string.format("dialogue_offset_spec: %s (%d checks, %d failures)",
    failures == 0 and "ok" or "FAILED", checks, failures))
if failures > 0 then error("dialogue_offset_spec failed", 0) end
