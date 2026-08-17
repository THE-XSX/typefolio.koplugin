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
-- Run from the plugin root:
--   python3 runlua.py <plugin_dir> <plugin_dir>/tests/dialogue_marking_spec.lua

local DialogueLayout = dofile("painters/dialogue_layout.lua")

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

    local fallback = build(narration, { quote_boxes = function() return nil end })
    check("without one the whole line is painted rather than nothing",
        #fallback == 1 and fallback[1].w > 40)
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

    -- Unchanged where the engine cannot help: better a whole line than nothing.
    local fallback = build(split, { quote_boxes = function() return nil end })
    check("without geometry it still falls back to the whole line",
        #fallback == 1 and fallback[1].w > 30)

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

print(string.format("dialogue_marking_spec: %s (%d checks, %d failures)",
    failures == 0 and "ok" or "FAILED", checks, failures))
if failures > 0 then error("dialogue_marking_spec failed", 0) end
