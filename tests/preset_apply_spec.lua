-- Applying a built-in preset must not quietly undo settings the preset says nothing
-- about.
--
-- The menu row used to build a fresh config table listing, by hand, the keys worth
-- carrying over from the reader's current config. Every setting added after that list
-- was written -- the dialogue painter, the emphasis painter, "skip blockquotes" -- was
-- missing from it, so Config.normalize filled them with defaults: one tap on a preset
-- turned off the quote highlighting the reader had enabled, and persisted that.
--
-- Runs the real settings/presets.lua. It requires three KOReader widgets at load time,
-- so those are stubbed through package.preload before it is dofile'd.
--
-- Run from the plugin root:
--   python3 runlua.py <plugin_dir> <plugin_dir>/tests/preset_apply_spec.lua

local function pluginRoot()
    local here = debug.getinfo(1, "S").source:sub(2)
    local root = here:match("^(.*[/\\])tests[/\\][^/\\]*$")
    if root and root:find("typefolio%.koplugin") then return root end
    return "../typefolio.koplugin/"
end
local ROOT = pluginRoot()

package.preload["ui/widget/inputdialog"] = function() return { new = function() return {} end } end
package.preload["ui/widget/confirmbox"] = function() return { new = function() return {} end } end
package.preload["ui/uimanager"] = function()
    return { show = function() end, close = function() end }
end

local Config = dofile(ROOT .. "core/config.lua")
local CSSTemplates = dofile(ROOT .. "css/css_templates.lua")
local PresetsSettings = dofile(ROOT .. "settings/presets.lua")

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

-- A reader who has been through the menus: painters on, blockquotes not skipped,
-- a non-default folio scene and a semantic overlay.
local function readerConfig()
    return Config.normalize{
        underline = "all_lines",
        line_thickness = "2px",
        dash_pattern = "dashed",
        tweaks = { pure_black = true },
        tweak_params = { drop_caps = { scale = 2.7 } },
        skip_headings = false,
        skip_blockquotes = false,
        folio_scene = "study",
        awareness = { chapter = { start = { enabled = true, style = "double", thickness = 2 } } },
        semantic_drawing = { enabled = true, diagnostics = true, thickness = 2 },
        dialogue_painter = { enabled = true, mode = "underline", tint_level = "strong" },
        emphasis_painter = { enabled = true },
    }
end

local function applyPreset(preset_key)
    local current = readerConfig()
    local applied
    local ctx = {
        tr = function(s) return s end,
        -- ffi/util's template: %1, %2 … are the positional slots.
        T = function(fmt, ...)
            local args = { ... }
            return (fmt:gsub("%%(%d)", function(n) return tostring(args[tonumber(n)]) end))
        end,
        ui = { doc_settings = {} },
        getConfig = function() return readerConfig() end,
        -- engine:apply normalizes whatever it is handed, which is where the defaults
        -- used to be substituted in.
        applyStyle = function(config) applied = Config.normalize(config) end,
        notify = function() end,
    }
    local items = PresetsSettings.items(ctx)
    for _, item in ipairs(items) do
        if item.text:find(preset_key, 1, true) or item.text == preset_key then
            item.callback(nil)
            return applied, current
        end
    end
    error("preset_apply_spec: no menu row matched " .. preset_key, 0)
end

-- Every built-in preset, so a new one cannot be added with the old hand-written table.
local preset_keys = {}
for key, preset in pairs(CSSTemplates.presets) do
    table.insert(preset_keys, { key = key, name = preset.name })
end
table.sort(preset_keys, function(a, b) return a.key < b.key end)
check("there is at least one built-in preset to check", #preset_keys > 0)

for _, entry in ipairs(preset_keys) do
    local applied, current = applyPreset(entry.name)
    local label = entry.key

    check(label .. ": dialogue painter stays on",
        applied.dialogue_painter.enabled == true)
    check(label .. ": dialogue painter keeps its mode",
        applied.dialogue_painter.mode == "underline")
    check(label .. ": dialogue painter keeps its tint level",
        applied.dialogue_painter.tint_level == "strong")
    check(label .. ": emphasis painter stays on",
        applied.emphasis_painter.enabled == true)
    check(label .. ": skip_blockquotes keeps the reader's answer",
        applied.skip_blockquotes == false)
    -- These three were already carried over and must stay that way.
    check(label .. ": semantic drawing survives",
        applied.semantic_drawing.enabled == true
            and applied.semantic_drawing.diagnostics == true)
    check(label .. ": awareness survives",
        applied.awareness.chapter.start.enabled == true
            and applied.awareness.chapter.start.style == "double")
    check(label .. ": skip_headings survives", applied.skip_headings == false)
    check(label .. ": folio scene survives", applied.folio_scene == current.folio_scene)
    check(label .. ": line thickness survives", applied.line_thickness == "2px")
    check(label .. ": tweak params survive",
        applied.tweak_params.drop_caps ~= nil and applied.tweak_params.drop_caps.scale == 2.7)

    -- And the preset still does its job.
    local preset = CSSTemplates.presets[entry.key]
    -- Compared after normalize, because a preset may still be written with a legacy
    -- underline key ("all_lines_dashed_compat") that normalize expands into an
    -- underline + dash_pattern pair.
    local expected = Config.normalize{
        underline = preset.underline,
        dash_pattern = preset.dash_pattern or "normal",
    }
    check(label .. ": the preset's underline is applied",
        applied.underline == expected.underline
            and applied.dash_pattern == expected.dash_pattern)
    check(label .. ": the preset's tweaks replace the old ones",
        applied.tweaks.pure_black == nil or preset.tweaks.pure_black ~= nil)
    for tweak, enabled in pairs(preset.tweaks) do
        check(label .. ": the preset enables " .. tweak, applied.tweaks[tweak] == enabled)
    end
    -- A preset is a styling payload, never a KOReader-settings replay.
    check(label .. ": no KOReader settings payload rides along",
        type(applied.koreader_settings) == "table" and next(applied.koreader_settings) == nil)
end

print(string.format("preset_apply_spec: %s (%d checks, %d failures)",
    failures == 0 and "ok" or "FAILED", checks, failures))
if failures > 0 then error("preset_apply_spec failed", 0) end
