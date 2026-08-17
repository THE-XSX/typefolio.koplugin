-- The "Mark health-check problems" overlay.
--
-- HealthCheck.run built a `findings` table, returned it, and never put anything in it;
-- semantic_layout builds its problem set from exactly that table, so the toggle drew
-- nothing while still paying for a health check on every frame. Same shape as the older
-- bug where the dialogue painter read `snapshot.semantics` from a producer that emits
-- `nodes`: a feature that is wired up end to end and silently inert.
--
-- Neither module needs KOReader.
--
-- Run from the plugin root:
--   python3 runlua.py <plugin_dir> <plugin_dir>/tests/health_check_spec.lua

local function pluginRoot()
    local here = debug.getinfo(1, "S").source:sub(2)
    local root = here:match("^(.*[/\\])tests[/\\][^/\\]*$")
    if root and root:find("typefolio%.koplugin") then return root end
    return "../typefolio.koplugin/"
end
local ROOT = pluginRoot()

local HealthCheck = dofile(ROOT .. "tools/health_check.lua")
local SemanticLayout = dofile(ROOT .. "painters/semantic_layout.lua")

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

local IDEOGRAPHIC_SPACE = "\227\128\128" -- U+3000

local function node(overrides)
    local n = {
        box = { x = 40, y = 100, w = 500, h = 30 },
        kind = "paragraph",
        html = "<p>普通的一段话。</p>",
        text = "普通的一段话。",
    }
    for k, v in pairs(overrides) do n[k] = v end
    return n
end

local function snapshotOf(nodes)
    return { page = { viewport = { w = 600, h = 800 } }, nodes = nodes }
end

local function findingById(report, id)
    for _, finding in ipairs(report.findings or {}) do
        if finding.id == id then return finding end
    end
    return nil
end

-- A chapter heading followed by a paragraph that opens with a fullwidth indent: the
-- drop cap will enlarge the space instead of the first glyph.
local heading = node{ kind = "heading", html = "<h2>第一章</h2>", text = "第一章" }
local indented = node{
    html = "<p>" .. IDEOGRAPHIC_SPACE .. IDEOGRAPHIC_SPACE .. "他推开门。</p>",
    text = IDEOGRAPHIC_SPACE .. IDEOGRAPHIC_SPACE .. "他推开门。",
}
local ordinary = node{}
local centered = node{ html = '<p align="center">※　※　※</p>', text = "※　※　※" }

-- --------------------------------------------------------------- fullwidth indent

do
    local report = HealthCheck.run(snapshotOf{ heading, indented, ordinary },
        { tweaks = { drop_caps = true } })
    local finding = findingById(report, "fullwidth_indent")
    check("a drop cap landing on an indent space is reported", finding ~= nil)
    check("the finding points at the paragraph itself, not a copy",
        finding and #finding.nodes == 1 and finding.nodes[1] == indented)
end

do
    -- Marking every indented paragraph would light up a whole page of a Chinese novel
    -- and say nothing; only the one a drop cap actually lands on counts.
    local report = HealthCheck.run(snapshotOf{ ordinary, indented },
        { tweaks = { drop_caps = true } })
    check("an indented paragraph mid-chapter is not reported",
        findingById(report, "fullwidth_indent") == nil)
end

do
    local report = HealthCheck.run(snapshotOf{ heading, indented }, { tweaks = {} })
    check("nothing is reported while drop caps are off",
        findingById(report, "fullwidth_indent") == nil)
    check("run() with no tweaks table at all is still safe",
        HealthCheck.run(snapshotOf{ heading, indented }, {}).findings ~= nil)
end

-- --------------------------------------------------------- centered body paragraphs

do
    local report = HealthCheck.run(snapshotOf{ ordinary, centered },
        { skip_headings = false })
    local finding = findingById(report, "centered_body")
    check("a centered paragraph is reported when skip-centered is off", finding ~= nil)
    check("it points at the centered node", finding and finding.nodes[1] == centered)

    check("and not while skip-centered is on",
        findingById(HealthCheck.run(snapshotOf{ ordinary, centered }, {}),
            "centered_body") == nil)
end

do
    local styled = node{
        html = '<p style="text-align: center">※</p>', text = "※",
    }
    check("a text-align style counts as centered too",
        findingById(HealthCheck.run(snapshotOf{ styled }, { skip_headings = false }),
            "centered_body") ~= nil)

    local heading_centered = node{
        kind = "heading", html = '<h2 align="center">第一章</h2>', text = "第一章",
    }
    check("a centered heading is not a problem",
        findingById(HealthCheck.run(snapshotOf{ heading_centered },
            { skip_headings = false }), "centered_body") == nil)
end

-- ------------------------------------------------------------------- the report itself

do
    local report = HealthCheck.run(snapshotOf{ heading, indented }, { tweaks = {} })
    check("the rest of the report still works", #report.features > 0
        and type(report.score) == "number" and report.html_available == true)
    check("an empty snapshot does not blow up",
        HealthCheck.run(nil, nil).html_available == false)
end

-- ------------------------------------------------------ end to end, through the painter

do
    local snapshot = snapshotOf{ heading, indented, ordinary }
    local report = HealthCheck.run(snapshot, { tweaks = { drop_caps = true } })
    local rects = SemanticLayout.build(snapshot, {
        enabled = true, diagnostics = true, thickness = 1,
    }, report)

    local marks = 0
    for _, rect in ipairs(rects) do
        if rect.kind == "diagnostic" then marks = marks + 1 end
    end
    check("the painter draws the diagnostic marks", marks > 0)

    local without = SemanticLayout.build(snapshot, {
        enabled = true, diagnostics = false, thickness = 1,
    }, report)
    local off_marks = 0
    for _, rect in ipairs(without) do
        if rect.kind == "diagnostic" then off_marks = off_marks + 1 end
    end
    check("and none when the toggle is off", off_marks == 0)
end

print(string.format("health_check_spec: %s (%d checks, %d failures)",
    failures == 0 and "ok" or "FAILED", checks, failures))
if failures > 0 then error("health_check_spec failed", 0) end
