-- SPDX-FileCopyrightText: Copyright (C) 2026 THE-XSX
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- Typefolio (文笺) - KOReader plugin
-- Released under the GNU Affero General Public License v3.0 or later.
-- See the LICENSE file in the project root for the full license text.

local item_path = debug.getinfo(1, "S").source:sub(2)
local PLUGIN_ROOT = item_path:match("(.*[/\\]typefolio%.koplugin[/\\])") or item_path:match("(.*[/\\])") or "plugins/typefolio.koplugin/"
local Config = dofile(PLUGIN_ROOT .. "core/config.lua")

local PresetCodec = {
    FORMAT = "typefolio-preset",
    FORMAT_VERSION = 1,
}

local function validName(value)
    return type(value) == "string" and value:match("%S") ~= nil and #value <= 120
end

local function oneOf(value, allowed)
    for _, candidate in ipairs(allowed) do
        if value == candidate then return true end
    end
    return false
end

local function onlyKeys(value, allowed, label)
    for key in pairs(value) do
        if not allowed[key] then return nil, "unknown " .. label .. ": " .. tostring(key) end
    end
    return true
end

local function validateAwareness(value)
    if value == nil then return true end
    if type(value) ~= "table" then return nil, "awareness must be an object" end
    local ok, err = onlyKeys(value, { chapter = true, annotations = true }, "awareness section")
    if not ok then return nil, err end

    for section, section_value in pairs(value) do
        if type(section_value) ~= "table" then
            return nil, section .. " awareness must be an object"
        end
        if section == "chapter" then
            local has_boundaries = section_value.start ~= nil or section_value["end"] ~= nil
            if has_boundaries then
                ok, err = onlyKeys(section_value, { start = true, ["end"] = true },
                    "chapter awareness field")
                if not ok then return nil, err end
                for _, boundary in ipairs({ "start", "end" }) do
                    local boundary_value = section_value[boundary]
                    if boundary_value ~= nil then
                        if type(boundary_value) ~= "table" then
                            return nil, "chapter " .. boundary .. " must be an object"
                        end
                        ok, err = onlyKeys(boundary_value,
                            { enabled = true, style = true, thickness = true, char = true, count = true },
                            "chapter " .. boundary .. " field")
                        if not ok then return nil, err end
                        if boundary_value.enabled ~= nil
                                and type(boundary_value.enabled) ~= "boolean" then
                            return nil, "enabled must be a boolean"
                        end
                        if boundary_value.style ~= nil
                                and not oneOf(boundary_value.style, { "single", "double", "wave", "dots", "heart", "custom" }) then
                            return nil, "style has an unsupported value"
                        end
                        local thickness = boundary_value.thickness
                        if thickness ~= nil and (type(thickness) ~= "number"
                                or thickness % 1 ~= 0 or thickness < 1 or thickness > 5) then
                            return nil, "chapter " .. boundary .. " thickness is out of range"
                        end
                    end
                end
            else
                ok, err = onlyKeys(section_value, {
                    enabled = true, show_start = true, show_end = true,
                    style = true, thickness = true, char = true, count = true,
                }, "legacy chapter awareness field")
                if not ok then return nil, err end
                for _, name in ipairs({ "enabled", "show_start", "show_end" }) do
                    if section_value[name] ~= nil and type(section_value[name]) ~= "boolean" then
                        return nil, name .. " must be a boolean"
                    end
                end
                if section_value.style ~= nil
                        and not oneOf(section_value.style, { "single", "double", "wave", "dots", "heart", "custom" }) then
                    return nil, "style has an unsupported value"
                end
                local thickness = section_value.thickness
                if thickness ~= nil and (type(thickness) ~= "number"
                        or thickness % 1 ~= 0 or thickness < 1 or thickness > 5) then
                    return nil, "legacy chapter thickness is out of range"
                end
            end
        else -- Legacy annotation-aware settings are accepted, then discarded by Config.normalize.
            ok, err = onlyKeys(section_value, {
                enabled = true, show_highlights = true, show_notes = true,
                style = true, side = true, thickness = true,
            }, "legacy annotations awareness field")
            if not ok then return nil, err end
            for _, name in ipairs({ "enabled", "show_highlights", "show_notes" }) do
                if section_value[name] ~= nil and type(section_value[name]) ~= "boolean" then
                    return nil, name .. " must be a boolean"
                end
            end
            if section_value.style ~= nil
                    and not oneOf(section_value.style, { "ticks", "dots", "brackets" }) then
                return nil, "style has an unsupported value"
            end
            if section_value.side ~= nil
                    and not oneOf(section_value.side, { "outer", "left", "right" }) then
                return nil, "side has an unsupported value"
            end
            if section_value.thickness ~= nil then
                local thickness = section_value.thickness
                if type(thickness) ~= "number" or thickness % 1 ~= 0
                        or thickness < 1 or thickness > 3 then
                    return nil, section .. " thickness is out of range"
                end
            end
        end
    end
    return true
end

local function validateSemanticDrawing(value)
    if value == nil then return true end
    if type(value) ~= "table" then return nil, "semantic_drawing must be an object" end
    local ok, err = onlyKeys(value, {
        enabled = true, headings = true, blockquotes = true,
        scene_breaks = true, diagnostics = true, thickness = true,
    }, "semantic drawing field")
    if not ok then return nil, err end
    for _, name in ipairs({ "enabled", "headings", "blockquotes", "scene_breaks", "diagnostics" }) do
        if value[name] ~= nil and type(value[name]) ~= "boolean" then
            return nil, name .. " must be a boolean"
        end
    end
    if value.thickness ~= nil and (type(value.thickness) ~= "number"
            or value.thickness % 1 ~= 0 or value.thickness < 1 or value.thickness > 3) then
        return nil, "semantic drawing thickness is out of range"
    end
    return true
end

local PARAM_RULES = {
    dialogue_style = {
        tint = "boolean",
        tint_level = { "light", "medium", "strong" },
        bold = "boolean",
        italic = "boolean",
    },
    chapter_pagebreak = {
        include_centered = "boolean",
    },
    header_border = {
        border = { "both", "bottom", "top", "none" },
        line_style = { "solid", "dashed", "dotted" },
        thickness = { min = 1, max = 5 },
        centered = "boolean",
        include_centered = "boolean",
    },
    blockquote_box = {
        bar = { min = 0, max = 10 },
        tint = { "none", "light", "medium" },
        italic = "boolean",
    },
    drop_caps = {
        -- An em multiplier, not a pixel count: the menu spins it in 0.1 steps and the
        -- template formats it "%.1fem", so whole numbers must not be required here.
        scale = { min = 1.5, max = 3.5, fractional = true },
        bold = "boolean",
    },
    pure_black = {},
    body_bold = {},
    body_italic = {},
}

local function validateParams(config)
    for key, enabled in pairs(config.tweaks) do
        if PARAM_RULES[key] == nil then return nil, "unknown effect: " .. tostring(key) end
        if type(enabled) ~= "boolean" then return nil, "effect flags must be booleans" end
    end
    for effect, params in pairs(config.tweak_params) do
        local rules = PARAM_RULES[effect]
        if rules == nil then return nil, "unknown effect parameters: " .. tostring(effect) end
        if type(params) ~= "table" then return nil, "effect parameters must be objects" end
        for name, value in pairs(params) do
            local rule = rules[name]
            if rule == nil then return nil, "unknown parameter: " .. tostring(name) end
            if rule == "boolean" then
                if type(value) ~= "boolean" then return nil, name .. " must be a boolean" end
            elseif rule.min then
                -- NaN loses every comparison, so test it before the range check rather
                -- than relying on the whole-number rule below to catch it.
                if type(value) ~= "number" or value ~= value
                    or value < rule.min or value > rule.max then
                    return nil, name .. " is out of range"
                end
                -- Most numeric parameters here are pixel counts that end up in a "%dpx"
                -- format. LuaJIT would silently truncate 2.5 to "2px"; Lua 5.3+ raises
                -- "number has no integer representation" instead. Reject it at the door so
                -- a hand-edited preset file fails with a clear message on either runtime.
                -- (2.0 is fine -- it has an exact integer representation.) Rules that carry
                -- a real fraction, like the drop-cap em multiplier, opt out.
                if not rule.fractional and value % 1 ~= 0 then
                    return nil, name .. " must be a whole number"
                end
            elseif not oneOf(value, rule) then
                return nil, name .. " has an unsupported value"
            end
        end
    end
    return true
end

-- Derived, not restated: core/config.lua owns these lists (see Config.STATUS_SLOTS).
local VALID_BAR_SLOTS = Config.STATUS_SLOTS
local VALID_BAR_PRESETS = Config.STATUS_PRESETS
local VALID_DIVIDER_STYLES = Config.STATUS_DIVIDERS

-- The accepted field names are exactly the keys normalize() keeps, so take them from the
-- defaults rather than typing them out again. PresetCodec.bundle exports
-- Config.normalize(config) verbatim, which means any key in the defaults but missing from
-- this set makes every exported preset unimportable -- and that is not hypothetical:
-- chapter_ticks was added to the header defaults and not to the hand-written list here,
-- so "unknown custom header field: chapter_ticks" rejected every file the plugin wrote.
-- Two table walks at load time, on a module that only runs on import or export.
local function fieldSet(defaults)
    local set = {}
    for key in pairs(defaults) do set[key] = true end
    return set
end
local BAR_DEFAULTS = Config.defaults()
local HEADER_FIELDS = fieldSet(BAR_DEFAULTS.custom_header)
local FOOTER_FIELDS = fieldSet(BAR_DEFAULTS.custom_footer)

-- An export written by an older build can carry a legacy slot or divider id.
-- Config.normalize translates those on the way in, so the importer must not reject them
-- before normalize ever sees them -- otherwise a file the plugin itself wrote is
-- unimportable. Same alias tables as normalize, so the two cannot disagree.
local function canonicalBarId(id, aliases)
    if type(id) ~= "string" then return id end
    return aliases[id] or id
end

-- Everything a bar config has in common: the same slot ids, presets, dividers and font
-- range apply to the header and the footer, so the checks live in one place and only the
-- field set and the label differ.
local function validateBar(value, fields, label)
    if value == nil then return true end
    if type(value) ~= "table" then return nil, label .. " must be an object" end
    local ok, err = onlyKeys(value, fields, label .. " field")
    if not ok then return nil, err end
    if value.enabled ~= nil and type(value.enabled) ~= "boolean" then
        return nil, "enabled must be a boolean"
    end
    if value.preset ~= nil and not oneOf(value.preset, VALID_BAR_PRESETS) then
        return nil, "preset has an unsupported value"
    end
    for _, slot in ipairs({ "left", "center", "right" }) do
        if value[slot] ~= nil
                and not oneOf(canonicalBarId(value[slot], Config.STATUS_SLOT_ALIASES),
                    VALID_BAR_SLOTS) then
            return nil, slot .. " has an unsupported value"
        end
    end
    if value.divider_style ~= nil
            and not oneOf(canonicalBarId(value.divider_style, Config.STATUS_DIVIDER_ALIASES),
                VALID_DIVIDER_STYLES) then
        return nil, "divider_style has an unsupported value"
    end
    if value.divider_position ~= nil
            and not oneOf(value.divider_position, { "auto", "above", "below" }) then
        return nil, "divider_position has an unsupported value"
    end
    -- Numbers are rejected here, not clamped, while Config.normalize clamps the same
    -- fields instead of resetting them. That difference is deliberate: normalize runs on a
    -- saved config with no user present, so silently keeping the reader's intent beats
    -- discarding it -- whereas an import is an explicit action with a visible error
    -- message, and a file that says 30 should not quietly become 28. Legacy *ids* are
    -- still translated above, because a renamed id carries the same intent; a number out
    -- of range does not.
    if value.divider_thickness ~= nil and (type(value.divider_thickness) ~= "number"
            or value.divider_thickness % 1 ~= 0 or value.divider_thickness < 1
            or value.divider_thickness > Config.STATUS_DIVIDER_THICKNESS_MAX) then
        return nil, "divider_thickness is out of range"
    end
    if value.font_size ~= nil and (type(value.font_size) ~= "number"
            or value.font_size < Config.STATUS_FONT_MIN
            or value.font_size > Config.STATUS_FONT_MAX) then
        return nil, "font_size is out of range"
    end
    return true
end

local function validateCustomHeader(value)
    return validateBar(value, HEADER_FIELDS, "custom header")
end

local function validateCustomFooter(value)
    return validateBar(value, FOOTER_FIELDS, "custom footer")
end

local function validateConfig(value)
    if type(value) ~= "table" then return nil, "config must be an object" end
    local awareness_ok, awareness_err = validateAwareness(value.awareness)
    if not awareness_ok then return nil, awareness_err end
    local semantic_ok, semantic_err = validateSemanticDrawing(value.semantic_drawing)
    if not semantic_ok then return nil, semantic_err end
    local header_ok, header_err = validateCustomHeader(value.custom_header)
    if not header_ok then return nil, header_err end
    local footer_ok, footer_err = validateCustomFooter(value.custom_footer)
    if not footer_ok then return nil, footer_err end
    if value.underline ~= nil and type(value.underline) ~= "string" then
        return nil, "underline must be a string"
    end
    if value.line_thickness ~= nil and type(value.line_thickness) ~= "string" then
        return nil, "line_thickness must be a string"
    end
    if value.dash_pattern ~= nil and type(value.dash_pattern) ~= "string" then
        return nil, "dash_pattern must be a string"
    end
    if value.folio_scene ~= nil and not oneOf(value.folio_scene,
            { "off", "auto", "quiet", "study", "editorial", "chapter",
              "swiss", "terminal", "quote", "ticket", "cover", "gallery",
              "dossier", "archive", "bookpost", "architecture", "zen",
              "mei", "lan", "zhu", "ju", "custom", "random" }) then
        return nil, "unsupported folio scene"
    end
    if value.tweaks ~= nil and type(value.tweaks) ~= "table" then
        return nil, "tweaks must be an object"
    end
    if value.tweak_params ~= nil and type(value.tweak_params) ~= "table" then
        return nil, "tweak_params must be an object"
    end
    if value.koreader_settings ~= nil and type(value.koreader_settings) ~= "table" then
        return nil, "koreader_settings must be an object"
    end
    local config = Config.normalize(value)
    if not oneOf(config.underline, { "none", "all_lines", "para", "em_only", "marker" }) then
        return nil, "unsupported underline"
    end
    if not oneOf(config.dash_pattern, { "solid", "normal", "dense", "thick" }) then
        return nil, "unsupported stroke"
    end
    local thickness = config.line_thickness:match("^(%d+%.?%d*)px$")
    thickness = tonumber(thickness)
    if not thickness or thickness <= 0 or thickness > 20 then
        return nil, "line thickness is out of range"
    end
    if type(config.skip_headings) ~= "boolean" then
        return nil, "skip_headings must be a boolean"
    end
    local ok, err = validateParams(config)
    if not ok then return nil, err end
    return config
end

function PresetCodec.bundle(name, config, plugin_version)
    assert(validName(name), "preset name is required")
    return {
        format = PresetCodec.FORMAT,
        format_version = PresetCodec.FORMAT_VERSION,
        plugin_version = plugin_version,
        name = name,
        config = Config.normalize(config),
    }
end

function PresetCodec.validate(value)
    if type(value) ~= "table" then return nil, "root must be an object" end
    if value.format ~= PresetCodec.FORMAT then return nil, "unsupported preset format" end
    if value.format_version ~= PresetCodec.FORMAT_VERSION then
        return nil, "unsupported preset version"
    end
    if not validName(value.name) then return nil, "invalid preset name" end
    local config, err = validateConfig(value.config)
    if not config then return nil, err end
    return {
        format = PresetCodec.FORMAT,
        format_version = PresetCodec.FORMAT_VERSION,
        plugin_version = type(value.plugin_version) == "string" and value.plugin_version or nil,
        name = value.name,
        config = config,
    }
end

function PresetCodec.encode(name, config, plugin_version)
    local rapidjson = require("rapidjson")
    return rapidjson.encode(PresetCodec.bundle(name, config, plugin_version), { pretty = true })
end

function PresetCodec.decode(text)
    if type(text) ~= "string" or text == "" then return nil, "empty preset" end
    local rapidjson = require("rapidjson")
    local ok, value = pcall(rapidjson.decode, text)
    if not ok then return nil, tostring(value) end
    return PresetCodec.validate(value)
end

return PresetCodec
