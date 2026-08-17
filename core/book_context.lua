local BookContext = {}
BookContext.__index = BookContext

local function safeCall(fn, perf, metric)
    local ok, a, b, c
    if perf and metric then
        ok, a, b, c = perf:safeCall(metric, fn)
    else
        ok, a, b, c = pcall(fn)
    end
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

-- crengine xpointers end in a character offset ("…/p[5]/text()[3].16"). Strip it to get the
-- element the pointer sits in, so every line of one paragraph shares a single cache entry
-- instead of each line paying for its own DOM read.
local function elementPath(xpointer)
    return xpointer:match("^(.*)%.%d+$") or xpointer
end

local function isOrderedRange(document, xp0, xp1, perf)
    if not (xp0 and xp1) then return false end
    local comparison = safeCall(function()
        return document:compareXPointers(xp0, xp1)
    end, perf, "native.document.compareXPointers")
    return comparison == 1
end

local function visibleRange(document, perf)
    local xp0 = safeCall(function() return document:getXPointer() end,
        perf, "native.document.getXPointer")
    if not xp0 then return nil end
    local count = safeCall(function() return document:getVisiblePageNumberCount() end,
        perf, "native.document.getVisiblePageNumberCount")
        or safeCall(function() return document:getVisiblePageCount() end,
            perf, "native.document.getVisiblePageCount") or 1
    local current = safeCall(function() return document:getCurrentPage() end,
        perf, "native.document.getCurrentPage")
    local last = safeCall(function() return document:getPageCount() end,
        perf, "native.document.getPageCount")
    if not (current and last) then return xp0, nil end
    -- getPageXPointer points at the start of a page, so the first page after
    -- the visible range is current + visible_pages. Adding another page makes
    -- the engine resolve an unnecessary extra page before clipping screen boxes.
    local next_page = current + math.max(count, 1)
    if next_page > last then return xp0, nil end
    return xp0, safeCall(function() return document:getPageXPointer(next_page) end,
        perf, "native.document.getPageXPointer")
end

function BookContext.new(opts)
    return setmetatable({
        ui = assert(opts.ui),
        screen_size = assert(opts.screen_size),
        perf = opts.perf,
        cache = {},
    }, BookContext)
end

function BookContext:invalidate(reason)
    if self.perf then
        self.perf:mark("cache.book_context.invalidate")
        if reason then self.perf:mark("cache.book_context.invalidate." .. reason) end
    end
    self.cache = {}
end

function BookContext:_page()
    if self.cache.page then
        if self.perf then self.perf:mark("cache.page.hit") end
        return self.cache.page
    end
    if self.perf then self.perf:mark("cache.page.miss") end
    local document = self.ui.document
    local width, height = self.screen_size()
    local page = safeCall(function() return document:getCurrentPage() end,
        self.perf, "native.document.getCurrentPage") or 1
    local visible_pages = safeCall(function() return document:getVisiblePageNumberCount() end,
        self.perf, "native.document.getVisiblePageNumberCount")
        or safeCall(function() return document:getVisiblePageCount() end,
            self.perf, "native.document.getVisiblePageCount") or 1
    self.cache.page = {
        number = page,
        visible_pages = math.max(visible_pages, 1),
        viewport = { x = 0, y = 0, w = width, h = height },
    }
    return self.cache.page
end

function BookContext:_chapter()
    if self.cache.chapter then
        if self.perf then self.perf:mark("cache.chapter.hit") end
        return self.cache.chapter
    end
    if self.perf then self.perf:mark("cache.chapter.miss") end
    local page = self:_page().number
    local toc = self.ui.toc
    local chapter = { title = "", is_start = false, is_end = false }
    if toc then
        chapter.title = safeCall(function() return toc:getTocTitleByPage(page) end,
            self.perf, "native.toc.getTocTitleByPage") or ""
        chapter.is_start = safeCall(function() return toc:isChapterStart(page) end,
            self.perf, "native.toc.isChapterStart") == true
        chapter.is_end = safeCall(function() return toc:isChapterEnd(page) end,
            self.perf, "native.toc.isChapterEnd") == true
    end
    self.cache.chapter = chapter
    return chapter
end

function BookContext:_rawLines()
    if self.cache.raw_lines then
        if self.perf then self.perf:mark("cache.raw_lines.hit") end
        return self.cache.raw_lines
    end
    if self.perf then self.perf:mark("cache.raw_lines.miss") end
    local perf_started = self.perf and self.perf:start()
    local document = self.ui.document
    local page = self:_page()
    local raw
    local xp0, xp1 = self:_visibleRange()
    if xp0 and xp1 and isOrderedRange(document, xp0, xp1, self.perf) then
        raw = safeCall(function()
            return document:getScreenBoxesFromPositions(xp0, xp1, true)
        end, self.perf, "native.document.getScreenBoxes.visible")
    end
    if type(raw) ~= "table" or #raw == 0 then
        local text = safeCall(function()
            return document:getTextFromPositions(
                { x = 0, y = 0 }, { x = page.viewport.w, y = page.viewport.h }, true)
        end, self.perf, "native.document.getText.page")
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
    if self.perf then
        self.perf:mark("data.raw_lines", #lines)
        self.perf:finish("phase.book_context.raw_lines", perf_started)
    end
    return lines
end

-- Visible text for one screen line box. More reliable for dialogue detection
-- than HTML from a nearest-word xpointer: short quoted lines and Calibre's
-- nested <span class="dialogue"> wrappers both round-trip cleanly here.
function BookContext:textForBox(box)
    local document = self.ui.document
    if not validBox(box) then return nil end
    local raw_document = document._document
    local has_raw_text = raw_document
        and type(raw_document.getTextFromPositions) == "function"
    if not has_raw_text and type(document.getTextFromPositions) ~= "function" then
        return nil
    end
    local line_text_cache = self.cache.line_text
    if not line_text_cache then
        line_text_cache = {}
        self.cache.line_text = line_text_cache
    end
    local cached = line_text_cache[box]
    if cached ~= nil then
        if self.perf then self.perf:mark("cache.line_text.hit") end
        if cached == false then return nil end
        return cached.text, cached.pos0
    end
    if self.perf then self.perf:mark("cache.line_text.miss") end
    local x0 = box.x + 1
    local y0 = box.y + math.max(1, math.floor(box.h * 0.25))
    local x1 = box.x + math.max(2, box.w - 1)
    local y1 = box.y + math.max(2, math.floor(box.h * 0.75))
    local result
    if has_raw_text then
        result = safeCall(function()
            return raw_document:getTextFromPositions(x0, y0, x1, y1, false, false)
        end, self.perf, "native.document.getTextRange.line")
    end
    if type(result) ~= "table" and type(document.getTextFromPositions) == "function" then
        result = safeCall(function()
            return document:getTextFromPositions(
                { x = x0, y = y0 }, { x = x1, y = y1 }, true)
        end, self.perf, "native.document.getText.line")
    end
    if type(result) ~= "table" or type(result.text) ~= "string" then
        line_text_cache[box] = false
        return nil
    end
    local text = result.text
        :gsub("\194\173", "") -- soft hyphen
        :gsub("\239\187\191", "") -- BOM
        :gsub("%s+", " ")
        :gsub("^%s+", "")
        :gsub("%s+$", "")
    if text == "" then
        line_text_cache[box] = false
        return nil
    end
    cached = { text = text, pos0 = result.pos0 }
    line_text_cache[box] = cached
    return cached.text, cached.pos0
end

-- The visible range costs ~5 native calls to work out (current page, page count, visible
-- page count, two xpointers), so resolve it once per page and let every caller share it.
-- Cached as a table because a page legitimately resolves to (xp0, nil) near the book's end.
function BookContext:_visibleRange()
    local cached = self.cache.visible_range
    if cached then
        if self.perf then self.perf:mark("cache.visible_range.hit") end
        return cached[1], cached[2]
    end
    if self.perf then self.perf:mark("cache.visible_range.miss") end
    local xp0, xp1 = safeCall(function() return visibleRange(self.ui.document, self.perf) end,
        self.perf, "phase.book_context.visible_range")
    self.cache.visible_range = { xp0, xp1 }
    return xp0, xp1
end

-- Block-level markup that makes an element a quote. Used per line to decide whether
-- "skip blockquotes" applies to it.
local QUOTE_BLOCK_MARKERS = {
    "<blockquote",
    "class=\"[^\"]*quote[^\"]*\"",
    "class=\"[^\"]*epigraph[^\"]*\"",
    "class=\"[^\"]*citation[^\"]*\"",
}

-- Markers that mean "somewhere on this page there is a quote". Deliberately broad: a false
-- positive only costs the per-line probes that used to run unconditionally, while a false
-- negative would underline a quote.
--
-- The block markers plus <cite>, which is an inline element -- a body paragraph citing a
-- work is not itself a quote block, so it belongs here but not in the per-line set. The
-- two lists used to be written out separately and had drifted apart in the other
-- direction: the page check accepted epigraph and citation, the per-line check did not,
-- so such a block armed the expensive probe for the whole page and was then not skipped.
local QUOTE_MARKERS = { "<cite" }
for _, marker in ipairs(QUOTE_BLOCK_MARKERS) do
    table.insert(QUOTE_MARKERS, marker)
end

local function isQuoteBlockHTML(html_lower)
    for _, marker in ipairs(QUOTE_BLOCK_MARKERS) do
        if html_lower:find(marker) then return true end
    end
    return false
end

-- Does the visible page contain any quote markup at all?
--
-- One range read per page turn replaces one xpointer probe per full-width line. Full-width
-- blockquotes have no geometric tell, so the only alternative was probing every body line
-- on every page — 20 engine calls on a 20-line page, where an ordinary page needs none.
-- Reading the page's HTML once answers the question for the whole page instead.
--
-- Returns true/false, or nil when the engine cannot answer, which means "fall back to
-- probing per line" so older KOReader builds keep the old accuracy.
function BookContext:_pageHasQuoteMarkup()
    local cached = self.cache.page_quote_markup
    if cached ~= nil then
        if self.perf then self.perf:mark("cache.page_quote_markup.hit") end
        if cached == "unknown" then return nil end
        return cached
    end
    if self.perf then self.perf:mark("cache.page_quote_markup.miss") end

    local document = self.ui.document
    local result = "unknown"
    if type(document.getHTMLFromXPointers) == "function" then
        local xp0, xp1 = self:_visibleRange()
        if xp0 and xp1 then
            -- 0x1001 is the flag set ReaderLink uses for plain structural HTML without CSS.
            local html = safeCall(function()
                return document:getHTMLFromXPointers(xp0, xp1, 0x1001)
            end, self.perf, "native.document.getHTML.page")
            if type(html) == "string" then
                local html_lower = html:lower()
                result = false
                for _, marker in ipairs(QUOTE_MARKERS) do
                    if html_lower:find(marker) then
                        result = true
                        break
                    end
                end
            end
        end
    end

    self.cache.page_quote_markup = result
    if self.perf and result ~= "unknown" then
        self.perf:mark("data.page_quote_markup." .. tostring(result))
    end
    if result == "unknown" then return nil end
    return result
end

function BookContext:_bodyLines(skip_headings, skip_blockquotes)
    if skip_headings == nil then skip_headings = true end
    if skip_blockquotes == nil then skip_blockquotes = true end
    local cache_key = "body_lines_" .. tostring(skip_headings) .. "_" .. tostring(skip_blockquotes)
    if self.cache[cache_key] then
        if self.perf then self.perf:mark("cache.body_lines.hit") end
        return self.cache[cache_key]
    end
    if self.perf then self.perf:mark("cache.body_lines.miss") end
    local perf_started = self.perf and self.perf:start()

    local document = self.ui.document
    local page = self:_page()
    local lines = self:_rawLines()
    if #lines == 0 then
        if self.perf then self.perf:finish("phase.book_context.body_lines", perf_started) end
        return {}
    end

    if not skip_headings and not skip_blockquotes then
        self.cache[cache_key] = lines
        if self.perf then self.perf:finish("phase.book_context.body_lines", perf_started) end
        return lines
    end

    local page_left, page_right = page.viewport.w, 0
    for _, box in ipairs(lines) do
        page_left = math.min(page_left, box.x)
        page_right = math.max(page_right, box.x + box.w)
    end
    local max_line_w = page_right - page_left

    local modal = modalHeight(lines)
    local body = {}
    local xp_cache = {}

    -- Asked once per page, before the loop, and only when full-width quotes are actually
    -- being skipped. Three-valued on purpose, so it cannot go through `and`/`or`: that
    -- idiom collapses nil to false and would turn "the engine cannot tell us" into
    -- "this page has no quotes", silently dropping detection on builds without the
    -- range API instead of falling back to probing each line.
    local page_quotes = nil
    if skip_blockquotes then
        page_quotes = self:_pageHasQuoteMarkup()
    end
    local probe_full_width = skip_blockquotes and page_quotes ~= false

    for _, box in ipairs(lines) do
        local is_heading_or_center = false
        local is_blockquote = false

        -- Geometric Fast-Path:
        -- Normal body lines span almost the full page width and match modal height.
        local height_matches = not modal or math.abs(box.h - modal) <= modal * 0.15
        local left_gap = box.x - page_left
        local right_gap = page_right - (box.x + box.w)

        if max_line_w > 50 and left_gap > 15 and right_gap > 15 and box.w < max_line_w * 0.88 then
            local diff = math.abs(left_gap - right_gap)
            if diff <= math.max(25, max_line_w * 0.1) then
                is_heading_or_center = true
            end
        end

        if modal and math.abs(box.h - modal) > modal * 0.2 then
            if not is_heading_or_center then
                is_heading_or_center = true
            end
        end

        -- Only do expensive DOM / HTML inspection if geometric heuristics flag this
        -- line as a candidate (indented or non-standard width) and it's not already resolved.
        -- geometry_suspect distinguishes those lines from the cheap opportunistic probe
        -- below, which is allowed the xpointer lookup but not the costlier follow-ups.
        local needs_dom_check = false
        local geometry_suspect = false
        if not is_heading_or_center then
            if skip_blockquotes and (left_gap > 15 or box.w < max_line_w * 0.90) then
                needs_dom_check, geometry_suspect = true, true
            elseif skip_headings and (box.w < max_line_w * 0.90 or not height_matches) then
                needs_dom_check, geometry_suspect = true, true
            elseif probe_full_width then
                -- A <blockquote> that the book's CSS renders at (or near) full width has
                -- neither an indent nor a width tell, so geometry can never flag it and it
                -- used to get underlined as body text. Only reached when the page-level
                -- read said this page contains quote markup (or could not tell), so an
                -- ordinary page pays nothing here.
                needs_dom_check = true
                -- The page markup check found a quote but the element path may not name it
                -- (`<div class="quote">` is invisible in an xpointer), so let these lines
                -- take the HTML pass too. Confined to pages that really have a quote, and
                -- the element-path cache keeps it to one read per paragraph.
                geometry_suspect = page_quotes == true
            end
        end

        if needs_dom_check then
            local _, xp = self:textForBox(box)
            if type(xp) ~= "string" and geometry_suspect then
                -- Second lookup only for geometry-flagged lines: the opportunistic
                -- full-width probe is not worth an extra native call per line.
                local nearest = safeCall(function()
                    return document:getNearestWordFromPosition({
                        x = box.x + 2,
                        y = box.y + math.floor(box.h / 2),
                    })
                end, self.perf, "native.document.getNearestWord.body")
                xp = type(nearest) == "table" and nearest.pos0
            end
            if type(xp) == "string" then
                local key = elementPath(xp)
                local cached = xp_cache[key]
                -- A full-width probe records its entry without reading HTML, so a
                -- geometry-flagged line landing on that entry still gets the HTML pass.
                if cached and (cached.html_checked or not geometry_suspect) then
                    if cached.is_heading_or_center then is_heading_or_center = true end
                    if cached.is_blockquote then is_blockquote = true end
                else
                    local xp_lower = xp:lower()
                    local xp_is_heading = xp_lower:find("/h%d") or xp_lower:find("title") or xp_lower:find("heading")
                                       or xp_lower:find("center") or xp_lower:find("align=center") or xp_lower:find("align=\"center\"")
                    local xp_is_quote = xp_lower:find("blockquote") or xp_lower:find("quote")

                    if xp_is_heading then is_heading_or_center = true end
                    if xp_is_quote then is_blockquote = true end

                    -- The HTML read is the expensive half, so it stays behind the geometry
                    -- gate, and is skipped once the line is already known to be skippable.
                    local resolved = is_heading_or_center or (is_blockquote and skip_blockquotes)
                    local html_checked = false
                    if geometry_suspect and not resolved
                            and type(document.getHTMLFromXPointer) == "function" then
                        html_checked = true
                        local html = safeCall(function()
                            return document:getHTMLFromXPointer(xp, 0x1001, true)
                        end, self.perf, "native.document.getHTML.body")
                        if type(html) == "string" and html ~= "" then
                            local html_lower = html:lower()
                            if html_lower:find("<h%d") or html_lower:find("class=\"[^\"]*title[^\"]*\"")
                               or html_lower:find("class=\"[^\"]*center[^\"]*\"")
                               or html_lower:find("align=\"center\"") or html_lower:find("align=center")
                               or html_lower:find("text%-align%s*:%s*center") then
                                is_heading_or_center = true
                                xp_is_heading = true
                            end
                            if isQuoteBlockHTML(html_lower) then
                                is_blockquote = true
                                xp_is_quote = true
                            end
                        end
                    end
                    xp_cache[key] = {
                        is_heading_or_center = xp_is_heading and true or false,
                        is_blockquote = xp_is_quote and true or false,
                        html_checked = html_checked,
                    }
                end
            end
        end

        local skippable = (skip_headings and is_heading_or_center)
                       or (skip_blockquotes and is_blockquote)

        if not skippable then
            table.insert(body, box)
        end
    end
    self.cache[cache_key] = body
    if self.perf then
        self.perf:mark("data.body_lines", #body)
        self.perf:finish("phase.book_context.body_lines", perf_started)
    end
    return body
end

function BookContext:_toc()
    if self.cache.toc then
        if self.perf then self.perf:mark("cache.toc.hit") end
        return self.cache.toc
    end
    if self.perf then self.perf:mark("cache.toc.miss") end
    local perf_started = self.perf and self.perf:start()
    local toc = self.ui.toc and self.ui.toc.toc
    if type(toc) ~= "table" then
        toc = safeCall(function() return self.ui.document:getToc() end,
            self.perf, "native.document.getToc")
    end
    toc = type(toc) == "table" and toc or {}
    local empty_titles = 0
    for _, item in ipairs(toc) do
        if type(item.title) ~= "string" or item.title:match("%S") == nil then
            empty_titles = empty_titles + 1
        end
    end
    self.cache.toc = { count = #toc, empty_titles = empty_titles }
    if self.perf then self.perf:finish("phase.book_context.toc", perf_started) end
    return self.cache.toc
end

function BookContext:_semantics(profile)
    if profile ~= "dialogue" and profile ~= "full" then
        profile = "structure"
    end
    local semantics_key = "semantics_" .. profile
    local capabilities_key = "capabilities_" .. profile
    if self.cache[semantics_key] then
        if self.perf then
            self.perf:mark("cache.semantics.hit")
            self.perf:mark("cache.semantics." .. profile .. ".hit")
        end
        return self.cache[semantics_key], self.cache[capabilities_key]
    end
    if self.perf then
        self.perf:mark("cache.semantics.miss")
        self.perf:mark("cache.semantics." .. profile .. ".miss")
    end
    local perf_started = self.perf and self.perf:start()
    local document = self.ui.document
    local samples = {}
    local needs_structure = profile ~= "dialogue"
    local needs_text = profile ~= "structure"
    local html_supported = needs_structure
        and type(document.getHTMLFromXPointer) == "function"
    local html_available = false
    local html_cache = {}

    for _, box in ipairs(self:_rawLines()) do
        local xpointer
        if needs_structure then
            -- Center probe is fastest and hits ~95% of lines on the first attempt.
            local nearest = safeCall(function()
                return document:getNearestWordFromPosition({
                    x = box.x + math.floor(box.w / 2),
                    y = box.y + math.floor(box.h / 2),
                })
            end, self.perf, "native.document.getNearestWord.semantic.center")
            if type(nearest) == "table" and type(nearest.pos0) == "string" then
                xpointer = nearest.pos0
            else
                -- Fallback probes only if center probe missed (short CJK lines, indents)
                local left_px = box.x + math.min(4, math.max(1, math.floor(box.w / 2)))
                nearest = safeCall(function()
                    return document:getNearestWordFromPosition({
                        x = left_px,
                        y = box.y + math.floor(box.h / 2),
                    })
                end, self.perf, "native.document.getNearestWord.semantic.left")
                if type(nearest) == "table" and type(nearest.pos0) == "string" then
                    xpointer = nearest.pos0
                else
                    local right_px = box.x + math.max(4, box.w - 4)
                    nearest = safeCall(function()
                        return document:getNearestWordFromPosition({
                            x = right_px,
                            y = box.y + math.floor(box.h / 2),
                        })
                    end, self.perf, "native.document.getNearestWord.semantic.right")
                    if type(nearest) == "table" and type(nearest.pos0) == "string" then
                        xpointer = nearest.pos0
                    end
                end
            end
        end

        local html
        if xpointer and html_supported then
            -- Parent paragraph key (e.g. /body/DocFragment/body/p[5])
            -- from_final_parent=true returns the parent paragraph markup, so lines in the same
            -- paragraph share the exact same returned html.
            local base_xp = elementPath(xpointer)
            if html_cache[base_xp] ~= nil then
                html = html_cache[base_xp]
                if html then html_available = true end
            else
                html = safeCall(function()
                    return document:getHTMLFromXPointer(xpointer, 0x1001, true)
                end, self.perf, "native.document.getHTML.semantic")
                if type(html) == "string" and html ~= "" then
                    html_available = true
                    html_cache[base_xp] = html
                else
                    html = nil
                    html_cache[base_xp] = false
                end
            end
        end
        local screen_text, line_pos0
        if needs_text then
            screen_text, line_pos0 = self:textForBox(box)
        end
        table.insert(samples, {
            box = box,
            xpointer = xpointer,
            pos0 = line_pos0,
            html = html,
            screen_text = screen_text,
        })
    end
    self.cache[semantics_key] = samples
    self.cache[capabilities_key] = { html = html_available }
    if self.perf then
        self.perf:mark("data.semantic_nodes", #samples)
        self.perf:finish("phase.book_context.semantics", perf_started)
        self.perf:finish("phase.book_context.semantics." .. profile, perf_started)
    end
    return samples, self.cache[capabilities_key]
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
-- Exposed for the spec that pins the page pre-check and the per-line check to one list.
BookContext.QUOTE_MARKERS = QUOTE_MARKERS
BookContext.QUOTE_BLOCK_MARKERS = QUOTE_BLOCK_MARKERS
BookContext.isQuoteBlockHTML = isQuoteBlockHTML

-- Screen boxes for a byte range inside the text node that `xpointer` addresses.
-- Returns nil when the document cannot resolve the range, so callers can fall
-- back to the whole-line box rather than drawing nothing.
function BookContext:boxesForRange(xpointer, first_byte, last_byte, text, text_origin)
    local document = self.ui.document
    if type(document.getScreenBoxesFromPositions) ~= "function" then return nil end
    local perf_started = self.perf and self.perf:start()
    -- The xpointer's trailing number is the char offset of the range's first
    -- character inside its text node. For a line that starts mid-node (a
    -- wrapped paragraph), that base must be ADDED to the offsets computed from
    -- the line's own screen_text, not replace them: replacing would point at
    -- characters earlier in the node and paint a wrong short segment.
    local base, base_offset = xpointer:match("^(.*)%.(%d+)$")
    if not base then
        if self.perf then self.perf:finish("phase.book_context.boxes_for_range", perf_started) end
        return nil
    end
    base_offset = tonumber(base_offset) or 0
    if text_origin then
        -- The caller knows where `text` begins inside the node -- 0 when it measured the
        -- offsets over the whole paragraph -- so the line's own base must not be added
        -- on top of them. Getting this wrong only showed on a paragraph continued from
        -- the previous page: the first line of a paragraph starts at 0, where the two
        -- conventions agree, which is why the tint looked right everywhere except at the
        -- top of the page.
        base_offset = text_origin
    end
    local start_offset = base_offset + charCount(text, first_byte - 1)
    local stop_offset = base_offset + charCount(text, last_byte)
    local xp0 = base .. "." .. tostring(start_offset)
    local xp1 = base .. "." .. tostring(stop_offset)
    local boxes = safeCall(function()
        return document:getScreenBoxesFromPositions(xp0, xp1, true)
    end, self.perf, "native.document.getScreenBoxes.quote")
    if type(boxes) ~= "table" or #boxes == 0 then
        if self.perf then self.perf:finish("phase.book_context.boxes_for_range", perf_started) end
        return nil
    end
    local page = self:_page()
    local clipped = {}
    for _, box in ipairs(boxes) do
        local ok = clipBox(box, page.viewport.w, page.viewport.h)
        if ok then table.insert(clipped, ok) end
    end
    if #clipped == 0 then
        if self.perf then self.perf:finish("phase.book_context.boxes_for_range", perf_started) end
        return nil
    end
    if self.perf then
        self.perf:mark("data.quote_boxes", #clipped)
        self.perf:finish("phase.book_context.boxes_for_range", perf_started)
    end
    return clipped
end

-- Word boxes (and their screen texts) for one screen line. The semantic nodes
-- are usually word-sized already, but a line rendered as a single long run
-- (common for CJK without markup) arrives as one node; splitting it here lets
-- the dialogue painter shade exactly the quoted words instead of the whole line.
function BookContext:lineWordBoxes(line_box)
    local document = self.ui.document
    if type(document.getTextFromPositions) ~= "function" then return nil end
    local perf_started = self.perf and self.perf:start()
    local range = safeCall(function()
        return document:getTextFromPositions(
            { x = line_box.x, y = line_box.y },
            { x = line_box.x + line_box.w, y = line_box.y + line_box.h }, true)
    end, self.perf, "native.document.getText.word_range")
    if type(range) ~= "table" or type(range.text) ~= "string" or range.text == "" then
        if self.perf then self.perf:finish("phase.book_context.line_word_boxes", perf_started) end
        return nil
    end
    local words = {}
    for _, box in ipairs(type(range.sboxes) == "table" and range.sboxes or {}) do
        local text = self:textForBox(box)
        if text and text ~= "" then
            table.insert(words, { box = box, text = text })
        end
    end
    if #words == 0 then
        if self.perf then self.perf:finish("phase.book_context.line_word_boxes", perf_started) end
        return nil
    end
    if self.perf then
        self.perf:mark("data.word_boxes", #words)
        self.perf:finish("phase.book_context.line_word_boxes", perf_started)
    end
    return { text = range.text, words = words }
end

function BookContext:snapshot(request)
    request = request or {}
    local snapshot = { page = self:_page() }
    if request.chapter then snapshot.chapter = self:_chapter() end
    if request.toc then snapshot.toc = self:_toc() end
    if request.semantics then
        snapshot.semantics, snapshot.capabilities = self:_semantics(request.semantic_profile)
    end
    if request.line_mode == "body" then
        snapshot.lines = self:_bodyLines(request.skip_headings, request.skip_blockquotes)
    elseif request.line_mode == "all" then
        snapshot.lines = self:_rawLines()
    end
    return snapshot
end

return BookContext
