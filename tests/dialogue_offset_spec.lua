-- SPDX-FileCopyrightText: Copyright (C) 2026 THE-XSX
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- Typefolio (文笺) - KOReader plugin
-- Released under the GNU Affero General Public License v3.0 or later.
-- See the LICENSE file in the project root for the full license text.

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
        quote_boxes = function(n, range, text, text_origin, text_scope)
            return BookContext.boxesForRange(context, n.pos0 or n.xpointer,
                range.first, range.last, text, text_origin, text_scope, n.html)
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
        quote_boxes = function(n, range, text, text_origin, text_scope)
            return BookContext.boxesForRange(context, n.pos0 or n.xpointer,
                range.first, range.last, text, text_origin, text_scope, n.html)
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

-- ------------------------------------------------ a paragraph split by inline markup
--
-- Reported from the device on 2026-08-22: on a Calibre edition whose utterances are
-- wrapped in <span class="dialogue">, the tint covered the narration as well, and stopped
-- exactly at the span. That boundary is the whole story. Inline markup splits a paragraph
-- into several text nodes, crengine numbers them among their text siblings, and the
-- paragraph-wide offset of the quote is past the end of the first node as soon as the
-- quote is reached -- so the engine placed nothing and the painter fell back to the line
-- box. Any <em>, <b>, footnote link or Calibre <span class="calibreN"> does it; a plain
-- single-text-node <p>, which is all the fixtures above are, never could.
--
-- The stub below is the part that makes this testable: it refuses an offset past the end
-- of its node, the way crengine does. A permissive stub answers every pointer and the
-- fixture passes while the device does not.

local PARA = "/body/DocFragment[2]/body/p[2]"
local NODE1 = PARA .. "/text()[1]"      -- the narration before the span
local QNODE = PARA .. "/span[1]/text()[1]" -- the utterance, inside the span
local NODE2 = PARA .. "/text()[2]"      -- the tail after the span

local LINE_BOX = { x = 40, y = 100, w = 500, h = 30 }
local RUN_BOX = { x = 40, y = 100, w = 120, h = 30 }

local function spanHTML(tail)
    return "<p>" .. NARRATION .. '<span class="dialogue">' .. QUOTE .. "</span>"
        .. (tail or TAIL) .. "</p>"
end

-- A document that knows how long each of its text nodes is.
local function domContext(nodes, log, html)
    return {
        ui = {
            document = {
                getScreenBoxesFromPositions = function(_, xp0, xp1)
                    table.insert(log.asked, { xp0 = xp0, xp1 = xp1 })
                    local function resolves(xp)
                        local path, offset = xp:match("^(.*)%.(%d+)$")
                        local length = path and nodes[path]
                        -- Offset == length is the node's end and is legal; past it the
                        -- pointer does not resolve and no rect comes back.
                        return length ~= nil and tonumber(offset) <= length
                    end
                    if not (resolves(xp0) and resolves(xp1)) then return {} end
                    return { { x = RUN_BOX.x, y = RUN_BOX.y, w = RUN_BOX.w, h = RUN_BOX.h } }
                end,
                getHTMLFromXPointer = function(_, xp, _, from_final_parent)
                    table.insert(log.html, { xp = xp, from_final_parent = from_final_parent })
                    return html
                end,
            },
        },
        _page = function() return { viewport = { w = 600, h = 800 } } end,
    }
end

local function paint(nodes, lengths, html)
    local log = { asked = {}, html = {} }
    local context = domContext(lengths, log, html)
    local rects = DialogueLayout.build({
        page = { viewport = { w = 600, h = 800 } },
        nodes = nodes,
    }, {
        enabled = true, mode = "tint", lang = "all", thickness = 1,
        -- Wired exactly as context_painter wires it, scope and markup included: the whole
        -- point of these fixtures is what happens when the offsets and the pointer are
        -- measured against different strings.
        quote_boxes = function(n, range, text, text_origin, text_scope)
            return BookContext.boxesForRange(context, n.pos0 or n.xpointer,
                range.first, range.last, text, text_origin, text_scope, n.html)
        end,
    })
    return rects, log
end

local function paintedWholeLine(rects)
    for _, rect in ipairs(rects) do
        if rect.w == LINE_BOX.w and rect.h == LINE_BOX.h then return true end
    end
    return false
end

local function askedInside(log, node_path)
    for _, entry in ipairs(log.asked) do
        if entry.xp0:find(node_path, 1, true) then return true end
    end
    return false
end

do
    -- Two screen lines, as on the device: the second one starts in the narration node and
    -- runs through the span into the tail. Both lines key on NODE1, so this is the pair
    -- that got tinted end to end.
    local lengths = {
        [NODE1] = 10, [QNODE] = 5, [NODE2] = 12,
    }
    local rects, log = paint({
        { box = { x = LINE_BOX.x, y = 100, w = LINE_BOX.w, h = 30 },
          pos0 = NODE1 .. ".0", screen_text = NARRATION:sub(1, 18) },  -- 6 chars
        { box = { x = LINE_BOX.x, y = 130, w = LINE_BOX.w, h = 30 },
          pos0 = NODE1 .. ".6",
          screen_text = NARRATION:sub(19) .. QUOTE .. TAIL:sub(1, 6) },
    }, lengths, spanHTML())

    check("the utterance is addressed in the node it actually lives in",
        askedInside(log, QNODE))
    check("the narration is not tinted along with it", not paintedWholeLine(rects))
    check("something was tinted", #rects > 0)
    check("the paragraph's markup is read at most once", #log.html <= 1)
end

do
    -- Same paragraph, this time with node.text/node.html present (the "full" profile).
    -- The line being resolved sits *after* the span, so its node is text()[2] while the
    -- offsets are measured over the whole paragraph. Those offsets resolve inside a tail
    -- this long -- the engine answers, with geometry from the wrong words. Nothing on
    -- screen says the tint is wrong, which is why the pointer has to be rejected before
    -- it is asked about.
    local long_tail = TAIL .. TAIL          -- 24 characters
    local lengths = { [NODE1] = 10, [QNODE] = 5, [NODE2] = 24 }
    local rects, log = paint({
        { box = { x = LINE_BOX.x, y = 100, w = LINE_BOX.w, h = 30 },
          pos0 = NODE2 .. ".2",
          text = NARRATION .. QUOTE .. long_tail,
          html = spanHTML(long_tail),
          screen_text = long_tail },
    }, lengths, spanHTML(long_tail))

    check("a pointer into the wrong text node is never asked about",
        not askedInside(log, NODE2))
    check("the utterance is addressed in the span node instead", askedInside(log, QNODE))
    check("and no line box is tinted as a consolation", not paintedWholeLine(rects))
end

do
    -- The common case must stay free: one text node, offsets valid, no markup to read.
    local lengths = { [PARA .. "/text()"] = 27 }
    local rects, log = paint({
        { box = { x = LINE_BOX.x, y = 100, w = LINE_BOX.w, h = 30 },
          pos0 = PARA .. "/text().0", text = PARAGRAPH,
          html = "<p>" .. PARAGRAPH .. "</p>", screen_text = PARAGRAPH },
    }, lengths, "<p>" .. PARAGRAPH .. "</p>")
    check("a single-text-node paragraph resolves without reading any markup",
        #log.html == 0)
    check("and it resolves in one engine call", #log.asked == 1)
    check("its quote is still tinted", #rects > 0 and not paintedWholeLine(rects))
end

print(string.format("dialogue_offset_spec: %s (%d checks, %d failures)",
    failures == 0 and "ok" or "FAILED", checks, failures))
if failures > 0 then error("dialogue_offset_spec failed", 0) end
