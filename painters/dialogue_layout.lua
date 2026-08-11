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

-- A paragraph that merely cites a few words ("他说“好”便走了") is narration, so
-- mid-paragraph quotes must clear a coverage bar before we paint them.
local COVERAGE_THRESHOLD = 0.5

-- Opening marks, matched at the very start of a paragraph. In CJK fiction a
-- speech line is routinely followed by an attribution ("“在那里！”马脸男子忙指
-- 去。"), which drops coverage to ~0.1 even though the whole line is one
-- utterance; measured on the test novel, coverage alone missed 36% of them.
-- Position is the reliable signal, so leading quotes bypass the ratio.
local OPENERS = {
    cn = { "“", "「", "『" },
    en = { "“", '"' },
    all = { "“", "「", "『", '"' },
}

-- Shared with the CSS dialogue tint levels so one control drives both paths.
local TINT_OPACITY = { light = 0.12, medium = 0.20, strong = 0.30 }

-- Byte ranges of the quoted runs, in reading order. Painting one quote instead
-- of the whole line needs positions, not just the matched strings.
function DialogueLayout.quoteRanges(text, lang)
    if type(text) ~= "string" or text == "" then return {} end
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

-- Ratio of the paragraph covered by quoted runs, in bytes (UTF-8 safe because
-- both operands are byte lengths of the same encoding).
function DialogueLayout.quoteCoverage(text, lang)
    if type(text) ~= "string" or text == "" then return 0 end
    local matches = DialogueLayout.findQuotes(text, lang)
    if #matches == 0 then return 0 end
    local quoted = 0
    for _, inner in ipairs(matches) do
        quoted = quoted + #inner
    end
    local total = #(text:gsub("%s+", ""))
    if total == 0 then return 0 end
    return math.min(1, quoted / total)
end

-- True when the paragraph opens with a quote mark. Needs a closing mark too, so
-- a stray opener in narration cannot flag the line.
function DialogueLayout.startsQuoted(text, lang)
    if type(text) ~= "string" or text == "" then return false end
    -- Drop leading spaces / fullwidth indent so a line box that still carries
    -- paragraph padding does not hide an opening quote.
    text = text:gsub("^[%s\227\128\128]+", "")
    local openers = OPENERS[lang or "all"] or OPENERS.all
    for _, mark in ipairs(openers) do
        if text:sub(1, #mark) == mark then
            return #DialogueLayout.findQuotes(text, lang) > 0
        end
    end
    return false
end

function DialogueLayout.isDialogue(text, lang)
    return #DialogueLayout.quoteRanges(text, lang) > 0
end

local function nodeText(node, nodes)
    -- Prefer full paragraph HTML text if available, so quotes spanning across multiple
    -- screen lines within a paragraph are matched reliably.
    if type(node.html) == "string" and node.html ~= "" then
        local text = node.html:gsub("<[^>]*>", ""):gsub("%s+", " ")
            :gsub("^%s+", ""):gsub("%s+$", "")
        if text ~= "" then return text end
    end
    if type(node.text) == "string" and node.text ~= "" then
        return node.text
    end
    -- Fallback: concatenate screen_text of all line nodes belonging to the same paragraph key
    local key = type(node.xpointer) == "string" and node.xpointer:match("^(.*)%.%d+$")
    if key and type(nodes) == "table" then
        local parts = {}
        for _, n in ipairs(nodes) do
            local n_key = type(n.xpointer) == "string" and n.xpointer:match("^(.*)%.%d+$")
            if n_key == key and type(n.screen_text) == "string" and n.screen_text ~= "" then
                table.insert(parts, n.screen_text)
            end
        end
        if #parts > 0 then
            return table.concat(parts, "")
        end
    end
    if type(node.screen_text) == "string" and node.screen_text ~= "" then
        return node.screen_text
    end
    return ""
end

-- True when this line is entirely (or almost entirely) one quoted utterance.
-- Used to paint the whole line box instead of rewriting xpointer offsets into
-- nested Calibre spans, which is what dropped “轰” / “嗖” while leaving the
-- surrounding narration alone.
function DialogueLayout.isPureQuoteLine(text, lang)
    if type(text) ~= "string" or text == "" then return false end
    text = text:gsub("^[%s\227\128\128]+", ""):gsub("[%s\227\128\128]+$", "")
    local ranges = DialogueLayout.quoteRanges(text, lang)
    if #ranges == 0 then return false end
    local coverage = DialogueLayout.quoteCoverage(text, lang)
    if coverage >= 0.85 then return true end
    return false
end

function DialogueLayout.build(snapshot, options)
    options = options or {}
    if options.enabled ~= true then return {} end
    local screen = snapshot and snapshot.page and snapshot.page.viewport
    if not screen then return {} end

    local rects = {}
    local thickness = math.max(1, tonumber(options.thickness) or 1)
    local mode = options.mode or "tint"
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
        if mode == "underline" then
            local before = #rects
            addRect(rects, box.x, box.y + box.h - thickness, box.w, thickness, screen, nil)
            return #rects > before
        else
            -- Tint must blend, not fill: a solid rect would black out the text.
            local before = #rects
            addRect(rects, box.x, box.y, box.w, box.h, screen, opacity)
            return #rects > before
        end
    end

    -- semantic_index exposes normalized samples as `nodes`; `semantics` is the
    -- raw BookContext field and is absent here.
    for _, node in ipairs(snapshot.nodes or {}) do
        local box = node.box
        if box then
            local text = nodeText(node, snapshot.nodes)
            if DialogueLayout.isDialogue(text, options.lang) then
                if mode == "side_bar" then
                    -- A margin rule is inherently line-level; there is no
                    -- sensible per-quote equivalent.
                    addRect(rects, box.x - thickness * 3, box.y, thickness, box.h, screen, nil)
                else
                    -- Mark only the quoted runs when the document can resolve
                    -- their geometry, so narration and speech tags on the same
                    -- line stay unmarked. Whole-line boxes remain the fallback.
                    --
                    -- `nodes` are per line, so a paragraph running over three
                    -- lines appears three times while quoteRanges() describes
                    -- the whole paragraph. Resolving once per line would ask
                    -- the engine for the same boxes repeatedly and, worse,
                    -- darken those pixels once per line. Key on the element
                    -- path (the xpointer minus its character offset) and treat
                    -- the first line of a paragraph as covering all of it.
                    local key = type(node.xpointer) == "string"
                        and node.xpointer:match("^(.*)%.%d+$") or nil
                    local state = key and seen[key]
                    if state ~= "quoted" then
                        local painted = false
                        local pure = DialogueLayout.isPureQuoteLine(text, options.lang)
                        local used_subline = false
                        if pure then
                            painted = emit(box) and true or false
                        elseif resolver and state == nil then
                            for _, range in ipairs(DialogueLayout.quoteRanges(text, options.lang)) do
                                local boxes = resolver(node, range, text)
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
                        if not painted then painted = emit(box) and true or painted end
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
