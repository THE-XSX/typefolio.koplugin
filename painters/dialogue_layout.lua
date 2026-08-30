-- SPDX-FileCopyrightText: Copyright (C) 2026 THE-XSX
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- Typefolio (文笺) - KOReader plugin
-- Released under the GNU Affero General Public License v3.0 or later.
-- See the LICENSE file in the project root for the full license text.

-- `^(.*)painters[/\\]` before the generic directory match, so a spec that dofiles this file
-- by a relative path ("painters/dialogue_layout.lua") resolves the plugin root to "" -- i.e.
-- the cwd it was run from -- instead of to "painters/".
local item_path = debug.getinfo(1, "S").source:sub(2)
local PLUGIN_ROOT = item_path:match("(.*[/\\]typefolio%.koplugin[/\\])")
    or item_path:match("^(.*)painters[/\\]") or item_path:match("(.*[/\\])")
    or "plugins/typefolio.koplugin/"
local TextNodes = dofile(PLUGIN_ROOT .. "core/text_nodes.lua")

local DialogueLayout = {}

local function addRect(rects, x, y, w, h, screen, opacity)
    local x0, y0 = math.max(0, math.floor(x)), math.max(0, math.floor(y))
    local x1 = math.min(screen.w, math.floor(x + w))
    local y1 = math.min(screen.h, math.floor(y + h))
    if x1 > x0 and y1 > y0 then
        table.insert(rects, { x = x0, y = y0, w = x1 - x0, h = y1 - y0, tint = opacity })
    end
end

-- Lazy `.-` spans whole UTF-8 sequences safely. A negated byte class such as
-- `[^”]` must not be used here: ” is E2 80 9D, and CJK codepoints routinely
-- contain the bytes 0x80/0x9D as continuation bytes (一 is E4 B8 80), so the
-- class would terminate mid-character and the match would silently fail.
-- The capture spans the marks as well as the text between them: the marks are
-- part of the utterance on screen, and excluding them scored a bare exclamation
-- ("“咦”") at 0.33 because two of its three characters were the marks.
local PATTERNS = {
    cn = { "(“.-”)", "(「.-」)", "(『.-』)" },
    en = { "(“.-”)", '(".-")' },
    all = { "(“.-”)", "(「.-」)", "(『.-』)", '(".-")' },
}

-- Marking policy: a quote mark is the whole test.
--
-- There was a design here for telling speech from narration -- a coverage ratio, a
-- leading-mark check, an attribution check -- and it was measured: on a careful
-- translation it separated real dialogue from cited words fairly well. It is gone,
-- deliberately. The books this painter exists for are not carefully punctuated. Web
-- fiction routinely gives a bare “…” with no attribution, no colon, and no reliable
-- sentence structure to reason from, so any rule refined enough to exclude 「他说“好”
-- 便走了」 also drops real speech in those books. Recall is worth more than precision
-- here: if there are quote marks, they get marked.
--
-- This also matches what the per-quote path already does. When the document can resolve
-- sub-line geometry, every quoted run is painted regardless of what surrounds it; gating
-- only the whole-line fallback would have made the two paths disagree about the same
-- paragraph depending on the KOReader build.
--
-- The one thing recall is *not* worth: marking text that is not quoted. Where the engine
-- can place quoted runs but fails on one, that run stays unmarked rather than growing into
-- a whole-line box -- see the note at the fallback in build().
local TINT_OPACITY = { light = 0.12, medium = 0.20, strong = 0.30 }

-- Byte ranges of the quoted runs, in reading order. Painting one quote instead
-- of the whole line needs positions, not just the matched strings.
function DialogueLayout.quoteRanges(text, lang)
    if type(text) ~= "string" or text == "" then return {} end
    if not (text:find("“", 1, true) or text:find("「", 1, true) or text:find("『", 1, true) or text:find('"', 1, true)) then
        return {}
    end
    lang = lang or "all"
    local patterns = PATTERNS[lang] or PATTERNS.all
    local found = {}
    for _, pat in ipairs(patterns) do
        local init = 1
        while init <= #text do
            local first, last, inner = text:find(pat, init)
            if not first then break end
            if inner and inner ~= "" then
                table.insert(found, { first = first, last = last })
            end
            init = last + 1
        end
    end
    table.sort(found, function(a, b) return a.first < b.first end)

    -- "all" runs several patterns over the same string, so one utterance can be
    -- matched twice (a stray ASCII quote inside a CJK line does it). Overlaps
    -- must be merged: darkenRect over the same pixels twice tints them twice.
    local merged = {}
    for _, range in ipairs(found) do
        local prev = merged[#merged]
        if prev and range.first <= prev.last then
            if range.last > prev.last then prev.last = range.last end
        else
            table.insert(merged, { first = range.first, last = range.last })
        end
    end
    return merged
end

function DialogueLayout.findQuotes(text, lang)
    local matches = {}
    for _, range in ipairs(DialogueLayout.quoteRanges(text, lang)) do
        table.insert(matches, text:sub(range.first, range.last))
    end
    return matches
end

-- Ratio of the paragraph covered by quoted runs, in bytes (UTF-8 safe because both
-- operands are byte lengths of the same encoding).
--
-- Takes the ranges instead of re-deriving them. quoteRanges runs four patterns over the
-- string with a sort and an overlap merge, and build() already holds the result; this
-- used to re-run all of it and allocate a substring per quote purely to measure their
-- lengths, which the ranges already give.
--
-- `text` is only the denominator, so it may be a trimmed version of the string the
-- ranges were measured on -- trimming moves positions but not lengths.
function DialogueLayout.coverageOf(text, ranges)
    if type(text) ~= "string" or text == "" then return 0 end
    if type(ranges) ~= "table" or #ranges == 0 then return 0 end
    local quoted = 0
    for _, range in ipairs(ranges) do
        quoted = quoted + (range.last - range.first + 1)
    end
    local total = #(text:gsub("%s+", ""))
    if total == 0 then return 0 end
    return math.min(1, quoted / total)
end

function DialogueLayout.quoteCoverage(text, lang)
    return DialogueLayout.coverageOf(text, DialogueLayout.quoteRanges(text, lang))
end

function DialogueLayout.isDialogue(text, lang)
    return #DialogueLayout.quoteRanges(text, lang) > 0
end

-- Returns the text to run quote detection over, where that text begins, and what it covers:
-- "block" for a whole paragraph (offsets are paragraph-wide and may cross text nodes) or
-- "node" for text measured inside a single text node. Geometry resolution needs both,
-- because the xpointer carries the *line's* offset inside its own node and adding that to
-- paragraph-wide offsets lands past the quote -- while treating node-wide offsets as
-- paragraph-wide addresses the wrong node as soon as inline markup splits the paragraph.
local function lineOffset(node)
    local pointer = node.pos0 or node.xpointer
    if type(pointer) ~= "string" then return nil end
    return tonumber(pointer:match("%.(%d+)$"))
end

local function nodeText(node, nodes)
    -- semantic_index derives `text` from the paragraph HTML with entities decoded and
    -- soft hyphens/BOM removed precisely so offsets survive; prefer it over stripping
    -- tags here. Both cover the whole paragraph, so a quote spanning several screen
    -- lines is still matched as one.
    if type(node.text) == "string" and node.text ~= "" then
        return node.text, 0, "block"
    end
    -- Snapshots not built by semantic_index carry only HTML.
    if type(node.html) == "string" and node.html ~= "" then
        local text = node.html:gsub("<[^>]*>", ""):gsub("%s+", " ")
            :gsub("^%s+", ""):gsub("%s+$", "")
        if text ~= "" then return text, 0, "block" end
    end
    -- Fallback: concatenate screen_text of all line nodes belonging to the same
    -- paragraph key. That text starts at the earliest line still on this page, which is
    -- the paragraph's own start only when the paragraph did not begin on the last one.
    --
    -- Grouping is by *text node*, not by paragraph, and has to stay that way: these
    -- offsets are node-relative, and the `dialogue` profile that lands here has no HTML to
    -- convert them with. On a paragraph split by inline markup that means each piece is
    -- scanned on its own, so an utterance wrapped in a <span> is found only if the span's
    -- own piece contains both marks. Missing a tint there is the acceptable half of the
    -- trade; tinting the narration around it is not.
    local pointer = node.pos0 or node.xpointer
    local key = type(pointer) == "string" and pointer:match("^(.*)%.%d+$")
    if key and type(nodes) == "table" then
        local parts = {}
        local origin
        for _, n in ipairs(nodes) do
            local n_pointer = n.pos0 or n.xpointer
            local n_key = type(n_pointer) == "string"
                and n_pointer:match("^(.*)%.%d+$")
            if n_key == key and type(n.screen_text) == "string" and n.screen_text ~= "" then
                table.insert(parts, n.screen_text)
                local offset = lineOffset(n)
                if offset and (not origin or offset < origin) then origin = offset end
            end
        end
        if #parts > 0 then
            return table.concat(parts, ""), origin, "node"
        end
    end
    if type(node.screen_text) == "string" and node.screen_text ~= "" then
        return node.screen_text, nil, "node"
    end
    return "", nil, "node"
end

-- Everything that may sit outside the marks and still leave the line "one utterance":
-- whitespace, the fullwidth indent, and sentence punctuation. Nothing else -- one CJK
-- character or one letter outside the quote is narration, and narration is the thing the
-- whole-box shortcut must not paint. Listing the allowed characters rather than trying to
-- exclude text keeps the failure direction safe: an unlisted character means "consult the
-- engine", never "cover the row".
local OUTSIDE_QUOTE_OK = {}
for char in ([[。，、！？；：…‥·．～—–‐ー・「」『』（）〔〕【】《》〈〉""''"'.,!?;:~-()[]{}]])
    :gmatch("[\1-\127\194-\244][\128-\191]*") do
    OUTSIDE_QUOTE_OK[char] = true
end
OUTSIDE_QUOTE_OK["\227\128\128"] = true       -- U+3000, the fullwidth indent
for _, space in ipairs({ " ", "\t", "\n", "\r", "\194\160" }) do
    OUTSIDE_QUOTE_OK[space] = true
end

-- True when this line is one utterance and nothing else worth separating.
--
-- Painting the whole box, rather than resolving each quoted run, exists for the case
-- where rewriting xpointer offsets into nested Calibre spans dropped short quotes
-- outright ("“轰”" / "“嗖”"). It also saves an engine call per paragraph, which on a page
-- of a dialogue-heavy novel is most of the paragraphs on it.
--
-- This used to be a coverage ratio, `quoted / non-space >= 0.85`, and the 15% it tolerated
-- was the bug reported on 2026-08-24: 《窄门》 p.21 wraps its utterance in a <span>, the
-- stitched unit picked up the following node's first three characters (「母亲大」), 31 of 34
-- characters were quoted, and the shortcut covered both rows -- narration included -- without
-- ever asking the engine. A ratio cannot tell "the closing 。 fell outside the mark" from
-- "the speech tag fell inside the unit"; on a long utterance both are a few percent.
--
-- So the test is now categorical: exactly one quoted run, and what is left over must be
-- punctuation or space. 「“你来了”。」 keeps its free ride, 「“…！”母亲大」 does not and goes
-- to the resolver, which either places the run or leaves it unmarked. Same call as the rest
-- of this painter -- a missing tint is cosmetic, a tinted line of narration is the defect.
--
-- Takes the ranges build() already computed; the text-only wrapper below is for callers
-- that do not have them.
function DialogueLayout.isSingleUtterance(text, ranges)
    if type(text) ~= "string" or text == "" then return false end
    if type(ranges) ~= "table" or #ranges ~= 1 then return false end
    local range = ranges[1]
    -- Ranges are positions in `text`, so the residue is taken before any trimming.
    local residue = text:sub(1, range.first - 1) .. text:sub(range.last + 1)
    for char in residue:gmatch("[\1-\127\194-\244][\128-\191]*") do
        if not OUTSIDE_QUOTE_OK[char] then return false end
    end
    return true
end

function DialogueLayout.isPureQuoteLine(text, lang)
    return DialogueLayout.isSingleUtterance(text, DialogueLayout.quoteRanges(text, lang))
end

function DialogueLayout.build(snapshot, options)
    options = options or {}
    if options.enabled ~= true then return {} end
    local screen = snapshot and snapshot.page and snapshot.page.viewport
    if not screen then return {} end

    local rects = {}
    local thickness = math.max(1, tonumber(options.thickness) or 1)
    local mode = options.mode or "tint"
    -- Vertical inset, in already-scaled pixels: how far each mark keeps off the top and
    -- bottom edges of the line box.
    --
    -- One value for all three modes, because they mean the same thing -- the tint stops
    -- short of the edge, the underline lifts off the baseline gap, the side bar shortens at
    -- both ends -- and a reader who wants tighter marks wants them tighter everywhere.
    --
    -- Line boxes come from the engine and include the line's leading, so a tint drawn to the
    -- full box height touches the row above and below on tight line spacing, which is what
    -- reads as "the highlight is too tall". Trimming is the only fix available to a painter:
    -- it draws after layout, so it cannot change what the box is, only what it fills.
    --
    -- Clamped, not just floored, so a large inset on a short line cannot invert the box or
    -- collapse it to nothing: at most 40% off each end, which always leaves a fifth of the
    -- row visible.
    local function insetOf(box)
        local requested = math.max(0, tonumber(options.vertical_inset) or 0)
        return math.min(requested, math.floor(box.h * 0.4))
    end
    -- Supplied by the painter; nil in unit tests and whenever the document
    -- cannot resolve sub-line geometry, in which case we mark whole lines.
    local resolver = options.quote_boxes
    -- Paragraphs already handled, keyed by element path. See the dedup note in
    -- the loop below.
    local seen = {}

    local opacity = TINT_OPACITY[options.tint_level] or TINT_OPACITY.light

    -- Emit the marks for one box, whether it covers a whole line or a single
    -- quoted run.
    local function emit(box)
        local inset = insetOf(box)
        if mode == "underline" then
            local before = #rects
            -- Measured up from the box's bottom edge, so the inset lifts the rule instead
            -- of thinning it -- `thickness` stays exactly what the reader asked for.
            addRect(rects, box.x, box.y + box.h - inset - thickness,
                box.w, thickness, screen, nil)
            return #rects > before
        else
            -- Tint must blend, not fill: a solid rect would black out the text.
            local before = #rects
            addRect(rects, box.x, box.y + inset, box.w, box.h - inset * 2, screen, opacity)
            return #rects > before
        end
    end

    -- semantic_index exposes normalized samples as `nodes`; `semantics` is the
    -- raw BookContext field and is absent here.
    for _, node in ipairs(snapshot.nodes or {}) do
        local box = node.box
        if box then
            local text, text_origin, text_scope = nodeText(node, snapshot.nodes)
            -- Scanned once and shared by everything below. The quote sweep runs four
            -- patterns over the string plus a sort and an overlap merge, and this loop
            -- used to trigger it three times per paragraph -- once to ask whether there
            -- was a quote at all, once inside the single-utterance check, once for the
            -- resolver -- on every visible line of every page.
            local ranges = DialogueLayout.quoteRanges(text, options.lang)
            if #ranges > 0 then
                if mode == "side_bar" then
                    -- A margin rule is inherently line-level; there is no
                    -- sensible per-quote equivalent. It does not go through emit(),
                    -- so it applies the inset itself -- shortening the rule at both
                    -- ends, which is the vertical meaning the other two modes have.
                    local inset = insetOf(box)
                    addRect(rects, box.x - thickness * 3, box.y + inset,
                        thickness, box.h - inset * 2, screen, nil)
                else
                    -- Mark only the quoted runs when the document can resolve
                    -- their geometry, so narration and speech tags on the same
                    -- line stay unmarked. Whole-line boxes remain the fallback.
                    --
                    -- `nodes` are per line, so a paragraph running over three
                    -- lines appears three times while quoteRanges() describes
                    -- the whole paragraph. Resolving once per line would ask
                    -- the engine for the same boxes repeatedly and, worse,
                    -- darken those pixels once per line. So key on whatever the
                    -- scanned text covers -- the paragraph when it came from the
                    -- paragraph's own text, the text node when the lines were
                    -- stitched per node -- and treat the first line of that unit
                    -- as covering all of it. Keying a paragraph-wide scan on the
                    -- text node instead splits one paragraph into one unit per
                    -- inline span, and every one of them pays again.
                    local pointer = node.pos0 or node.xpointer
                    local key
                    if type(pointer) == "string" then
                        key = text_scope == "block" and TextNodes.blockPath(pointer)
                            or pointer:match("^(.*)%.%d+$")
                    end
                    local state = key and seen[key]
                    if state ~= "quoted" then
                        local painted = false
                        local pure = DialogueLayout.isSingleUtterance(text, ranges)
                        local used_subline = false
                        if pure then
                            painted = emit(box) and true or false
                        elseif resolver and state == nil then
                            for _, range in ipairs(ranges) do
                                local boxes = resolver(node, range, text, text_origin, text_scope)
                                if type(boxes) == "table" then
                                    for _, quote_box in ipairs(boxes) do
                                        if emit(quote_box) then
                                            painted = true
                                            used_subline = true
                                        end
                                    end
                                end
                            end
                        end
                        -- No whole-line consolation prize when a resolver exists.
                        --
                        -- Reported from the device on 2026-08-22: on an edition whose
                        -- utterances are wrapped in <span class="dialogue">, the tint
                        -- covered the narration too and stopped exactly at the span. The
                        -- resolver was handed a pointer it could not place, returned
                        -- nothing, and this line tinted the whole row instead -- on every
                        -- row keyed to that text node. A line box is only honest when
                        -- there is no way to do better, i.e. on a build with no sub-line
                        -- geometry at all; when the geometry exists and the run cannot be
                        -- placed, the run goes unmarked. Losing a tint is cosmetic,
                        -- tinting narration is wrong, and emphasis_layout has been making
                        -- this same call for the same reason.
                        if not painted and not resolver then
                            painted = emit(box) and true or painted
                        end
                        -- Sub-line geometry may already cover later rows of the
                        -- same paragraph, so only those are suppressed. Whole-line
                        -- fallbacks must still run on every visible row.
                        if key then
                            seen[key] = (painted and used_subline) and "quoted" or "fallback"
                        end
                    end
                end
            end
        end
    end
    return rects
end

return DialogueLayout
