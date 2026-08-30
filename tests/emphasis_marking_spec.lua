-- SPDX-FileCopyrightText: Copyright (C) 2026 THE-XSX
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- Typefolio (文笺) - KOReader plugin
-- Released under the GNU Affero General Public License v3.0 or later.
-- See the LICENSE file in the project root for the full license text.

-- What the emphasis painter dots.
--
-- The bug this spec exists for: the old test was "does this node's HTML contain an
-- emphasis tag", and the answer was applied to the node's box. Semantic nodes are screen
-- *lines*; `html` is the parent paragraph's markup, shared by every line of it. So one
-- <strong> word dotted every line of the paragraph, full width -- and <b>/<strong> are
-- everywhere in Chinese web fiction. The painter now locates the run inside the paragraph
-- text and asks the document for its geometry, so the interesting cases are all about
-- *where* a run is found and what happens when it cannot be.
--
-- Run from the plugin root:
--   python3 runlua.py <plugin_dir> tests/emphasis_marking_spec.lua --lua 51

local EmphasisLayout = dofile("painters/emphasis_layout.lua")

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

local LINE_H = 30
local CHAR_W = 20

-- A paragraph laid out as N screen lines of the same width, the way book_context reports
-- one: every line carries the parent paragraph's html and its own xpointer offset.
local function paragraph(html, text, line_count)
    local nodes = {}
    for i = 1, (line_count or 1) do
        table.insert(nodes, {
            box = { x = 40, y = 100 + (i - 1) * LINE_H, w = 500, h = LINE_H },
            pos0 = string.format("/body/p[1]/text().%d", (i - 1) * 10),
            html = html,
            text = text,
        })
    end
    return { page = { viewport = { w = 600, h = 800 } }, nodes = nodes }
end

-- Stands in for BookContext:boxesForRange. Lays the paragraph out as one line of
-- fixed-width characters so a byte range maps to a predictable box, and records what it
-- was asked for -- the count is the per-page-turn engine cost.
local function makeResolver(opts)
    opts = opts or {}
    local calls = {}
    local resolver = function(node, range, text)
        table.insert(calls, { first = range.first, last = range.last,
            run = text:sub(range.first, range.last) })
        if opts.fails then return nil end
        local before = text:sub(1, range.first - 1)
        local _, prefix_chars = before:gsub("[%z\1-\127\194-\244]", "")
        local _, run_chars = text:sub(range.first, range.last):gsub("[%z\1-\127\194-\244]", "")
        local box = {
            x = 40 + prefix_chars * CHAR_W,
            y = opts.y or 100,
            w = run_chars * CHAR_W,
            h = LINE_H,
        }
        if opts.elsewhere then box.y = box.y + 400 end
        return { box }
    end
    return resolver, calls
end

local function build(snapshot, options)
    local merged = { enabled = true, size = 2, gap = 12 }
    for key, value in pairs(options or {}) do merged[key] = value end
    return EmphasisLayout.build(snapshot, merged)
end

-- ------------------------------------------------------------------ finding the run
local ranges = EmphasisLayout.emphasisRanges

local function onlyRun(html, text)
    local found = ranges(html, text)
    if #found ~= 1 then return nil end
    return text:sub(found[1].first, found[1].last)
end

check("<em> is found", onlyRun("<p>他说<em>不行</em>就走了</p>", "他说不行就走了") == "不行")
check("<strong> is found", onlyRun("<p>他说<strong>不行</strong>了</p>", "他说不行了") == "不行")
check("<b> is found", onlyRun("<p>他说<b>不行</b>了</p>", "他说不行了") == "不行")
check("<i> is found", onlyRun("<p>他说<i>不行</i>了</p>", "他说不行了") == "不行")
check("<u> is found", onlyRun("<p>他说<u>不行</u>了</p>", "他说不行了") == "不行")
check("an attribute on the tag does not hide it",
    onlyRun('<p>他说<em class="x">不行</em>了</p>', "他说不行了") == "不行")
check("an uppercase tag is found",
    onlyRun("<P>他说<EM>不行</EM>了</P>", "他说不行了") == "不行")

-- The near-misses that a bare "<b" / "<i" / "<u" test would have caught by accident.
check("<br> is not emphasis", #ranges("<p>一行<br/>二行</p>", "一行 二行") == 0)
check("<img> is not emphasis",
    #ranges('<p>看图<img src="a.png"/>吧</p>', "看图吧") == 0)
check("<ul> is not emphasis", #ranges("<ul><li>一</li></ul>", "一") == 0)
check("<blockquote> is not emphasis",
    #ranges("<blockquote><p>引文</p></blockquote>", "引文") == 0)
check("an unclosed tag is not a run", #ranges("<p>他说<em>不行", "他说不行") == 0)
check("an empty run is not a run", #ranges("<p>他说<em></em>不行</p>", "他说不行") == 0)

-- The same near-misses with a real run further along, which is where a loose tag match
-- does its damage: it opens at <img> and closes at the real </i>, and everything between
-- gets marked. Matching on the tag name alone is not enough -- the character after it
-- has to be whitespace or ">".
check("an <img> before an <i> run does not widen it",
    onlyRun('<p>看图<img src="a.png"/>然后<i>斜体</i>吧</p>', "看图然后斜体吧") == "斜体")
check("a <br> before a <b> run does not widen it",
    onlyRun("<p>一行<br/>然后<b>加粗</b>吧</p>", "一行 然后加粗吧") == "加粗")
check("a <ul> before a <u> run does not widen it",
    onlyRun("<div><ul><li>一</li></ul>然后<u>下划</u>吧</div>", "一 然后下划吧") == "下划")

-- The reason the search takes a position hint: a one-character run occurs all over a
-- paragraph, and the first occurrence is usually not the emphasized one.
local repeated = ranges("<p>他来了，他走了，<em>他</em>回来了。</p>", "他来了，他走了，他回来了。")
check("a repeated one-character run is located at the emphasized occurrence",
    #repeated == 1 and repeated[1].first == string.find("他来了，他走了，他回来了。", "他回来了", 1, true))

-- Two runs, in reading order, and nested markup reported once.
local two = ranges("<p><em>甲</em>和<strong>乙</strong></p>", "甲和乙")
check("two runs are both found in reading order",
    #two == 2 and two[1].first < two[2].first)
check("nested markup is one run, not two",
    #ranges("<p>他<strong><em>不行</em></strong>了</p>", "他不行了") == 1)
check("adjacent runs are merged",
    #ranges("<p><em>甲</em><em>乙</em></p>", "甲乙") == 1)

-- Text the run cannot be located in: under-mark rather than mark the wrong words.
check("a run whose text is not in the paragraph is skipped",
    #ranges("<p>他说<em>不行</em>了</p>", "完全不同的一段文字") == 0)
check("no text means no ranges", #ranges("<p><em>不行</em></p>", "") == 0)
check("no html means no ranges", #ranges("", "他说不行了") == 0)
check("an encoded entity inside the run is skipped rather than guessed",
    #ranges("<p>他说<em>a&amp;b</em>了</p>", "他说a&b了") == 0)

-- ------------------------------------------------------------------------ coverage
check("coverage of a short run in a long paragraph is small",
    EmphasisLayout.coverageOf("他说不行就走了", { { first = 7, last = 12 } }) < 0.4)
check("coverage of the whole paragraph is 1",
    EmphasisLayout.coverageOf("不行", { { first = 1, last = 6 } }) == 1)
check("coverage ignores spaces",
    EmphasisLayout.coverageOf("a b", { { first = 1, last = 1 } }) == 0.5)
check("no ranges is no coverage", EmphasisLayout.coverageOf("他说", {}) == 0)

-- --------------------------------------------------------------------- what gets dotted
--
-- The regression itself, stated as an assertion: a four-line paragraph with one
-- emphasized word gets dots under the word, on its line only.
local resolver, calls = makeResolver()
local html = "<p>他说<em>不行</em>就走了，后面还有很多很多很多的话。</p>"
local text = "他说不行就走了，后面还有很多很多很多的话。"
local rects = build(paragraph(html, text, 4), { emphasis_boxes = resolver })
check("one emphasized word is resolved once for the whole paragraph, not once per line",
    #calls == 1)
check("the resolver was asked for the emphasized run", calls[1] and calls[1].run == "不行")
check("dots are drawn for the run", #rects > 0)
local one_line = true
for _, rect in ipairs(rects) do
    if rect.y < 100 or rect.y > 100 + LINE_H + 4 then one_line = false end
end
check("every dot lands under the run's own line", one_line)
check("a two-character run gets a handful of dots, not a line's worth", #rects <= 4)

-- The shortcut: a paragraph that is emphasized end to end still dots every line, and
-- never calls the engine.
local whole_resolver, whole_calls = makeResolver()
local whole = build(paragraph("<p><strong>整段都是重点内容。</strong></p>",
    "整段都是重点内容。", 3), { emphasis_boxes = whole_resolver })
check("a fully emphasized paragraph needs no engine call", #whole_calls == 0)
check("a fully emphasized paragraph is dotted on every line", #whole > 0)
local lines_dotted = {}
for _, rect in ipairs(whole) do lines_dotted[rect.y] = true end
local line_count = 0
for _ in pairs(lines_dotted) do line_count = line_count + 1 end
check("all three lines of a fully emphasized paragraph are dotted", line_count == 3)

-- When geometry cannot be had, nothing is drawn: dotting the line box instead would put
-- the mark under narration.
local failing_resolver = makeResolver({ fails = true })
check("a run the document cannot place is left unmarked",
    #build(paragraph(html, text, 4), { emphasis_boxes = failing_resolver }) == 0)
check("no resolver means no dots",
    #build(paragraph(html, text, 4), {}) == 0)

-- The offset splice can address a text node in a different paragraph, so a run box that
-- does not sit on one of this paragraph's lines is rejected.
local elsewhere_resolver = makeResolver({ elsewhere = true })
check("a run box on someone else's line is rejected",
    #build(paragraph(html, text, 4), { emphasis_boxes = elsewhere_resolver }) == 0)

-- The common case has to stay free: no emphasis markup, no engine call, no rects.
local plain_resolver, plain_calls = makeResolver()
check("a paragraph with no emphasis is not dotted",
    #build(paragraph("<p>普通的一段话。</p>", "普通的一段话。", 3),
        { emphasis_boxes = plain_resolver }) == 0)
check("a paragraph with no emphasis costs no engine call", #plain_calls == 0)

-- Guards.
check("disabled draws nothing",
    #EmphasisLayout.build(paragraph(html, text, 2), { enabled = false }) == 0)
check("a snapshot with no viewport draws nothing",
    #build({ nodes = paragraph(html, text, 1).nodes }, { emphasis_boxes = resolver }) == 0)
check("an empty snapshot draws nothing", #build({ page = { viewport = { w = 600, h = 800 } } }) == 0)

-- A hand-built "emphasis" node is the run itself and needs no locating. semanticKind()
-- does not emit this today; the branch is kept for snapshots that do.
local kind_nodes = paragraph("<p>整行</p>", "整行", 2)
for _, node in ipairs(kind_nodes.nodes) do node.kind = "emphasis" end
check("a node whose kind is emphasis is dotted directly", #build(kind_nodes) > 0)

-- Dots stay inside the viewport even for a line at the very bottom edge.
local edge = paragraph("<p><strong>底部</strong></p>", "底部", 1)
edge.nodes[1].box = { x = 40, y = 800 - LINE_H, w = 500, h = LINE_H }
local edge_rects = build(edge)
local inside = true
for _, rect in ipairs(edge_rects) do
    if rect.y + rect.h > 800 or rect.x + rect.w > 600 then inside = false end
end
check("dots never leave the viewport", inside)

-- Dot size and spacing are device pixels, and the painter is the only place they can be
-- scaled -- the layout gets numbers, not a Screen. Source-level because instantiating
-- context_painter means stubbing half of KOReader for two arithmetic lines, and the
-- failure it guards against is silent: scaledOptions() scales `thickness`, which this
-- layout never reads, so unscaled 2px dots every 12px come out half size and twice as
-- dense as intended on a 300 DPI screen, with no menu row to compensate.
do
    local path = debug.getinfo(1, "S").source:sub(2):gsub("tests[/\\][^/\\]*$", "")
    local fh = io.open(path .. "painters/context_painter.lua", "r")
    local src = fh and fh:read("*a") or ""
    if fh then fh:close() end
    check("the painter scales the dot size for the screen",
        src:find("options.size = math.max(1, Screen:scaleBySize", 1, true) ~= nil)
    check("the painter scales the dot spacing for the screen",
        src:find("options.gap = math.max(4, Screen:scaleBySize", 1, true) ~= nil)

    -- The dot size and spacing are written as a number in three places: the schema
    -- default in core/config.lua, the painter's fallback, and the layout's. normalize()
    -- always fills the emphasis_painter section from the schema, so both fallbacks are
    -- unreachable in the reader and are purely a second copy waiting to drift. Pinned
    -- here rather than removed: giving a pure layout function a dependency on the schema
    -- module would cost more than the duplication does.
    local layout_fh = io.open(path .. "painters/emphasis_layout.lua", "r")
    local layout_src = layout_fh and layout_fh:read("*a") or ""
    if layout_fh then layout_fh:close() end
    local Config = dofile(path .. "core/config.lua")
    local defaults = Config.defaults().emphasis_painter
    check("the schema still has a dot size and spacing to agree with",
        type(defaults.size) == "number" and type(defaults.gap) == "number")
    check("the painter's dot size fallback matches the schema (" .. tostring(defaults.size) .. ")",
        src:find("tonumber(self.emphasis_painter.size) or " .. defaults.size, 1, true) ~= nil)
    check("the painter's spacing fallback matches the schema (" .. tostring(defaults.gap) .. ")",
        src:find("tonumber(self.emphasis_painter.gap) or " .. defaults.gap, 1, true) ~= nil)
    check("the layout's dot size fallback matches the schema",
        layout_src:find("tonumber(options.size) or " .. defaults.size, 1, true) ~= nil)
    check("the layout's spacing fallback matches the schema",
        layout_src:find("tonumber(options.gap) or " .. defaults.gap, 1, true) ~= nil)
end

print(string.format("emphasis_marking_spec: %s (%d checks, %d failures)",
    failures == 0 and "ok" or "FAILED", checks, failures))
if failures > 0 then error("emphasis_marking_spec failed", 0) end
