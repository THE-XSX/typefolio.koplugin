-- SPDX-FileCopyrightText: Copyright (C) 2026 THE-XSX
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- Typefolio (文笺) - KOReader plugin
-- Released under the GNU Affero General Public License v3.0 or later.
-- See the LICENSE file in the project root for the full license text.

-- Emphasis dots (着重号) under emphasized runs.
--
-- The test used to be "does this node's HTML contain an emphasis tag", and the answer
-- was applied to the node's box. Those two facts are not about the same thing:
-- semantic nodes are *screen lines*, while `html` is the parent paragraph's markup,
-- shared by every line of that paragraph (book_context caches it per element path
-- exactly so). One <strong> word therefore dotted every line of the paragraph, full
-- width -- and <b>/<strong> are common in Chinese web fiction, so a page could come
-- back with a few hundred dot rects, none of them under the emphasized words.
--
-- So the run has to be located inside the paragraph text and turned into geometry, the
-- same way the dialogue painter places a quote: byte range -> xpointer offsets ->
-- getScreenBoxesFromPositions, supplied by the painter as `options.emphasis_boxes` and
-- deduplicated per paragraph rather than per line.
--
-- Cost, per page turn:
--   * no emphasis on the page (the common case): unchanged -- one plain find per node
--     over HTML that is already in memory, no engine call, no rects.
--   * whole paragraph emphasized: no engine call at all. The 85% coverage shortcut
--     keeps the old line-box path, which is the one case where it was right.
--   * a word or two emphasized: one getScreenBoxesFromPositions per run per paragraph
--     (not per line), and ~2-8 dots instead of ~40 per line of the paragraph.
-- When geometry cannot be resolved -- no resolver, or the engine cannot place the
-- offsets -- a partial run is left unmarked. Dotting the whole line instead would put
-- the mark under narration, which is worse than an absent mark.
local EmphasisLayout = {}

-- Matched by tag name only: a bare "<i" also hits <img>, "<u" hits <ul>, "<b" hits
-- <br> and <blockquote>.
local EMPHASIS_TAGS = { "em", "i", "strong", "b", "u" }

-- A paragraph this thoroughly emphasized is emphasized as a whole, so its line boxes
-- are the right thing to dot.
--
-- The dialogue painter used to share this constant and no longer does: a ratio there let the
-- narration after a closing quote be tinted (see its isSingleUtterance comment), so it now
-- asks whether anything but punctuation sits outside the run. That test does not transfer
-- here unchanged -- emphasis ranges come from tags rather than paired marks, and a partly
-- emphasized paragraph is ordinary -- but the failure mode is the same shape: the 15% this
-- bar tolerates gets dots it did not ask for. Worth measuring on a real book before moving.
local WHOLE_PARAGRAPH_COVERAGE = 0.85

local function addRect(rects, x, y, w, h, screen)
    local x0, y0 = math.max(0, math.floor(x)), math.max(0, math.floor(y))
    local x1 = math.min(screen.w, math.floor(x + w))
    local y1 = math.min(screen.h, math.floor(y + h))
    if x1 > x0 and y1 > y0 then
        table.insert(rects, { x = x0, y = y0, w = x1 - x0, h = y1 - y0 })
    end
end

-- Plain text of an HTML fragment, normalized the way semantic_index normalizes
-- node.text: tags out, whitespace collapsed, ends trimmed. Entities are deliberately
-- left encoded -- a run containing one fails to locate below and is skipped, which
-- under-marks rather than marking the wrong words.
local function plainText(html)
    local text = html
    if text:find("<", 1, true) then text = text:gsub("<[^>]*>", "") end
    return (text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Byte ranges of the emphasized runs inside `text`, in reading order, overlaps merged.
--
-- `text` must be the paragraph text the caller will hand to the geometry resolver:
-- offsets are only meaningful against that exact string.
function EmphasisLayout.emphasisRanges(html, text)
    if type(html) ~= "string" or html == "" then return {} end
    if type(text) ~= "string" or text == "" then return {} end

    -- Positions are taken from the lowercased copy and applied to the original, so the
    -- two must agree byte for byte. :lower() maps A-Z only, one byte to one byte, and
    -- leaves UTF-8 continuation bytes alone.
    local lowered = html:lower()
    local found = {}

    for _, tag in ipairs(EMPHASIS_TAGS) do
        local init = 1
        while true do
            local open_first = lowered:find("<" .. tag .. "[%s>]", init)
            if not open_first then break end
            local open_end = lowered:find(">", open_first, true)
            local close_first = open_end and lowered:find("</%s*" .. tag .. "%s*>", open_end)
            if not (open_end and close_first) then break end

            local inner = plainText(html:sub(open_end + 1, close_first - 1))
            if inner ~= "" then
                -- Search from where the run sits in the paragraph, not from the start:
                -- a one-character run ("他") occurs all over a paragraph and the first
                -- hit is rarely the emphasized one. The hint can overshoot when an
                -- entity precedes the run (node.text has it decoded, this prefix does
                -- not), so an unfound run is retried from the beginning.
                local hint = #plainText(html:sub(1, open_first - 1))
                local from = math.max(1, hint - 2)
                local first, last = text:find(inner, from, true)
                if not first and from > 1 then
                    first, last = text:find(inner, 1, true)
                end
                if first then
                    table.insert(found, { first = first, last = last })
                end
            end
            init = close_first + 1
        end
    end

    if #found < 2 then return found end
    table.sort(found, function(a, b) return a.first < b.first end)

    -- Nested markup (<strong><em>x</em></strong>) reports the same run twice, and one
    -- range painted twice is one row of dots painted twice.
    local merged = {}
    for _, range in ipairs(found) do
        local prev = merged[#merged]
        if prev and range.first <= prev.last + 1 then
            if range.last > prev.last then prev.last = range.last end
        else
            table.insert(merged, { first = range.first, last = range.last })
        end
    end
    return merged
end

-- Share of the paragraph's non-space bytes covered by emphasized runs.
function EmphasisLayout.coverageOf(text, ranges)
    if type(text) ~= "string" or text == "" then return 0 end
    if type(ranges) ~= "table" or #ranges == 0 then return 0 end
    local marked = 0
    for _, range in ipairs(ranges) do
        marked = marked + (range.last - range.first + 1)
    end
    local total = #(text:gsub("%s+", ""))
    if total == 0 then return 0 end
    return math.min(1, marked / total)
end

local function nodeText(node)
    if type(node.text) == "string" and node.text ~= "" then return node.text end
    if type(node.html) == "string" and node.html ~= "" then
        local text = plainText(node.html)
        if text ~= "" then return text end
    end
    return ""
end

local function hasEmphasisTag(lowered_html)
    for _, tag in ipairs(EMPHASIS_TAGS) do
        if lowered_html:find("<" .. tag .. "[%s>]") then return true end
    end
    return false
end

-- One entry per paragraph, in first-seen order, carrying every visible line box of it.
-- Grouping first is what makes "resolve the run once, not once per line" structural
-- rather than a side effect of iteration order, and it gives the run boxes something to
-- be sanity-checked against.
local function groupByElement(nodes)
    local groups, order = {}, {}
    for index, sample in ipairs(nodes or {}) do
        if sample.box then
            local pointer = sample.pos0 or sample.xpointer
            local key = type(pointer) == "string" and pointer:match("^(.*)%.%d+$") or nil
            -- No pointer means nothing links this node to its neighbours; keep it alone
            -- rather than merging unrelated nodes under one key.
            local group = key and groups[key]
            if not group then
                group = { sample = sample, boxes = {} }
                groups[key or ("#" .. index)] = group
                table.insert(order, group)
            end
            table.insert(group.boxes, sample.box)
        end
    end
    return order
end

-- A resolved run has to land on one of the paragraph's own lines. Paragraph-wide byte
-- offsets are spliced onto the xpointer of whichever text node the line probe hit, and
-- a paragraph containing <em> has more than one text node -- so the arithmetic can
-- address a position outside the run's node and come back with geometry from somewhere
-- else on the page. Dots in the wrong paragraph are worse than no dots.
local function onOwnLine(run_box, boxes)
    for _, line in ipairs(boxes) do
        if run_box.y + run_box.h > line.y and run_box.y < line.y + line.h
                and run_box.w <= line.w then
            return true
        end
    end
    return false
end

function EmphasisLayout.build(snapshot, options)
    options = options or {}
    if options.enabled ~= true then return {} end
    local screen = snapshot and snapshot.page and snapshot.page.viewport
    if not screen then return {} end

    local rects = {}
    local dot_size = math.max(1, tonumber(options.size) or 2)
    local gap = math.max(4, tonumber(options.gap) or 12)
    -- Supplied by the painter; nil in unit tests and whenever the document cannot
    -- resolve sub-line geometry.
    local resolver = options.emphasis_boxes

    local function dotsUnder(box)
        local y_dot = box.y + box.h + 1
        local before = #rects
        for x_dot = box.x + gap / 2, box.x + box.w - gap / 4, gap do
            addRect(rects, x_dot - dot_size / 2, y_dot, dot_size, dot_size, screen)
        end
        return #rects > before
    end

    -- semantic_index exposes normalized samples as `nodes`; `semantics` is the raw
    -- BookContext field and is absent here.
    for _, group in ipairs(groupByElement(snapshot.nodes)) do
        local sample = group.sample
        -- semanticKind() does not emit "emphasis" today, so this only fires for
        -- snapshots built by hand; a node that *is* the run needs no locating.
        if sample.kind == "emphasis" then
            for _, box in ipairs(group.boxes) do dotsUnder(box) end
        else
            local html = type(sample.html) == "string" and sample.html or ""
            if html ~= "" and hasEmphasisTag(html:lower()) then
                local text = nodeText(sample)
                local ranges = EmphasisLayout.emphasisRanges(html, text)
                if #ranges > 0 then
                    if EmphasisLayout.coverageOf(text, ranges) >= WHOLE_PARAGRAPH_COVERAGE then
                        -- All of it is emphasized, so every line of it gets dots and the
                        -- engine is not consulted at all.
                        for _, box in ipairs(group.boxes) do dotsUnder(box) end
                    elseif resolver then
                        for _, range in ipairs(ranges) do
                            local boxes = resolver(sample, range, text)
                            if type(boxes) == "table" then
                                for _, run_box in ipairs(boxes) do
                                    if onOwnLine(run_box, group.boxes) then
                                        dotsUnder(run_box)
                                    end
                                end
                            end
                        end
                    end
                    -- No resolver, or it could not place the run: the run stays unmarked.
                    -- Dotting the line box instead would put the mark under narration.
                end
            end
        end
    end
    return rects
end

return EmphasisLayout
