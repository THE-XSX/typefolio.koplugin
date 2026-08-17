-- "Skip blockquotes" has to agree with itself.
--
-- Two lists decide whether a line is a quote: one scans the whole page's HTML to decide
-- if the expensive per-line probe is worth arming at all, the other looks at a single
-- element. They were written out separately and drifted: the page scan accepted
-- `epigraph` and `citation`, the per-line check only `<blockquote>` and `class="quote"`.
-- An epigraph therefore armed the probe for every full-width line on the page -- the
-- exact cost the page scan exists to avoid -- and was then underlined anyway.
--
-- The two are now derived from one list, and this spec pins both the relationship and
-- the behaviour, driving the real _bodyLines against a stub document.
--
-- Run from the plugin root:
--   python3 runlua.py <plugin_dir> <plugin_dir>/tests/quote_markup_spec.lua

local BookContext = dofile("core/book_context.lua")

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

-- ------------------------------------------------------------------ the two lists

do
    local page_set = {}
    for _, marker in ipairs(BookContext.QUOTE_MARKERS) do page_set[marker] = true end
    local missing = {}
    for _, marker in ipairs(BookContext.QUOTE_BLOCK_MARKERS) do
        if not page_set[marker] then table.insert(missing, marker) end
    end
    -- The direction that matters: the page scan must never be narrower than the per-line
    -- check, or a quote is skipped by nobody. The reverse is fine and intended.
    check("every per-line marker is also a page marker (" .. table.concat(missing, ", ") .. ")",
        #missing == 0)
    check("the page list is the wider one",
        #BookContext.QUOTE_MARKERS > #BookContext.QUOTE_BLOCK_MARKERS)
end

do
    local function isBlock(html) return BookContext.isQuoteBlockHTML(html:lower()) end
    check("a <blockquote> is a quote block", isBlock('<blockquote><p>x</p></blockquote>'))
    check('class="quote" is a quote block', isBlock('<div class="quote">x</div>'))
    check('class="epigraph" is a quote block', isBlock('<div class="epigraph">x</div>'))
    check('class="citation" is a quote block', isBlock('<div class="citation">x</div>'))
    check("a compound class still matches", isBlock('<div class="first epigraph big">x</div>'))
    check("an ordinary paragraph is not", not isBlock('<p>普通的一段正文。</p>'))
    -- <cite> is inline: a paragraph that cites a work is still body text. It stays a
    -- page-level hint only.
    check("an inline <cite> does not turn a paragraph into a quote block",
        not isBlock('<p>见<cite>《论语》</cite>所载。</p>'))
end

-- --------------------------------------------------------- and the behaviour it drives

local FULL_WIDTH = { x = 20, w = 560, h = 24 }

local function documentWith(html)
    local boxes = {
        { x = FULL_WIDTH.x, y = 40, w = FULL_WIDTH.w, h = FULL_WIDTH.h },  -- body
        { x = FULL_WIDTH.x, y = 70, w = FULL_WIDTH.w, h = FULL_WIDTH.h },  -- the quote
        { x = FULL_WIDTH.x, y = 100, w = FULL_WIDTH.w, h = FULL_WIDTH.h }, -- body
    }
    local per_line_calls = 0
    local document = {
        getCurrentPage = function() return 5 end,
        getVisiblePageNumberCount = function() return 1 end,
        getPageCount = function() return 100 end,
        getXPointer = function() return "/body/p[1]/text().0" end,
        getPageXPointer = function() return "/body/p[9]/text().0" end,
        compareXPointers = function() return 1 end,
        getScreenBoxesFromPositions = function() return boxes end,
        getNearestWordFromPosition = function(_, pos)
            -- One xpointer per line, so the middle line can carry the quote markup.
            local index = 1
            for i, box in ipairs(boxes) do
                if pos and pos.y and pos.y >= box.y and pos.y < box.y + box.h then index = i end
            end
            return { pos0 = "/body/p[" .. index .. "]/text().0" }
        end,
        getHTMLFromXPointers = function() return html.page end,
        getHTMLFromXPointer = function(_, xp)
            per_line_calls = per_line_calls + 1
            local index = tonumber(xp:match("%[(%d+)%]")) or 1
            return html.lines[index] or "<p>正文。</p>"
        end,
    }
    return document, function() return per_line_calls end
end

local function bodyLines(document)
    local context = BookContext.new{
        ui = { document = document },
        screen_size = function() return 600, 800 end,
    }
    return context:_bodyLines(true, true)
end

local function runWith(quote_html)
    local html = {
        page = "<p>正文。</p>" .. quote_html .. "<p>正文。</p>",
        lines = { "<p>正文。</p>", quote_html, "<p>正文。</p>" },
    }
    local document, calls = documentWith(html)
    return bodyLines(document), calls
end

do
    local kept = runWith('<div class="epigraph"><p>题记。</p></div>')
    check("a full-width epigraph is skipped, not underlined", #kept == 2)

    kept = runWith('<div class="citation"><p>引文。</p></div>')
    check("a full-width citation is skipped", #kept == 2)

    kept = runWith("<blockquote><p>引文。</p></blockquote>")
    check("a full-width blockquote is still skipped", #kept == 2)

    kept = runWith('<div class="quote"><p>引文。</p></div>')
    check('a full-width class="quote" is still skipped', #kept == 2)
end

do
    -- The page scan's whole purpose: a page with no quote markup at all must not pay for
    -- a per-line HTML probe.
    local html = {
        page = "<p>正文一。</p><p>正文二。</p><p>正文三。</p>",
        lines = { "<p>正文一。</p>", "<p>正文二。</p>", "<p>正文三。</p>" },
    }
    local document, calls = documentWith(html)
    local kept = bodyLines(document)
    check("an ordinary page keeps every line", #kept == 3)
    check("and asks the engine for no per-line HTML (" .. calls() .. " calls)",
        calls() == 0)
end

do
    -- An inline <cite> arms the probe (the page scan is deliberately broad) but must not
    -- cost the reader a skipped paragraph.
    local paragraph = "<p>见<cite>《论语》</cite>所载，学而时习之。</p>"
    local html = {
        page = "<p>正文。</p>" .. paragraph .. "<p>正文。</p>",
        lines = { "<p>正文。</p>", paragraph, "<p>正文。</p>" },
    }
    local document, calls = documentWith(html)
    local kept = bodyLines(document)
    check("a paragraph citing a work is still body text", #kept == 3)
    check("though it did arm the per-line probe", calls() > 0)
end

print(string.format("quote_markup_spec: %s (%d checks, %d failures)",
    failures == 0 and "ok" or "FAILED", checks, failures))
if failures > 0 then error("quote_markup_spec failed", 0) end
