-- settings/typesetting_tools.lua
-- Typesetting tools: Health check, Selector helper, Semantic drawing, Dialogue/Emphasis painters
local item_path = debug.getinfo(1, "S").source:sub(2)
local PLUGIN_ROOT = item_path:match("(.*[/\\]typefolio%.koplugin[/\\])") or item_path:match("(.*[/\\])settings[/\\]") or item_path:match("(.*[/\\])") or "plugins/typefolio.koplugin/"
local HealthCheck = dofile(PLUGIN_ROOT .. "tools/health_check.lua")
local SelectorHelper = dofile(PLUGIN_ROOT .. "tools/selector_helper.lua")
local SpinWidget = require("ui/widget/spinwidget")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")

local TypesettingToolsSettings = {}

local function getSemantic(ctx, name)
    return ctx.getConfig(ctx.ui).semantic_drawing[name]
end

local function setSemantic(ctx, name, value)
    local config = ctx.getConfig(ctx.ui)
    config.semantic_drawing[name] = value
    ctx.applyStyle(config)
end

local function getEmphasisPainter(ctx, name)
    return ctx.getConfig(ctx.ui).emphasis_painter[name]
end

local function setEmphasisPainter(ctx, name, value)
    local config = ctx.getConfig(ctx.ui)
    config.emphasis_painter[name] = value
    ctx.applyStyle(config)
end

function TypesettingToolsSettings.showHealthReport(ctx)
    local tr = ctx.tr
    local T = ctx.T
    local Screen = ctx.Screen
    local semantic_index = ctx.getSemanticIndex()

    if not semantic_index then return end
    local perf = ctx.getPerformanceCounter and ctx.getPerformanceCounter()
    local report
    if perf then
        report = perf:measure("phase.health_check.menu", function()
            return HealthCheck.run(semantic_index:inspect(), ctx.getConfig(ctx.ui), ctx.ui, perf)
        end)
    else
        report = HealthCheck.run(semantic_index:inspect(), ctx.getConfig(ctx.ui), ctx.ui)
    end
    local lines = {
        "--------------------------------------------------",
        " ■ " .. T(tr("Typesetting health score: %1/100"), tostring(report.score)),
        " ■ " .. (report.html_available and tr("Inspection scope: Book-wide TOC sampling + Current Page") or tr("Inspection scope: Current Page fallback")),
        "--------------------------------------------------",
        "",
        "【 " .. tr("Feature Compatibility & Adaptation Guide") .. " 】",
    }

    for _, feat in ipairs(report.features or {}) do
        table.insert(lines, "")
        table.insert(lines, string.format(" ● %s  [%s]", tr(feat.name), tr(feat.badge)))
        table.insert(lines, "    • " .. tr("Diagnosis: ") .. tr(feat.desc))
        if feat.action1 then
            table.insert(lines, "    [1] " .. tr("Option 1 (Plugin setting): ") .. tr(feat.action1))
        end
        if feat.action2 then
            table.insert(lines, "    [2] " .. tr("Option 2 (Calibre edit): ") .. tr(feat.action2))
        end
    end

    table.insert(lines, "")
    table.insert(lines, "--------------------------------------------------")
    table.insert(lines, "【 " .. tr("Calibre Quick Regex Reference") .. " 】")
    table.insert(lines, "--------------------------------------------------")
    table.insert(lines, tr("1. Dialogue (.dialogue):"))
    table.insert(lines, "   " .. tr("Search: “([^””]*)”  →  Replace: <span class=\"dialogue\">“\\1”</span>"))
    table.insert(lines, tr("2. Chapter Title (<h2>):"))
    table.insert(lines, "   " .. tr("Search: <p[^>]*>\\s*(第[0-9一二...]+[章卷回][^<]*)</p>  →  Replace: <h2 class=\"chapter-title\">\\1</h2>"))
    table.insert(lines, tr("3. Blockquote (<blockquote>):"))
    table.insert(lines, "   " .. tr("Search: <p[^>]*>【引用】([^\\n<]*)</p>  →  Replace: <blockquote><p>\\1</p></blockquote>"))
    table.insert(lines, tr("4. Clean Fullwidth Space:"))
    table.insert(lines, "   " .. tr("Search: (<h[1-4][^>]*>[^<]*</h[1-4]>\\s*<p[^>]*>)　+  →  Replace: \\1"))
    table.insert(lines, "--------------------------------------------------")

    UIManager:show(TextViewer:new{
        title = tr("Typesetting health check"),
        text = table.concat(lines, "\n"),
        text_type = "code",
        height = math.floor(Screen:getHeight() * 0.85),
    })
end

function TypesettingToolsSettings.inspectSelector(ctx, y_ratio)
    local tr = ctx.tr
    local T = ctx.T
    local Screen = ctx.Screen
    local showInfo = ctx.showInfo
    local semantic_index = ctx.getSemanticIndex()

    if not semantic_index then return end
    local snapshot = semantic_index:inspect({
        target = { x = Screen:getWidth() / 2, y = Screen:getHeight() * y_ratio },
    })
    local result = SelectorHelper.suggest(snapshot)
    if not result.available then
        showInfo(tr("No semantic node is available near that screen position."))
        return
    end
    ctx.setLastSelectorSnippet(result.snippet)
    local lines = {
        T(tr("Selector: %1"), result.selector),
        T(tr("Confidence: %1"), tr(result.confidence)),
        T(tr("Semantic role: %1"), tr(result.kind)),
        T(tr("Source: %1"), tr(result.source)),
        "",
        result.snippet,
        "",
        "XPointer: " .. tostring(result.xpointer or "n/a"),
    }
    UIManager:show(TextViewer:new{
        title = tr("Selector helper"),
        text = table.concat(lines, "\n"),
        text_type = "code",
        height = math.floor(Screen:getHeight() * 0.8),
    })
end

function TypesettingToolsSettings.showPerformanceReport(ctx)
    local report, path, err = ctx.getPerformanceReport()
    local text = report
    if path then
        text = ctx.T(ctx.tr("Performance report saved to: %1"), path) .. "\n\n" .. report
    elseif err then
        text = ctx.T(ctx.tr("Failed to save performance report: %1"), tostring(err)) .. "\n\n" .. report
    end
    UIManager:show(TextViewer:new{
        title = ctx.tr("Performance report"),
        text = text,
        text_type = "code",
        height = math.floor(ctx.Screen:getHeight() * 0.85),
    })
end

function TypesettingToolsSettings.performanceCounterItems(ctx)
    local Device = ctx.Device or require("device")
    return {
        {
            text = ctx.tr("View performance report"),
            callback = function() TypesettingToolsSettings.showPerformanceReport(ctx) end,
        },
        {
            text = ctx.tr("Copy performance report"),
            enabled_func = function() return Device:hasClipboard() end,
            callback = function()
                local report = ctx.getPerformanceReport()
                Device.input.setClipboardText(report)
                ctx.notify(ctx.tr("Performance report copied"))
            end,
        },
        {
            text = ctx.tr("Reset performance counters"),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                ctx.resetPerformanceCounters()
                ctx.notify(ctx.tr("Performance counters reset"))
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        },
    }
end

function TypesettingToolsSettings.selectorHelperItems(ctx)
    local tr = ctx.tr
    local notify = ctx.notify
    local Device = ctx.Device or require("device")
    local items = {}
    for _, option in ipairs({
        { ratio = 0.25, label = "Inspect upper page" },
        { ratio = 0.5, label = "Inspect page center" },
        { ratio = 0.75, label = "Inspect lower page" },
    }) do
        local ratio, label = option.ratio, option.label
        table.insert(items, {
            text = tr(label),
            keep_menu_open = true,
            callback = function() TypesettingToolsSettings.inspectSelector(ctx, ratio) end,
        })
    end
    table.insert(items, {
        text = tr("Copy last CSS snippet"),
        keep_menu_open = true,
        enabled_func = function()
            return ctx.getLastSelectorSnippet() ~= nil and Device:hasClipboard()
        end,
        callback = function()
            Device.input.setClipboardText(ctx.getLastSelectorSnippet())
            notify(tr("CSS snippet copied"))
        end,
    })
    return items
end

function TypesettingToolsSettings.semanticToggle(ctx, name, label, always_enabled)
    local tr = ctx.tr
    return {
        text = tr(label),
        keep_menu_open = true,
        enabled_func = function()
            return always_enabled or getSemantic(ctx, "enabled") == true
        end,
        checked_func = function() return getSemantic(ctx, name) == true end,
        callback = function(touchmenu_instance)
            setSemantic(ctx, name, not getSemantic(ctx, name))
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    }
end

function TypesettingToolsSettings.semanticDrawingItems(ctx)
    local tr = ctx.tr
    local T = ctx.T
    local enable = TypesettingToolsSettings.semanticToggle(ctx, "enabled", "Semantic drawing", true)
    enable.text = nil
    enable.text_func = function()
        return T(tr("%1: %2"), tr("Semantic drawing"),
            getSemantic(ctx, "enabled") and tr("Enabled") or tr("Disabled"))
    end
    enable.separator = true
    return {
        enable,
        TypesettingToolsSettings.semanticToggle(ctx, "headings", "Mark semantic headings"),
        TypesettingToolsSettings.semanticToggle(ctx, "blockquotes", "Mark semantic blockquotes"),
        TypesettingToolsSettings.semanticToggle(ctx, "scene_breaks", "Mark semantic scene breaks"),
        TypesettingToolsSettings.semanticToggle(ctx, "diagnostics", "Mark health-check problems"),
        {
            text_func = function()
                return T(tr("Thickness: %1"), tostring(getSemantic(ctx, "thickness")))
            end,
            keep_menu_open = true,
            enabled_func = function() return getSemantic(ctx, "enabled") == true end,
            callback = function(touchmenu_instance)
                UIManager:show(SpinWidget:new{
                    title_text = tr("Decoration thickness"),
                    value = getSemantic(ctx, "thickness"),
                    value_min = 1,
                    value_max = 3,
                    value_step = 1,
                    value_hold_step = 1,
                    default_value = 1,
                    ok_always_enabled = true,
                    callback = function(spin)
                        setSemantic(ctx, "thickness", spin.value)
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                })
            end,
        },
    }
end

function TypesettingToolsSettings.items(ctx)
    local tr = ctx.tr
    local T = ctx.T
    return {
        {
            text = tr("Typesetting health check"),
            keep_menu_open = true,
            callback = function() TypesettingToolsSettings.showHealthReport(ctx) end,
        },
        {
            text = tr("Selector helper"),
            sub_item_table_func = function() return TypesettingToolsSettings.selectorHelperItems(ctx) end,
        },
        {
            text = tr("Semantic drawing"),
            keep_menu_open = true,
            checked_func = function() return getSemantic(ctx, "enabled") == true end,
            checkmark_callback = function(touchmenu_instance)
                setSemantic(ctx, "enabled", not getSemantic(ctx, "enabled"))
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
            sub_item_table_func = function() return TypesettingToolsSettings.semanticDrawingItems(ctx) end,
        },
        -- Dynamic dialogue detection now lives under Text styling > Dialogue,
        -- together with the CSS class-based styling it complements.
        {
            text = tr("Emphasis dots painter"),
            keep_menu_open = true,
            checked_func = function() return getEmphasisPainter(ctx, "enabled") == true end,
            callback = function(touchmenu_instance)
                setEmphasisPainter(ctx, "enabled", not getEmphasisPainter(ctx, "enabled"))
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        },
        {
            text_func = function()
                return T(tr("%1: %2"), tr("Developer performance counters"),
                    ctx.performanceCountersEnabled() and tr("Enabled") or tr("Disabled"))
            end,
            checked_func = function() return ctx.performanceCountersEnabled() end,
            checkmark_callback = function(touchmenu_instance)
                ctx.setPerformanceCountersEnabled(not ctx.performanceCountersEnabled())
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
            sub_item_table_func = function()
                return TypesettingToolsSettings.performanceCounterItems(ctx)
            end,
        },
    }
end

return TypesettingToolsSettings
