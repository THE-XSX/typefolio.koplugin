-- SPDX-FileCopyrightText: Copyright (C) 2026 THE-XSX
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- Typefolio (文笺) - KOReader plugin
-- Released under the GNU Affero General Public License v3.0 or later.
-- See the LICENSE file in the project root for the full license text.

-- PresetCodec.validate is the gate every imported .typefolio.json passes through, so it is
-- the right place to reject values the CSS templates cannot render. Runs the real codec:
-- preset_codec.lua only dofile()s core/config.lua, neither of which touches KOReader.
--
-- Loading it needs care. preset_codec.lua finds its siblings by matching its own source
-- path against "typefolio.koplugin/", so a bare dofile("css/preset_codec.lua") leaves it
-- looking for "css/core/config.lua". Feed it a path that contains the plugin folder name:
-- the spec's own directory when we were given an absolute path, otherwise a relative form
-- that round-trips through the plugin folder and works when cwd is the plugin root.
local function loadModule(relative)
    local here = debug.getinfo(1, "S").source:sub(2)
    local root = here:match("^(.*[/\\])tests[/\\][^/\\]*$")
    local candidates = {}
    if root and root:find("typefolio%.koplugin") then
        table.insert(candidates, root .. relative)
    end
    table.insert(candidates, "../typefolio.koplugin/" .. relative)
    for _, path in ipairs(candidates) do
        local probe = io.open(path, "r")
        if probe then
            probe:close()
            return dofile(path)
        end
    end
    error("preset_codec_spec: could not locate " .. relative .. " from " .. here, 0)
end
local PresetCodec = loadModule("css/preset_codec.lua")
local CSSTemplates = loadModule("css/css_templates.lua")

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

local function bundleWith(params)
    return {
        format = PresetCodec.FORMAT,
        format_version = PresetCodec.FORMAT_VERSION,
        name = "Test preset",
        config = {
            underline = "all_lines",
            line_thickness = "1px",
            dash_pattern = "solid",
            tweaks = { blockquote_box = true },
            tweak_params = { blockquote_box = params },
        },
    }
end

local function validates(params)
    local ok, err = PresetCodec.validate(bundleWith(params))
    return ok ~= nil, err
end

-- Baseline: the shipped default must still import.
local ok_default, default_err = validates{ bar = 5, tint = "light", italic = true }
check("whole-number bar imports (" .. tostring(default_err) .. ")", ok_default)
check("bar = 0 imports (the 'no bar' end of the range)", (validates{ bar = 0 }))
check("bar = 10 imports (top of the range)", (validates{ bar = 10 }))
-- 2.0 is a float in Lua 5.3+ but has an exact integer representation, so "%dpx" accepts it
-- and there is no reason to reject it.
check("bar = 2.0 imports", (validates{ bar = 2.0 }))

-- The reason this rule exists: css_templates formats bar into "border-left: %dpx". LuaJIT
-- truncates 2.5 to "2px" and says nothing; Lua 5.3+ raises "number has no integer
-- representation" from inside the CSS build. Neither is acceptable, so reject on import.
local frac_ok, frac_err = validates{ bar = 2.5 }
check("fractional bar is rejected", not frac_ok)
check("fractional bar names the parameter (" .. tostring(frac_err) .. ")",
    type(frac_err) == "string" and frac_err:find("bar", 1, true) ~= nil)

-- Range checks use < and >, which are both false for NaN, so the integer rule is what
-- actually keeps NaN out.
local nan = 0 / 0
check("NaN bar is rejected", not (validates{ bar = nan }))

-- Out-of-range still fails, and for the range reason rather than the new one.
local high_ok, high_err = validates{ bar = 11 }
check("bar = 11 is out of range", not high_ok and tostring(high_err):find("range", 1, true) ~= nil)
local neg_ok = validates{ bar = -1 }
check("bar = -1 is out of range", not neg_ok)

-- The same rule guards header_border thickness, the other numeric parameter.
local function borderValidates(params)
    local ok = PresetCodec.validate{
        format = PresetCodec.FORMAT,
        format_version = PresetCodec.FORMAT_VERSION,
        name = "Test preset",
        config = {
            underline = "all_lines",
            line_thickness = "1px",
            dash_pattern = "solid",
            tweaks = { header_border = true },
            tweak_params = { header_border = params },
        },
    }
    return ok ~= nil
end
check("header_border thickness = 2 imports", borderValidates{ thickness = 2 })
check("header_border thickness = 1.5 is rejected", not borderValidates{ thickness = 1.5 })

-- The rule table in preset_codec is a second copy of the parameter set that lives in
-- css_templates.tweak_defaults, and it had drifted: header_border gained
-- include_centered, chapter_pagebreak was created with one, and neither was added here,
-- so a preset the menu can produce was refused on import. Export does not validate, so
-- this only ever surfaced on the other device. Rather than list the three holes, assert
-- the invariant: whatever ships as a default must survive a round trip.
local function effectValidates(effect, params)
    local ok, err = PresetCodec.validate{
        format = PresetCodec.FORMAT,
        format_version = PresetCodec.FORMAT_VERSION,
        name = "Test preset",
        config = {
            underline = "all_lines",
            line_thickness = "1px",
            dash_pattern = "solid",
            tweaks = { [effect] = true },
            tweak_params = { [effect] = params },
        },
    }
    return ok ~= nil, err
end

local effects = {}
for effect in pairs(CSSTemplates.tweak_defaults) do table.insert(effects, effect) end
table.sort(effects)
for _, effect in ipairs(effects) do
    local defaults = CSSTemplates.tweak_defaults[effect]
    local ok, err = effectValidates(effect, defaults)
    check(string.format("%s ships defaults that import (%s)", effect, tostring(err)), ok)
    -- And each parameter on its own, so a table with one bad key cannot hide behind a
    -- neighbour that happens to be absent from the defaults.
    for name, value in pairs(defaults) do
        local one_ok, one_err = effectValidates(effect, { [name] = value })
        check(string.format("%s.%s = %s imports (%s)", effect, name, tostring(value),
            tostring(one_err)), one_ok)
    end
end

-- drop_caps.scale is an em multiplier, not a pixel count: the menu spins it from 1.5 to
-- 3.5 in tenths and the template formats it "%.1fem". The whole-number rule written for
-- pixel values was rejecting 18 of the 21 selectable sizes, including the shipped 2.1.
for _, scale in ipairs({ 1.5, 1.6, 2.0, 2.1, 2.7, 3.4, 3.5 }) do
    check("drop_caps scale " .. tostring(scale) .. " imports",
        (effectValidates("drop_caps", { scale = scale })))
end
check("drop_caps scale below the range is rejected",
    not effectValidates("drop_caps", { scale = 1.4 }))
check("drop_caps scale above the range is rejected",
    not effectValidates("drop_caps", { scale = 3.6 }))
-- Opting out of the whole-number rule removed what used to catch NaN, hence the
-- explicit guard now in validateParams.
check("drop_caps scale NaN is rejected",
    not effectValidates("drop_caps", { scale = 0 / 0 }))
check("drop_caps scale of the wrong type is rejected",
    not effectValidates("drop_caps", { scale = "2.1" }))
-- Unknown keys must still be refused; widening the rules must not turn into accepting
-- anything.
check("an invented parameter is still rejected",
    not effectValidates("drop_caps", { scale_factor = 2 }))
check("an invented effect is still rejected",
    not effectValidates("sparkles", { on = true }))

-- custom_header and custom_footer validation.
--
-- This block used to be written against left_slot / center_slot / right_slot / divider,
-- none of which exist -- the schema keys are left / center / right / divider_style. Every
-- value in it was therefore rejected as an unknown field, which made the three
-- "... is rejected" checks pass no matter what the codec did, and hid a real bug: the
-- header's accepted-field list had not been told about chapter_ticks, so the config
-- PresetCodec.bundle writes was refused by PresetCodec.validate and no exported preset
-- could be imported anywhere. Hence the round-trip check first, then the field checks
-- with ids that really exist.
local function headerFooterValidates(header_cfg, footer_cfg)
    local ok, err = PresetCodec.validate{
        format = PresetCodec.FORMAT,
        format_version = PresetCodec.FORMAT_VERSION,
        name = "Header Footer Test",
        config = {
            underline = "none",
            custom_header = header_cfg,
            custom_footer = footer_cfg,
        },
    }
    return ok ~= nil, err
end

-- The invariant: what export writes, import must accept. bundle() emits
-- Config.normalize(config) verbatim, so a normalized config is exactly what lands in the
-- file, and any schema key the codec has not been told about breaks every export.
local Config = loadModule("core/config.lua")
local normalized = Config.normalize{
    custom_header = { enabled = true },
    custom_footer = { enabled = true },
}
local rt_ok, rt_err = PresetCodec.validate{
    format = PresetCodec.FORMAT,
    format_version = PresetCodec.FORMAT_VERSION,
    name = "Round trip",
    config = normalized,
}
check("a normalized config survives export -> import (" .. tostring(rt_err) .. ")",
    rt_ok ~= nil)
-- Field by field, so a single unknown key cannot hide behind an earlier failure.
for _, bar in ipairs({ "custom_header", "custom_footer" }) do
    local keys = {}
    for key in pairs(normalized[bar]) do table.insert(keys, key) end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local one = { [key] = normalized[bar][key] }
        local ok, err = headerFooterValidates(
            bar == "custom_header" and one or nil,
            bar == "custom_footer" and one or nil)
        check(string.format("%s.%s = %s imports (%s)", bar, key,
            tostring(normalized[bar][key]), tostring(err)), ok)
    end
end

check("a fully specified header and footer validate",
    (headerFooterValidates(
        { enabled = true, preset = "classic_folio", font_size = Config.STATUS_FONT_MIN,
          left = "none", center = "clock_12h", right = "none",
          divider_style = "dots_small", divider_thickness = 2 },
        { enabled = true, preset = "wechat_duokan", font_size = Config.STATUS_FONT_MAX,
          left = "time_left_chapter", right = "reading_percent", divider_style = "none" }
    )))

check("a progress_bar divider with a CJK combo slot validates",
    (headerFooterValidates(
        nil,
        { enabled = true, preset = "classic_folio", font_size = 12,
          center = "book_title_page_progress_cn", divider_style = "progress_bar",
          chapter_ticks = true }
    )))

-- The rejection checks, now that the surrounding keys are real: each bundle differs from
-- a valid one in exactly the field under test.
check("an unsupported slot id is rejected",
    not (headerFooterValidates(nil, { enabled = true, left = "invalid_magic_slot" })))
check("a slot key that does not exist in the schema is rejected",
    not (headerFooterValidates(nil, { enabled = true, left_slot = "none" })))
check("an unsupported divider is rejected",
    not (headerFooterValidates({ enabled = true, divider_style = "invalid_wavy" }, nil)))
check("a font_size above the range is rejected",
    not (headerFooterValidates(nil,
        { enabled = true, font_size = Config.STATUS_FONT_MAX + 1 })))
check("a font_size below the range is rejected",
    not (headerFooterValidates(nil,
        { enabled = true, font_size = Config.STATUS_FONT_MIN - 1 })))
check("a divider thickness out of range is rejected",
    not (headerFooterValidates(nil,
        { enabled = true, divider_thickness = Config.STATUS_DIVIDER_THICKNESS_MAX + 1 })))
check("enabled must be a boolean",
    not (headerFooterValidates(nil, { enabled = "yes" })))

-- A file written by an older build carries the ids that build used. Config.normalize
-- translates those, so the importer must not reject them on the way in -- otherwise the
-- reader's own exported preset is unimportable, which is the same failure the
-- chapter_ticks omission caused. Rejection has to stay a hard error, not a partial
-- recovery, so this is the only place legacy values are tolerated.
for legacy, current in pairs(Config.STATUS_SLOT_ALIASES) do
    local ok, err = headerFooterValidates({ enabled = true, left = legacy }, nil)
    check(string.format("a legacy slot id (%s) still imports (%s)", legacy, tostring(err)), ok)
    check(string.format("and normalize turns it into %s", current),
        Config.normalize{ custom_header = { left = legacy } }.custom_header.left == current)
end
for legacy, current in pairs(Config.STATUS_DIVIDER_ALIASES) do
    local ok, err = headerFooterValidates(nil, { enabled = true, divider_style = legacy })
    check(string.format("a legacy divider id (%s) still imports (%s)", legacy, tostring(err)), ok)
    check(string.format("and normalize turns it into %s", current),
        Config.normalize{ custom_footer = { divider_style = legacy } }
            .custom_footer.divider_style == current)
end

print(string.format("preset_codec_spec: %s (%d checks, %d failures)",
    failures == 0 and "ok" or "FAILED", checks, failures))
if failures > 0 then error("preset_codec_spec failed", 0) end
