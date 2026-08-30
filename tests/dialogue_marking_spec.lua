-- SPDX-FileCopyrightText: Copyright (C) 2026 THE-XSX
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- Typefolio (文笺) - KOReader plugin
-- Released under the GNU Affero General Public License v3.0 or later.
-- See the LICENSE file in the project root for the full license text.

-- What the dialogue painter marks.
--
-- The policy is deliberately blunt: quote marks are the whole test. There is history
-- behind that, and it is worth keeping so nobody re-derives the rejected version.
--
-- dialogue_layout used to carry an unused speech/narration classifier -- a coverage
-- ratio plus a leading-mark check. Wiring it in and measuring it on a careful
-- translation (《窄门》, 915 paragraphs, 443 with a quote) showed the ratio alone
-- discarded 91 paragraphs, half of them real speech introduced by an attribution;
-- adding an attribution check recovered those 45 and held 397/443. Good numbers -- on a
-- book with careful punctuation.
--
-- It was still removed. The books this painter exists for are web fiction, where a line
-- is routinely a bare “…” with no attribution, no colon, and no reliable structure to
-- reason from. Any rule sharp enough to exclude 「他说“好”便走了」 also drops real speech
-- there, and a reader who turned quote highlighting on would rather see a cited word
-- highlighted than miss dialogue. Recall over precision.
--
-- Recall over precision about *which* text is quoted, that is -- not about how much of the
-- row to cover. Those pull in opposite directions and the second one lost: a whole-line box
-- is only used where the build cannot resolve sub-line geometry at all. Where it can and a
-- run still will not place, the run goes unmarked. See the 2026-08-22 section below.
--
-- Run from the plugin root:
--   python3 runlua.py <plugin_dir> <plugin_dir>/tests/dialogue_marking_spec.lua

local DialogueLayout = dofile("painters/dialogue_layout.lua")
-- Only for DIALOGUE_INSET_MAX: the last section checks the menu's range against what the
-- painter can actually draw, which is the failure mode the divider-thickness bug had.
local Config = dofile("core/config.lua")

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

local function build(text, options)
    local snapshot = {
        page = { viewport = { w = 600, h = 800 } },
        nodes = {
            {
                box = { x = 40, y = 100, w = 500, h = 30 },
                pos0 = "/body/p[1]/text().0",
                text = text,
                screen_text = text,
            },
        },
    }
    local merged = { enabled = true, lang = "all", thickness = 1, mode = "tint" }
    for key, value in pairs(options or {}) do merged[key] = value end
    return DialogueLayout.build(snapshot, merged)
end

-- ------------------------------------------------------- the shapes web fiction uses

-- No attribution at all, which is the common case and the reason the classifier went.
check("a bare utterance is marked", #build("“你来了。”") > 0)
check("a bare utterance with no closing punctuation is marked",
    #build("“你来了”") > 0)
check("an utterance followed by an attribution is marked",
    #build("“在那里！”马脸男子忙指去。") > 0)
check("an attribution followed by an utterance is marked",
    #build("马脸男子忙指去，“在那里！”") > 0)
check("a colon-introduced utterance is marked",
    #build("他说道：“不管怎么说，白色也算丧服吧。”") > 0)
check("dialogue with no speaker marked at all is still marked",
    #build("“你到底想说什么”“我也不知道”") > 0)
check("a fullwidth indent before the mark does not hide it",
    #build("　　“你来了。”") > 0)
check("「」 marks count", #build("「そうですか」") > 0)
check("straight ASCII quotes count", #build('"Well?" he said.') > 0)

-- The accepted cost of casting a wide net, asserted so it reads as a decision rather
-- than an oversight.
check("a cited word inside narration is marked too -- accepted",
    #build("除了花园，一天里剩下的时光我们都在“学习室”里度过。") > 0)
check("so is a quoted aphorism", #build("我想起那句“伟大的心以散布自己纷乱的心情为耻”。") > 0)

check("text with no quote mark is never marked",
    #build("第二天，她又换上了黑色饰带。") == 0)
check("an unpaired opening mark is not a quote",
    #build("他还没有说完，“") == 0)
check("empty text is not marked", #build("") == 0)

-- ------------------------------------------------------------------ all three modes

for _, mode in ipairs({ "tint", "underline", "side_bar" }) do
    check(mode .. ": marks a bare utterance", #build("“你来了。”", { mode = mode }) > 0)
    check(mode .. ": marks a cited word", #build("我们都在“学习室”里度过。", { mode = mode }) > 0)
    check(mode .. ": leaves quoteless narration alone",
        #build("第二天，她又换上了黑色饰带。", { mode = mode }) == 0)
end

-- ------------------------------------------- per quote when the geometry is available

do
    -- Casting a wide net does not mean painting wide: given sub-line geometry, only the
    -- quoted run is painted, and the narration around it is untouched.
    local narration = "除了花园，一天里剩下的时光我们都在“学习室”里度过。"
    local resolved = build(narration, {
        quote_boxes = function(node)
            return { { x = node.box.x + 10, y = node.box.y, w = 40, h = node.box.h } }
        end,
    })
    check("with a resolver only the quoted run is painted",
        #resolved == 1 and resolved[1].w == 40)

    -- A resolver that cannot place the run marks nothing. Reported from the device on
    -- 2026-08-22: on a Calibre edition whose utterances are wrapped in
    -- <span class="dialogue">, the resolver was handed a paragraph-wide offset spliced onto
    -- the narration node's pointer, could not place it, and the painter tinted the whole
    -- row instead -- narration included, stopping exactly at the span boundary. Where the
    -- engine can place quoted runs, an unplaceable one has to go unmarked: losing a tint is
    -- cosmetic, tinting narration is the bug.
    local unplaceable = build(narration, { quote_boxes = function() return nil end })
    check("a resolver that places nothing marks nothing, not the whole line",
        #unplaceable == 0)

    -- The line box is not gone, it is just last: on a build with no sub-line geometry at
    -- all there is no better answer, which is what every check above this section exercises.
    local no_resolver = build(narration)
    check("with no resolver at all the whole line is still painted",
        #no_resolver == 1 and no_resolver[1].w > 40)
end

do
    -- A paragraph that is almost entirely one utterance skips resolution: there is
    -- nothing to separate, and asking would only cost engine calls.
    local asked = 0
    local rects = build("“你也来了。”", {
        quote_boxes = function() asked = asked + 1; return nil end,
    })
    check("an all-quote paragraph is painted without asking the engine",
        #rects > 0 and asked == 0)
end

-- ------------------------------- two utterances with a speech tag wedged between them

do
    -- Reported from the device: a paragraph that opens and closes with speech and has
    -- only a few narration characters in the middle came out highlighted end to end.
    -- The ratio shortcut was to blame -- long utterances either side of a short speech
    -- tag clear 0.85 comfortably -- so it now also requires the quoted text to be a
    -- single run.
    local split = "“这件事我早就想明白了，只是一直没有说出口。”他说，“不必再提。”"
    check("the reported shape does clear the ratio bar",
        DialogueLayout.quoteCoverage(split, "all") >= 0.85)
    check("but it is no longer treated as one utterance",
        not DialogueLayout.isPureQuoteLine(split, "all"))
    check("nor is a pair of utterances with nothing between them",
        not DialogueLayout.isPureQuoteLine("“你来了。”“坐吧。”", "all"))
    check("while a single utterance still is",
        DialogueLayout.isPureQuoteLine("“你来了，坐吧。”", "all"))
    check("including a one-word one, which is why the shortcut exists",
        DialogueLayout.isPureQuoteLine("“轰”", "all"))

    local asked = 0
    local rects = build(split, {
        quote_boxes = function(node, range)
            asked = asked + 1
            return { { x = node.box.x + range.first, y = node.box.y, w = 30, h = node.box.h } }
        end,
    })
    check("both utterances are resolved separately", asked == 2 and #rects == 2)
    check("and the speech tag between them is left unpainted",
        rects[1].w == 30 and rects[2].w == 30)

    -- Unchanged where the engine cannot help *at all*: better a whole line than nothing.
    local fallback = build(split)
    check("with no resolver it still falls back to the whole line",
        #fallback == 1 and fallback[1].w > 30)

    -- But this is the shape that made the fallback dangerous: the speech tag sits between
    -- the two utterances, so covering the row to salvage them highlights it as well.
    local unplaceable = build(split, { quote_boxes = function() return nil end })
    check("while an unplaceable pair leaves the speech tag between them alone",
        #unplaceable == 0)

    -- A leading fullwidth indent must not count against a short exclamation, which is
    -- why the shortcut measures the trimmed text.
    check("a leading indent does not spoil the shortcut",
        DialogueLayout.isPureQuoteLine("　　“轰”", "all"))
end

-- ------------------------------------------------------------ one scan per paragraph

do
    -- The quote sweep is the hot path here: four patterns over the string plus a sort
    -- and an overlap merge, on every visible line of every page. build() asked three
    -- separate questions and each re-ran it -- is there a quote, is it one utterance,
    -- where are the runs. It now scans once and shares the answer.
    local scans = 0
    local real = DialogueLayout.quoteRanges
    DialogueLayout.quoteRanges = function(...)
        scans = scans + 1
        return real(...)
    end
    local ok, err = pcall(build, "“这件事我早就想明白了。”他说，“不必再提。”",
        { quote_boxes = function() return nil end })
    DialogueLayout.quoteRanges = real
    check("build did not error while instrumented", ok, err)
    check("the paragraph is scanned exactly once (was three times)", scans == 1)

    -- And a paragraph with no quote at all costs exactly one scan, nothing else.
    scans = 0
    DialogueLayout.quoteRanges = function(...)
        scans = scans + 1
        return real(...)
    end
    build("第二天，她又换上了黑色饰带。")
    DialogueLayout.quoteRanges = real
    check("quoteless narration costs one scan and stops", scans == 1)
end

-- ------------------------------------------------------- a paragraph over three lines

do
    -- Mixed narration and speech, so it does not take the all-quote shortcut and the
    -- resolver is actually consulted.
    local paragraph = "他停下来，“这句话很长。”然后就走了，外面的雨一直没有停，" ..
        "远处的灯火在水汽里显得格外模糊，像是随时都会熄灭。"
    local snapshot = {
        page = { viewport = { w = 600, h = 800 } },
        nodes = {},
    }
    for i = 0, 2 do
        table.insert(snapshot.nodes, {
            box = { x = 40, y = 100 + i * 30, w = 500, h = 30 },
            pos0 = "/body/p[1]/text()." .. (i * 12),
            text = paragraph,
            screen_text = "行" .. i,
        })
    end
    check("the fixture is not an all-quote paragraph",
        not DialogueLayout.isPureQuoteLine(paragraph, "all"))
    local resolved = DialogueLayout.build(snapshot, {
        enabled = true, lang = "all", thickness = 1, mode = "tint",
        quote_boxes = function(node)
            return { { x = node.box.x, y = node.box.y, w = 100, h = node.box.h } }
        end,
    })
    -- Resolved once for the paragraph, not once per line: painting the same pixels
    -- three times would darken them three times.
    check("sub-line geometry is resolved once per paragraph", #resolved == 1)

    local fallback = DialogueLayout.build(snapshot, {
        enabled = true, lang = "all", thickness = 1, mode = "tint",
    })
    check("but a whole-line fallback still covers every visible row", #fallback == 3)
end

-- ------------------------------------- an utterance that fills all but the last few chars

do
    -- Reported from the device on 2026-08-24: 《窄门》 p.21, the tint covered the two rows
    -- of an utterance *and* the 母亲大 that follows the closing mark on the second row,
    -- while the 嚷道。 on the third row stayed clean.
    --
    -- Not the offset bug fixed on 2026-08-22: this paragraph never reaches the resolver.
    -- Its utterance is wrapped in a <span>, so the `dialogue` profile stitches the rows that
    -- *begin* inside that text node -- and the second of them carries the following node's
    -- first three characters along with it. The stitched unit is then 31 quoted characters
    -- out of 34, which cleared the old 0.85 ratio bar, and the ratio bar's whole point was
    -- to skip the engine and paint the row boxes. The 15% the bar tolerated is exactly the
    -- narration that got tinted.
    local UTTERANCE = "“她肩上的红色披肩呢，这也叫‘丧服’吗？弗洛拉，你别气我了！”"
    local FOREIGN_TAIL = "母亲大"            -- lives in the next text node, shares row 2
    local unit = UTTERANCE .. FOREIGN_TAIL

    check("the reported shape does clear the old ratio bar",
        DialogueLayout.quoteCoverage(unit, "all") >= 0.85)
    check("but a unit with narration in it is not one utterance",
        not DialogueLayout.isPureQuoteLine(unit, "all"))
    check("while the utterance on its own still is",
        DialogueLayout.isPureQuoteLine(UTTERANCE, "all"))

    -- Two rows keyed to the same text node, as the stitch produces them: the unit's text is
    -- the concatenation of both rows, so row 2's box spans the foreign tail as well.
    local snapshot = {
        page = { viewport = { w = 600, h = 800 } },
        nodes = {
            {
                box = { x = 40, y = 100, w = 500, h = 30 },
                pos0 = "/body/p[1]/span[1]/text().0",
                screen_text = "“她肩上的红色披肩呢，这也叫‘丧",
            },
            {
                box = { x = 40, y = 130, w = 500, h = 30 },
                pos0 = "/body/p[1]/span[1]/text().15",
                screen_text = "服’吗？弗洛拉，你别气我了！”" .. FOREIGN_TAIL,
            },
        },
    }
    local function run(options)
        local merged = { enabled = true, lang = "all", thickness = 1, mode = "tint" }
        for key, value in pairs(options or {}) do merged[key] = value end
        return DialogueLayout.build(snapshot, merged)
    end

    local asked = 0
    local resolved = run{
        quote_boxes = function(node, range)
            asked = asked + 1
            return { { x = node.box.x, y = node.box.y, w = 120, h = node.box.h } }
        end,
    }
    check("the engine is consulted instead of covering the rows", asked == 1)
    check("and only what it placed is painted",
        #resolved == 1 and resolved[1].w == 120)
    for _, rect in ipairs(resolved) do
        check("no row box reached the paint list", rect.w ~= 500)
    end

    -- The trade this makes, stated so it is a decision: where the engine cannot place the
    -- run, the utterance now goes unmarked rather than being covered along with the
    -- narration behind it. Same call as every other path in this file.
    check("an unplaceable run leaves the narration alone",
        #run{ quote_boxes = function() return nil end } == 0)

    -- Unchanged where there is no sub-line geometry at all.
    check("with no resolver the rows are still covered", #run() == 2)

    -- And the case the shortcut exists for keeps its free ride: a unit that is nothing but
    -- the utterance has no narration to protect, so its row boxes are exactly right.
    local free_asked = 0
    local free = DialogueLayout.build({
        page = { viewport = { w = 600, h = 800 } },
        nodes = {
            {
                box = { x = 40, y = 100, w = 500, h = 30 },
                pos0 = "/body/p[1]/span[1]/text().0",
                screen_text = "“轰”",
            },
        },
    }, {
        enabled = true, lang = "all", thickness = 1, mode = "tint",
        quote_boxes = function() free_asked = free_asked + 1; return nil end,
    })
    check("an all-quote unit is still painted without asking the engine",
        #free == 1 and free_asked == 0)
end

-- ------------------------------------------- what the tightened shortcut costs per page

do
    -- The shortcut is a cost optimization, so narrowing it has to be paid for and the bill
    -- bounded. Worst realistic page for this change: 20 rows of nothing but 「“…”她说。」
    -- paragraphs, every one of which used to clear the ratio bar and now does not.
    --
    -- Upper bound is one getScreenBoxesFromPositions per *paragraph*, and that is the number
    -- this section pins. It is not one per row: the `seen` dedup keys on the text node, so a
    -- two-row utterance is resolved once and its sub-line boxes cover both rows. Losing that
    -- would multiply the bill by the row count and also tint the same pixels twice.
    local ROWS = 20
    -- Split so that each variant's rows concatenate to the same paragraph -- a one-row
    -- paragraph has to carry both marks itself, or it is an unpaired 「“」 and marks nothing,
    -- which would make this section pass for the wrong reason.
    local SPLITS = {
        [1] = { "“这句话说得很长很长，而且还没有说完。”她说。" },
        [2] = { "“这句话说得很长很长，", "而且还没有说完。”她说。" },
    }
    local function dialoguePage(rows_per_paragraph)
        local rows = SPLITS[rows_per_paragraph]
        local nodes = {}
        local paragraphs = ROWS // rows_per_paragraph
        for p = 1, paragraphs do
            local offset = 0
            for r, row in ipairs(rows) do
                table.insert(nodes, {
                    box = { x = 40, y = 40 + (#nodes) * 30, w = 500, h = 30 },
                    -- One paragraph's rows share a text node, which is what the stitch keys on.
                    pos0 = "/body/p[" .. p .. "]/text()." .. offset,
                    screen_text = row,
                })
                offset = offset + #row
            end
        end
        return nodes, paragraphs
    end

    for _, rows_per_paragraph in ipairs({ 1, 2 }) do
        local nodes, paragraphs = dialoguePage(rows_per_paragraph)
        local asked = 0
        DialogueLayout.build({
            page = { viewport = { w = 600, h = 800 } },
            nodes = nodes,
        }, {
            enabled = true, lang = "all", thickness = 1, mode = "tint",
            quote_boxes = function(node)
                asked = asked + 1
                return { { x = node.box.x, y = node.box.y, w = 200, h = node.box.h } }
            end,
        })
        check(string.format(
            "a %d-row dialogue page costs one engine call per paragraph (%d), not per row",
            ROWS, paragraphs), asked == paragraphs)
    end
end

-- ------------------------------------------------------ how tall the mark is drawn

do
    -- Line boxes come from the engine and include the line's leading, so a tint drawn to
    -- the full box height touches the rows above and below on tight line spacing. A painter
    -- runs after layout and cannot change the box, only how much of it it fills, so the
    -- inset is the only control available -- and it has to mean the same thing in all three
    -- modes or the setting reads differently depending on the marking style.
    local BOX = { x = 40, y = 100, w = 500, h = 30 }
    local function mark(mode, inset)
        return DialogueLayout.build({
            page = { viewport = { w = 600, h = 800 } },
            nodes = {
                {
                    box = BOX,
                    pos0 = "/body/p[1]/text().0",
                    text = "“你来了。”",
                    screen_text = "“你来了。”",
                },
            },
        }, {
            enabled = true, lang = "all", thickness = 2, mode = mode,
            vertical_inset = inset,
        })[1]
    end

    local tint = mark("tint", 4)
    check("the tint keeps off both edges by the inset",
        tint.y == BOX.y + 4 and tint.h == BOX.h - 8)
    local bar = mark("side_bar", 4)
    check("the side bar shortens at both ends by the same amount",
        bar.y == BOX.y + 4 and bar.h == BOX.h - 8)

    -- Measured up from the bottom edge, so the inset lifts the rule rather than thinning
    -- it. Subtracting from the height instead would silently override the thickness the
    -- reader chose, which is a separate setting one row above it in the menu.
    local rule = mark("underline", 4)
    check("the underline lifts off the bottom edge", rule.y == BOX.y + BOX.h - 4 - 2)
    check("and keeps the thickness that was asked for", rule.h == 2)

    for _, mode in ipairs({ "tint", "underline", "side_bar" }) do
        local off, on = mark(mode, 0), mark(mode, 3)
        check(mode .. ": zero inset is exactly the old geometry",
            off.y == (mode == "underline" and BOX.y + BOX.h - 2 or BOX.y)
                and off.h == (mode == "underline" and 2 or BOX.h))
        check(mode .. ": a nil inset behaves as zero",
            mark(mode, nil).y == off.y and mark(mode, nil).h == off.h)
        check(mode .. ": the inset actually moves the mark", on.y ~= off.y)
    end

    -- Clamped to 40% per end, so a value tuned for a large font cannot invert or erase the
    -- mark when the reader shrinks the text. addRect would drop an inverted box silently --
    -- the mark would just stop appearing, with the menu still showing a number.
    --
    -- On a 30px row the menu's whole range fits (40% is 12), so the clamp is only observable
    -- on a short row. Both halves are worth pinning: the inset must be honoured literally
    -- while it fits, and capped once it does not.
    check("an inset that fits is applied as asked", mark("tint", 8).h == BOX.h - 16)
    local function shortMark(inset)
        return DialogueLayout.build({
            page = { viewport = { w = 600, h = 800 } },
            nodes = {
                {
                    box = { x = 40, y = 100, w = 500, h = 10 },
                    pos0 = "/body/p[1]/text().0",
                    text = "“轰”",
                    screen_text = "“轰”",
                },
            },
        }, {
            enabled = true, lang = "all", thickness = 2, mode = "tint",
            vertical_inset = inset,
        })
    end
    local capped = shortMark(8)
    check("on a short row the inset is capped at 40% per end",
        #capped == 1 and capped[1].h == 10 - 2 * math.floor(10 * 0.4))
    check("and a short row still gets a visible mark",
        #capped == 1 and capped[1].h > 0)
    -- The menu maximum must stay inside what the painter can render on a plausible row, or
    -- the top of the range would be indistinguishable from the value below it.
    check("the menu's maximum is not silently clamped on an ordinary row",
        Config.DIALOGUE_INSET_MAX <= math.floor(BOX.h * 0.4))
end

print(string.format("dialogue_marking_spec: %s (%d checks, %d failures)",
    failures == 0 and "ok" or "FAILED", checks, failures))
if failures > 0 then error("dialogue_marking_spec failed", 0) end
