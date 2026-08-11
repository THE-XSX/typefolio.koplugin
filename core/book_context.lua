local BookContext = {}
BookContext.__index = BookContext

local function safeCall(fn)
    local ok, a, b, c = pcall(fn)
    if ok then return a, b, c end
    return nil
end

local function validBox(box)
    return type(box) == "table" and type(box.x) == "number" and type(box.y) == "number"
        and type(box.w) == "number" and type(box.h) == "number"
        and box.w > 0 and box.h > 0
end

local function clipBox(box, width, height)
    if not validBox(box) then return nil end
    local x0 = math.max(0, box.x)
    local y0 = math.max(0, box.y)
    local x1 = math.min(width, box.x + box.w)
    local y1 = math.min(height, box.y + box.h)
    if x1 <= x0 or y1 <= y0 then return nil end
    return { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
end

local function modalHeight(boxes)
    local counts, best, best_count = {}, nil, 0
    for _, box in ipairs(boxes) do
        local height = math.floor(box.h)
        counts[height] = (counts[height] or 0) + 1
        if counts[height] > best_count then
            best, best_count = height, counts[height]
        end
    end
    return best
end

local function isOrderedRange(document, xp0, xp1)
    if not (xp0 and xp1) then return false end
    local comparison = safeCall(function()
        return document:compareXPointers(xp0, xp1)
    end)
    return comparison == 1
end

local function visibleRange(document)
    local xp0 = safeCall(function() return document:getXPointer() end)
    if not xp0 then return nil end
    local count = safeCall(function() return document:getVisiblePageNumberCount() end)
        or safeCall(function() return document:getVisiblePageCount() end) or 1
    local current = safeCall(function() return document:getCurrentPage() end)
    local last = safeCall(function() return document:getPageCount() end)
    if not (current and last) then return xp0, nil end
    local next_page = current + math.max(count, 1) + 1
    if next_page > last then return xp0, nil end
    return xp0, safeCall(function() return document:getPageXPointer(next_page) end)
end

function BookContext.new(opts)
    return setmetatable({
        ui = assert(opts.ui),
        screen_size = assert(opts.screen_size),
        cache = {},
    }, BookContext)
end

function BookContext:invalidate()
    self.cache = {}
end

function BookContext:_page()
    if self.cache.page then return self.cache.page end
    local document = self.ui.document
    local width, height = self.screen_size()
    local page = safeCall(function() return document:getCurrentPage() end) or 1
    local visible_pages = safeCall(function() return document:getVisiblePageNumberCount() end)
        or safeCall(function() return document:getVisiblePageCount() end) or 1
    self.cache.page = {
        number = page,
        visible_pages = math.max(visible_pages, 1),
        viewport = { x = 0, y = 0, w = width, h = height },
    }
    return self.cache.page
end

function BookContext:_chapter()
    if self.cache.chapter then return self.cache.chapter end
    local page = self:_page().number
    local toc = self.ui.toc
    local chapter = { title = "", is_start = false, is_end = false }
    if toc then
        chapter.title = safeCall(function() return toc:getTocTitleByPage(page) end) or ""
        chapter.is_start = safeCall(function() return toc:isChapterStart(page) end) == true
        chapter.is_end = safeCall(function() return toc:isChapterEnd(page) end) == true
    end
    self.cache.chapter = chapter
    return chapter
end

function BookContext:_rawLines()
    if self.cache.raw_lines then return self.cache.raw_lines end
    local document = self.ui.document
    local page = self:_page()
    local raw
    local xp0, xp1 = safeCall(function() return visibleRange(document) end)
    if xp0 and xp1 and isOrderedRange(document, xp0, xp1) then
        raw = safeCall(function()
            return document:getScreenBoxesFromPositions(xp0, xp1, true)
        end)
    end
    if type(raw) ~= "table" or #raw == 0 then
        local text = safeCall(function()
            return document:getTextFromPositions(
                { x = 0, y = 0 }, { x = page.viewport.w, y = page.viewport.h }, true)
        end)
        raw = text and text.sboxes or {}
    end

    local lines = {}
    for _, box in ipairs(type(raw) == "table" and raw or {}) do
        local clipped = clipBox(box, page.viewport.w, page.viewport.h)
        if clipped then table.insert(lines, clipped) end
    end
    table.sort(lines, function(a, b)
        return a.y == b.y and a.x < b.x or a.y < b.y
    end)
    self.cache.raw_lines = lines
    return lines
end

-- Visible text for one screen line box. More reliable for dialogue detection
-- than HTML from a nearest-word xpointer: short quoted lines and Calibre's
-- nested <span class="dialogue"> wrappers both round-trip cleanly here.
function BookContext:textForBox(box)
    local document = self.ui.document
    if not validBox(box) then return nil end
    if type(document.getTextFromPositions) ~= "function" then return nil end
    local result = safeCall(function()
        return document:getTextFromPositions(
            { x = box.x + 1, y = box.y + math.max(1, math.floor(box.h * 0.25)) },
            { x = box.x + math.max(2, box.w - 1), y = box.y + math.max(2, math.floor(box.h * 0.75)) },
            true)
    end)
    if type(result) ~= "table" or type(result.text) ~= "string" then return nil end
    local text = result.text
        :gsub("\194\173", "") -- soft hyphen
        :gsub("\239\187\191", "") -- BOM
        :gsub("%s+", " ")
        :gsub("^%s+", "")
        :gsub("%s+$", "")
    if text == "" then return nil end
    return text, result.pos0
end

function BookContext:_bodyLines(skip_headings, skip_blockquotes)
    if skip_headings == nil then skip_headings = true end
    if skip_blockquotes == nil then skip_blockquotes = true end
    local cache_key = "body_lines_" .. tostring(skip_headings) .. "_" .. tostring(skip_blockquotes)
    if self.cache[cache_key] then return self.cache[cache_key] end

    local document = self.ui.document
    local page = self:_page()
    local lines = self:_rawLines()
    if #lines == 0 then return {} end

    local page_left, page_right = page.viewport.w, 0
    for _, box in ipairs(lines) do
        page_left = math.min(page_left, box.x)
        page_right = math.max(page_right, box.x + box.w)
    end
    local max_line_w = page_right - page_left

    local modal = modalHeight(lines)
    local body = {}
    for _, box in ipairs(lines) do
        local is_heading_or_center = false
        local is_blockquote = false

        local nearest = safeCall(function()
            return document:getNearestWordFromPosition({
                x = box.x + 2,
                y = box.y + math.floor(box.h / 2),
            })
        end)
        local xp = type(nearest) == "table" and nearest.pos0
        if type(xp) == "string" then
            local xp_lower = xp:lower()
            if xp_lower:find("/h%d") or xp_lower:find("title") or xp_lower:find("heading")
               or xp_lower:find("center") or xp_lower:find("align=center") or xp_lower:find("align=\"center\"") then
                is_heading_or_center = true
            end
            if xp_lower:find("blockquote") or xp_lower:find("quote") then
                is_blockquote = true
            end

            if not is_heading_or_center and type(document.getHTMLFromXPointer) == "function" then
                local html = safeCall(function()
                    return document:getHTMLFromXPointer(xp, 0x1001, true)
                end)
                if type(html) == "string" and html ~= "" then
                    local html_lower = html:lower()
                    if html_lower:find("<h%d") or html_lower:find("class=\"[^\"]*title[^\"]*\"")
                       or html_lower:find("class=\"[^\"]*center[^\"]*\"")
                       or html_lower:find("align=\"center\"") or html_lower:find("align=center")
                       or html_lower:find("text%-align%s*:%s*center") then
                        is_heading_or_center = true
                    end
                    if html_lower:find("<blockquote") or html_lower:find("class=\"[^\"]*quote[^\"]*\"") then
                        is_blockquote = true
                    end
                end
            end
        end

        if not is_heading_or_center and max_line_w > 50 then
            local left_gap = box.x - page_left
            local right_gap = page_right - (box.x + box.w)
            if left_gap > 15 and right_gap > 15 and box.w < max_line_w * 0.88 then
                local diff = math.abs(left_gap - right_gap)
                if diff <= math.max(25, max_line_w * 0.1) then
                    is_heading_or_center = true
                end
            end
        end

        if modal and math.abs(box.h - modal) > modal * 0.2 then
            if not is_heading_or_center and not is_blockquote then
                is_heading_or_center = true
            end
        end

        local skippable = (skip_headings and is_heading_or_center)
                       or (skip_blockquotes and is_blockquote)

        if not skippable then
            table.insert(body, box)
        end
    end
    self.cache[cache_key] = body
    return body
end

function BookContext:_toc()
    if self.cache.toc then return self.cache.toc end
    local toc = self.ui.toc and self.ui.toc.toc
    if type(toc) ~= "table" then
        toc = safeCall(function() return self.ui.document:getToc() end)
    end
    toc = type(toc) == "table" and toc or {}
    local empty_titles = 0
    for _, item in ipairs(toc) do
        if type(item.title) ~= "string" or item.title:match("%S") == nil then
            empty_titles = empty_titles + 1
        end
    end
    self.cache.toc = { count = #toc, empty_titles = empty_titles }
    return self.cache.toc
end

function BookContext:_semantics()
    if self.cache.semantics then return self.cache.semantics, self.cache.capabilities end
    local document = self.ui.document
    local samples = {}
    local html_supported = type(document.getHTMLFromXPointer) == "function"
    local html_available = false
    for _, box in ipairs(self:_rawLines()) do
        -- Short CJK dialogue lines are easy to miss with a single left-side
        -- probe (first-line indent, narrow glyphs, trailing punctuation). Try a
        -- few x positions across the line and keep the first hit that yields a
        -- usable xpointer.
        local xpointer
        local probes = {
            box.x + math.min(4, math.max(1, box.w / 2)),
            box.x + box.w / 2,
            box.x + math.max(4, box.w - 4),
        }
        for _, px in ipairs(probes) do
            local nearest = safeCall(function()
                return document:getNearestWordFromPosition({
                    x = px,
                    y = box.y + box.h / 2,
                })
            end)
            if type(nearest) == "table" and type(nearest.pos0) == "string" then
                xpointer = nearest.pos0
                break
            end
        end
        local html
        if xpointer and html_supported then
            html = safeCall(function()
                -- from_final_parent=true walks up to the paragraph-like parent so
                -- nested Calibre markup such as
                --   <p><span><span class="dialogue">...</span></span></p>
                -- still yields the full utterance instead of a bare inner span
                -- fragment that can lose quote context after cleanup.
                return document:getHTMLFromXPointer(xpointer, 0x1001, true)
            end)
            if type(html) == "string" and html ~= "" then html_available = true end
        end
        local screen_text, line_pos0 = self:textForBox(box)
        table.insert(samples, {
            box = box,
            xpointer = xpointer,
            pos0 = line_pos0,
            html = html,
            screen_text = screen_text,
        })
    end
    self.cache.semantics = samples
    self.cache.capabilities = { html = html_available }
    return samples, self.cache.capabilities
end

-- A crengine xpointer ends with a character offset into its text node, e.g.
--   /body/DocFragment/body/p[5]/text()[3].16
-- (the format is documented in KOReader's readerlink.lua). Rewriting that
-- trailing number is how we address an arbitrary character without walking
-- getNextVisibleChar one codepoint at a time, which would cost one engine call
-- per character.
local function xpointerAtOffset(xpointer, offset)
    if type(xpointer) ~= "string" then return nil end
    local base = xpointer:match("^(.*)%.%d+$")
    if not base then return nil end
    return base .. "." .. tostring(offset)
end

-- Number of UTF-8 codepoints in the first `bytes` bytes of `text`. Offsets in
-- an xpointer count characters, but Lua patterns hand back byte positions, so
-- every range has to be converted before it can be spliced into a pointer.
local function charCount(text, bytes)
    if type(text) ~= "string" then return 0 end
    local count = 0
    local i = 1
    while i <= bytes and i <= #text do
        local byte = text:byte(i)
        -- Continuation bytes are 10xxxxxx; only count lead bytes.
        if byte < 0x80 or byte >= 0xC0 then count = count + 1 end
        i = i + 1
    end
    return count
end

BookContext.xpointerAtOffset = xpointerAtOffset
BookContext.charCount = charCount

-- Screen boxes for a byte range inside the text node that `xpointer` addresses.
-- Returns nil when the document cannot resolve the range, so callers can fall
-- back to the whole-line box rather than drawing nothing.
function BookContext:boxesForRange(xpointer, first_byte, last_byte, text)
    local document = self.ui.document
    if type(document.getScreenBoxesFromPositions) ~= "function" then return nil end
    -- The xpointer's trailing number is the char offset of the range's first
    -- character inside its text node. For a line that starts mid-node (a
    -- wrapped paragraph), that base must be ADDED to the offsets computed from
    -- the line's own screen_text, not replace them: replacing would point at
    -- characters earlier in the node and paint a wrong short segment.
    local base, base_offset = xpointer:match("^(.*)%.(%d+)$")
    if not base then return nil end
    base_offset = tonumber(base_offset) or 0
    local start_offset = base_offset + charCount(text, first_byte - 1)
    local stop_offset = base_offset + charCount(text, last_byte)
    local xp0 = base .. "." .. tostring(start_offset)
    local xp1 = base .. "." .. tostring(stop_offset)
    local boxes = safeCall(function()
        return document:getScreenBoxesFromPositions(xp0, xp1, true)
    end)
    if type(boxes) ~= "table" or #boxes == 0 then return nil end
    local page = self:_page()
    local clipped = {}
    for _, box in ipairs(boxes) do
        local ok = clipBox(box, page.viewport.w, page.viewport.h)
        if ok then table.insert(clipped, ok) end
    end
    if #clipped == 0 then return nil end
    return clipped
end

-- Word boxes (and their screen texts) for one screen line. The semantic nodes
-- are usually word-sized already, but a line rendered as a single long run
-- (common for CJK without markup) arrives as one node; splitting it here lets
-- the dialogue painter shade exactly the quoted words instead of the whole line.
function BookContext:lineWordBoxes(line_box)
    local document = self.ui.document
    if type(document.getTextFromPositions) ~= "function" then return nil end
    local range = safeCall(function()
        return document:getTextFromPositions(
            { x = line_box.x, y = line_box.y },
            { x = line_box.x + line_box.w, y = line_box.y + line_box.h }, true)
    end)
    if type(range) ~= "table" or type(range.text) ~= "string" or range.text == "" then
        return nil
    end
    local words = {}
    for _, box in ipairs(type(range.sboxes) == "table" and range.sboxes or {}) do
        local text = self:textForBox(box)
        if text and text ~= "" then
            table.insert(words, { box = box, text = text })
        end
    end
    if #words == 0 then return nil end
    return { text = range.text, words = words }
end

function BookContext:snapshot(request)
    request = request or {}
    local snapshot = { page = self:_page() }
    if request.chapter then snapshot.chapter = self:_chapter() end
    if request.toc then snapshot.toc = self:_toc() end
    if request.semantics then
        snapshot.semantics, snapshot.capabilities = self:_semantics()
    end
    if request.line_mode == "body" then
        snapshot.lines = self:_bodyLines(request.skip_headings, request.skip_blockquotes)
    elseif request.line_mode == "all" then
        snapshot.lines = self:_rawLines()
    end
    return snapshot
end

return BookContext
