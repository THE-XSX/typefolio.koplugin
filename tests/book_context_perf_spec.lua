local PerfCounter = dofile("core/perf_counter.lua")
local BookContext = dofile("core/book_context.lua")

local now = 0
local function tick(value, result)
    now = now + value
    return result
end

local boxes = {
    { x = 20, y = 40, w = 400, h = 24 },
    { x = 20, y = 70, w = 380, h = 24 },
}

local document = {
    getCurrentPage = function() return tick(1, 5) end,
    getVisiblePageNumberCount = function() return tick(1, 1) end,
    getXPointer = function() return tick(1, "/body/p[1]/text().0") end,
    getPageCount = function() return tick(1, 100) end,
    getPageXPointer = function() return tick(1, "/body/p[3]/text().0") end,
    compareXPointers = function() return tick(1, 1) end,
    getScreenBoxesFromPositions = function() return tick(4, boxes) end,
    getNearestWordFromPosition = function()
        return tick(3, { pos0 = "/body/p[1]/text().0" })
    end,
    getHTMLFromXPointer = function()
        return tick(5, "<p class=\"dialogue\">“Hello.”</p>")
    end,
    getTextFromPositions = function()
        return tick(2, {
            text = "“Hello.”",
            pos0 = "/body/p[1]/text().0",
            sboxes = boxes,
        })
    end,
}

local toc = {
    toc = { { title = "Chapter" } },
    getTocTitleByPage = function() return tick(1, "Chapter") end,
    isChapterStart = function() return tick(1, true) end,
    isChapterEnd = function() return tick(1, false) end,
}

local counter = PerfCounter.new{
    enabled = true,
    clock = function() return now end,
}
local context = BookContext.new{
    ui = { document = document, toc = toc },
    screen_size = function() return 600, 800 end,
    perf = counter,
}

local first = context:snapshot{
    chapter = true,
    toc = true,
    semantics = true,
    semantic_profile = "full",
    line_mode = "all",
}
assert(#first.lines == 2)
assert(#first.semantics == 2)

local initial = counter:snapshot().metrics
assert(initial["native.document.getScreenBoxes.visible"].calls == 1)
assert(initial["native.document.getNearestWord.semantic.center"].calls == 2)
assert(initial["native.document.getText.line"].calls == 2)
assert(initial["native.document.getHTML.semantic"].calls == 1)
assert(initial["phase.book_context.semantics"].calls == 1)

context:snapshot{
    chapter = true,
    toc = true,
    semantics = true,
    semantic_profile = "full",
    line_mode = "all",
}
local cached = counter:snapshot().metrics
assert(cached["native.document.getScreenBoxes.visible"].calls == 1)
assert(cached["native.document.getText.line"].calls == 2)
assert(cached["cache.raw_lines.hit"].calls >= 1)
assert(cached["cache.semantics.hit"].calls == 1)

context:invalidate("page_update")
context:snapshot{ line_mode = "all" }
local invalidated = counter:snapshot().metrics
assert(invalidated["cache.book_context.invalidate.page_update"].calls == 1)
assert(invalidated["native.document.getScreenBoxes.visible"].calls == 2)

local dialogue_counter = PerfCounter.new{
    enabled = true,
    clock = function() return now end,
}
local dialogue_context = BookContext.new{
    ui = { document = document, toc = toc },
    screen_size = function() return 600, 800 end,
    perf = dialogue_counter,
}
local dialogue = dialogue_context:snapshot{
    semantics = true,
    semantic_profile = "dialogue",
}
assert(#dialogue.semantics == 2)
local dialogue_metrics = dialogue_counter:snapshot().metrics
assert(dialogue_metrics["native.document.getNearestWord.semantic.center"] == nil)
assert(dialogue_metrics["native.document.getHTML.semantic"] == nil)
assert(dialogue_metrics["native.document.getText.line"].calls == 2)

local body_boxes = {
    { x = 20, y = 40, w = 500, h = 24 },
    { x = 50, y = 70, w = 465, h = 24 },
}
local body_document = {
    getCurrentPage = function() return 5 end,
    getVisiblePageNumberCount = function() return 1 end,
    getXPointer = function() return "/body/p[1]/text().0" end,
    getPageCount = function() return 100 end,
    getPageXPointer = function() return "/body/p[3]/text().0" end,
    compareXPointers = function() return 1 end,
    getScreenBoxesFromPositions = function() return body_boxes end,
    getNearestWordFromPosition = function()
        return { pos0 = "/body/blockquote[1]/text().0" }
    end,
    getHTMLFromXPointer = function(xpointer)
        if xpointer:find("blockquote", 1, true) then
            return "<blockquote>Quoted text</blockquote>"
        end
        return "<p>Body text</p>"
    end,
    getTextFromPositions = function(_, from)
        if from.x > 30 then
            return {
                text = "Quoted text",
                pos0 = "/body/blockquote[1]/text().0",
            }
        end
        return {
            text = "Body text",
            pos0 = "/body/p[1]/text().0",
        }
    end,
}
local body_counter = PerfCounter.new{
    enabled = true,
    clock = function() return now end,
}
local body_context = BookContext.new{
    ui = { document = body_document },
    screen_size = function() return 600, 800 end,
    perf = body_counter,
}

local body_snapshot = body_context:snapshot{
    line_mode = "body",
    skip_headings = true,
    skip_blockquotes = true,
}
assert(#body_snapshot.lines == 1)
local body_metrics = body_counter:snapshot().metrics
assert(body_metrics["native.document.getNearestWord.body"] == nil)

body_context:snapshot{
    semantics = true,
    semantic_profile = "dialogue",
}
body_metrics = body_counter:snapshot().metrics
assert(body_metrics["native.document.getText.line"].calls == 2)
-- Both lines are now resolved during the body pass (the full-width line gets the cheap
-- opportunistic xpointer probe), so the dialogue pass that follows reads both from the
-- shared per-box cache instead of calling into the engine again. Total native line-text
-- calls across the two passes stays at one per line.
assert(body_metrics["cache.line_text.hit"].calls == 2)

body_document.getTextFromPositions = function(_, from)
    return { text = from.x > 30 and "Quoted text" or "Body text" }
end
local fallback_counter = PerfCounter.new{
    enabled = true,
    clock = function() return now end,
}
local fallback_context = BookContext.new{
    ui = { document = body_document },
    screen_size = function() return 600, 800 end,
    perf = fallback_counter,
}
local fallback_snapshot = fallback_context:snapshot{
    line_mode = "body",
    skip_headings = true,
    skip_blockquotes = true,
}
assert(#fallback_snapshot.lines == 1)
assert(fallback_counter:snapshot().metrics["native.document.getNearestWord.body"].calls == 1)

-- A <blockquote> that the book's CSS renders at full width with no indent is geometrically
-- identical to body text, so it used to fall through the fast path and get underlined.
-- The xpointer's element path still names the tag, so the cheap probe catches it without
-- reading any HTML and without a second engine lookup.
local wide_boxes = {
    { x = 20, y = 40, w = 500, h = 24 },  -- body paragraph
    { x = 20, y = 70, w = 500, h = 24 },  -- full-width blockquote, line 1
    { x = 20, y = 100, w = 500, h = 24 }, -- full-width blockquote, line 2
}
local wide_document = {
    getCurrentPage = function() return 5 end,
    getVisiblePageNumberCount = function() return 1 end,
    getXPointer = function() return "/body/DocFragment[2]/body/p[7]/text().0" end,
    getPageCount = function() return 100 end,
    getPageXPointer = function() return "/body/DocFragment[2]/body/p[9]/text().0" end,
    compareXPointers = function() return 1 end,
    getScreenBoxesFromPositions = function() return wide_boxes end,
    getNearestWordFromPosition = function()
        error("full-width probe must not fall back to a second lookup")
    end,
    getHTMLFromXPointer = function()
        error("full-width probe must not read HTML")
    end,
    getTextFromPositions = function(_, from)
        if from.y >= 70 then
            -- One paragraph, two lines: same element, different character offsets.
            return {
                text = "Quoted text",
                pos0 = "/body/DocFragment[2]/body/blockquote[1]/p[1]/text()." .. tostring(from.y),
            }
        end
        return { text = "Body text", pos0 = "/body/DocFragment[2]/body/p[7]/text().0" }
    end,
}
local wide_counter = PerfCounter.new{
    enabled = true,
    clock = function() return now end,
}
local wide_context = BookContext.new{
    ui = { document = wide_document },
    screen_size = function() return 600, 800 end,
    perf = wide_counter,
}
local wide_snapshot = wide_context:snapshot{
    line_mode = "body",
    skip_headings = true,
    skip_blockquotes = true,
}
assert(#wide_snapshot.lines == 1)
assert(wide_snapshot.lines[1].y == 40)
local wide_metrics = wide_counter:snapshot().metrics
assert(wide_metrics["native.document.getHTML.body"] == nil)
assert(wide_metrics["native.document.getNearestWord.body"] == nil)
-- wide_document has no getHTMLFromXPointers, so the case above is also the fallback for
-- KOReader builds without the range API: probe every full-width line, as before.
assert(wide_metrics["native.document.getHTML.page"] == nil)

-- Page-level quote pre-check. Probing every full-width line costs one xpointer lookup per
-- line (20 on a 20-line page) to answer a question that is the same for the whole page, so
-- ask the engine once per page turn instead and only probe when the answer is yes.
local precheck_boxes = {
    { x = 20, y = 40, w = 500, h = 24 },  -- body paragraph
    { x = 20, y = 70, w = 500, h = 24 },  -- full-width quote, line 1
    { x = 20, y = 100, w = 500, h = 24 }, -- full-width quote, line 2
}
-- page_html is what the range read returns; quote_path is the element path the lower two
-- lines resolve to; para_html is the markup a per-paragraph read finds for that element.
local function precheckDocument(page_html, quote_path, para_html)
    local reads = { page = 0, flags = nil, endpoints = 0 }
    local document = {
        getCurrentPage = function() return 5 end,
        getVisiblePageNumberCount = function() return 1 end,
        getXPointer = function() return "/body/DocFragment[2]/body/p[7]/text().0" end,
        getPageCount = function() return 100 end,
        getPageXPointer = function() return "/body/DocFragment[2]/body/p[9]/text().0" end,
        compareXPointers = function() return 1 end,
        getScreenBoxesFromPositions = function() return precheck_boxes end,
        getNearestWordFromPosition = function() return nil end,
        getHTMLFromXPointers = function(_, xp0, xp1, flags)
            assert(type(xp0) == "string" and type(xp1) == "string")
            reads.page = reads.page + 1
            reads.flags = flags
            return page_html
        end,
        getHTMLFromXPointer = function(_, xpointer)
            if xpointer:find(quote_path, 1, true) then return para_html end
            return "<p>Body text</p>"
        end,
        getTextFromPositions = function(_, from)
            if from.y >= 70 then
                -- One paragraph, two lines: same element, different character offsets.
                return { text = "Quoted text", pos0 = quote_path .. "/text()." .. tostring(from.y) }
            end
            return { text = "Body text", pos0 = "/body/DocFragment[2]/body/p[7]/text().0" }
        end,
    }
    return document, reads
end

local function precheckSnapshot(document)
    local counter = PerfCounter.new{ enabled = true, clock = function() return now end }
    local context = BookContext.new{
        ui = { document = document },
        screen_size = function() return 600, 800 end,
        perf = counter,
    }
    return context:snapshot{
        line_mode = "body",
        skip_headings = true,
        skip_blockquotes = true,
    }, counter:snapshot().metrics
end

-- An ordinary page: one range read settles it, and no line is probed at all. This is the
-- case that has to stay cheap, because it is nearly every page in the book.
local plain_document, plain_reads = precheckDocument(
    "<p>Body</p><p>Body</p><p>Body</p>", "/body/DocFragment[2]/body/p[8]", "<p>Body text</p>")
-- Counted rather than raised: textForBox runs the engine call inside safeCall, so an error()
-- here would be swallowed and the assertion would never fail.
local plain_probes = 0
plain_document.getTextFromPositions = function()
    plain_probes = plain_probes + 1
    return { text = "Body text", pos0 = "/body/DocFragment[2]/body/p[7]/text().0" }
end
local precheck_plain, precheck_plain_metrics = precheckSnapshot(plain_document)
assert(#precheck_plain.lines == 3)
assert(plain_probes == 0)
assert(plain_reads.page == 1)
-- 0x1001 is the flag set ReaderLink uses for structural HTML with no CSS.
assert(plain_reads.flags == 0x1001)
assert(precheck_plain_metrics["native.document.getHTML.page"].calls == 1)
assert(precheck_plain_metrics["native.document.getText.line"] == nil)
assert(precheck_plain_metrics["data.page_quote_markup.false"].calls == 1)

-- A page that does contain a full-width <blockquote>: the pre-check says yes, so the lines
-- get probed and the element path names the tag, exactly as before the pre-check existed.
local quote_document, quote_reads = precheckDocument(
    "<p>Body</p><blockquote><p>Quoted</p></blockquote>",
    "/body/DocFragment[2]/body/blockquote[1]/p[1]", "<blockquote>Quoted text</blockquote>")
local precheck_quote, precheck_quote_metrics = precheckSnapshot(quote_document)
assert(#precheck_quote.lines == 1)
assert(precheck_quote.lines[1].y == 40)
assert(quote_reads.page == 1)
assert(precheck_quote_metrics["data.page_quote_markup.true"].calls == 1)

-- New capability: a full-width <div class="quote"> is invisible to the xpointer's element
-- path, so probing per line could never catch it. The page read finds the marker, which
-- promotes these lines to the HTML pass -- one read per paragraph, not per line.
local div_document, div_reads = precheckDocument(
    "<p>Body</p><div class=\"quote\"><p>Quoted</p></div>",
    "/body/DocFragment[2]/body/div[3]/p[1]", "<div class=\"quote\">Quoted text</div>")
local precheck_div, precheck_div_metrics = precheckSnapshot(div_document)
assert(#precheck_div.lines == 1)
assert(precheck_div.lines[1].y == 40)
assert(div_reads.page == 1)
assert(precheck_div_metrics["native.document.getHTML.body"].calls == 2)

-- The engine answering "I cannot tell you" must mean "probe per line", not "no quotes here".
-- Writing the gate as `skip_blockquotes and self:_pageHasQuoteMarkup() or false` collapses
-- nil to false and silently stops detecting full-width quotes; this is that regression.
local unknown_document = precheckDocument(
    nil, "/body/DocFragment[2]/body/blockquote[1]/p[1]", "<blockquote>Quoted text</blockquote>")
-- Counted, not raised, for the same safeCall reason as above.
local unknown_html_reads = 0
unknown_document.getHTMLFromXPointer = function()
    unknown_html_reads = unknown_html_reads + 1
    return "<blockquote>Quoted text</blockquote>"
end
local precheck_unknown, precheck_unknown_metrics = precheckSnapshot(unknown_document)
assert(#precheck_unknown.lines == 1)
assert(precheck_unknown.lines[1].y == 40)
assert(unknown_html_reads == 0)
assert(precheck_unknown_metrics["data.page_quote_markup.false"] == nil)
assert(precheck_unknown_metrics["data.page_quote_markup.true"] == nil)
assert(precheck_unknown_metrics["native.document.getText.line"].calls == 3)

-- Headings and full-width body text must survive the widened probe untouched.
wide_document.getTextFromPositions = function(_, from)
    if from.y >= 70 then
        return { text = "Body text", pos0 = "/body/DocFragment[2]/body/p[8]/text().0" }
    end
    return { text = "Body text", pos0 = "/body/DocFragment[2]/body/p[7]/text().0" }
end
local plain_context = BookContext.new{
    ui = { document = wide_document },
    screen_size = function() return 600, 800 end,
}
assert(#plain_context:snapshot{
    line_mode = "body",
    skip_headings = true,
    skip_blockquotes = true,
}.lines == 3)

-- Element-path cache: every line of a paragraph carries its own character offset, so
-- keying DOM results on the raw xpointer made a multi-line quote pay for the same HTML
-- read once per line. One read per paragraph is enough.
local indented_boxes = {
    { x = 20, y = 40, w = 500, h = 24 }, -- body paragraph, sets the page bounds
    -- Indented on the left only: a symmetric inset would trip the centered-heading
    -- heuristic first and never reach the blockquote check.
    { x = 60, y = 70, w = 460, h = 24 }, -- indented quote, line 1
    { x = 60, y = 100, w = 460, h = 24 }, -- indented quote, line 2
}
local indented_document = {
    getCurrentPage = function() return 5 end,
    getVisiblePageNumberCount = function() return 1 end,
    getXPointer = function() return "/body/DocFragment[2]/body/p[7]/text().0" end,
    getPageCount = function() return 100 end,
    getPageXPointer = function() return "/body/DocFragment[2]/body/p[9]/text().0" end,
    compareXPointers = function() return 1 end,
    getScreenBoxesFromPositions = function() return indented_boxes end,
    getNearestWordFromPosition = function() return nil end,
    -- The element name gives nothing away here, so only the markup can classify it.
    getHTMLFromXPointer = function(_, xpointer)
        if xpointer:find("div", 1, true) then
            return "<blockquote>Quoted text</blockquote>"
        end
        return "<p>Body text</p>"
    end,
    getTextFromPositions = function(_, from)
        if from.x > 30 then
            return {
                text = "Quoted text",
                pos0 = "/body/DocFragment[2]/body/div[3]/p[1]/text()." .. tostring(from.y),
            }
        end
        return { text = "Body text", pos0 = "/body/DocFragment[2]/body/p[7]/text().0" }
    end,
}
local indented_counter = PerfCounter.new{
    enabled = true,
    clock = function() return now end,
}
local indented_context = BookContext.new{
    ui = { document = indented_document },
    screen_size = function() return 600, 800 end,
    perf = indented_counter,
}
local indented_snapshot = indented_context:snapshot{
    line_mode = "body",
    skip_headings = true,
    skip_blockquotes = true,
}
assert(#indented_snapshot.lines == 1)
assert(indented_snapshot.lines[1].y == 40)
assert(indented_counter:snapshot().metrics["native.document.getHTML.body"].calls == 1)

local raw_calls, public_calls = 0, 0
local direct_counter = PerfCounter.new{
    enabled = true,
    clock = function() return now end,
}
local direct_context = BookContext.new{
    ui = {
        document = {
            _document = {
                getTextFromPositions = function()
                    raw_calls = raw_calls + 1
                    return {
                        text = "Raw text",
                        pos0 = "/body/p[1]/text().0",
                    }
                end,
            },
            getTextFromPositions = function()
                public_calls = public_calls + 1
                return {
                    text = "Public text",
                    pos0 = "/body/p[1]/text().0",
                }
            end,
        },
    },
    screen_size = function() return 600, 800 end,
    perf = direct_counter,
}
local direct_text, direct_pos0 = direct_context:textForBox{
    x = 20, y = 40, w = 500, h = 24,
}
assert(direct_text == "Raw text")
assert(direct_pos0 == "/body/p[1]/text().0")
assert(raw_calls == 1)
assert(public_calls == 0)
local direct_metrics = direct_counter:snapshot().metrics
assert(direct_metrics["native.document.getTextRange.line"].calls == 1)
assert(direct_metrics["native.document.getText.line"] == nil)

local endpoint_page
local range_context = BookContext.new{
    ui = {
        document = {
            getCurrentPage = function() return 5 end,
            getVisiblePageNumberCount = function() return 1 end,
            getXPointer = function() return "/body/p[1]/text().0" end,
            getPageCount = function() return 100 end,
            getPageXPointer = function(_, page)
                endpoint_page = page
                return "/body/p[3]/text().0"
            end,
            compareXPointers = function() return 1 end,
            getScreenBoxesFromPositions = function() return boxes end,
        },
    },
    screen_size = function() return 600, 800 end,
}
range_context:snapshot{ line_mode = "all" }
assert(endpoint_page == 6)

print("book_context_perf_spec: ok")
