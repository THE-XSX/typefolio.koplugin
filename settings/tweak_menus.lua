-- SPDX-FileCopyrightText: Copyright (C) 2026 THE-XSX
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- Typefolio (文笺) - KOReader plugin
-- Released under the GNU Affero General Public License v3.0 or later.
-- See the LICENSE file in the project root for the full license text.

-- settings/tweak_menus.lua
-- Submenus for CSS/painter typesetting tweaks (chapter headers, blockquotes,
-- dialogue styling & font switching, drop caps, emphasis dots).
local item_path = debug.getinfo(1, "S").source:sub(2)
local PLUGIN_ROOT = item_path:match("(.*[/\\]typefolio%.koplugin[/\\])")
    or item_path:match("(.*[/\\])settings[/\\]")
    or item_path:match("(.*[/\\])")
    or "plugins/typefolio.koplugin/"

local ModuleLoader = dofile(PLUGIN_ROOT .. "core/module_loader.lua")
local CSSTemplates = ModuleLoader.load(PLUGIN_ROOT, "css/css_templates.lua")
local Config = ModuleLoader.load(PLUGIN_ROOT, "core/config.lua")
local EpubDialogueTagger = ModuleLoader.load(PLUGIN_ROOT, "tools/epub_dialogue_tagger.lua")

local ConfirmBox = require("ui/widget/confirmbox")
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")

local TweakMenus = {}

local LINE_STYLE_LABELS = {
    solid = "Solid", dashed = "Dashed", dotted = "Dotted",
}
local BORDER_LABELS = {
    both = "Top and bottom", bottom = "Bottom only", top = "Top only", none = "No border",
}
local TINT_LABELS = {
    none = "No background", light = "Light tint", medium = "Medium tint",
}
local TINT_LEVEL_LABELS = {
    light = "Light", medium = "Medium", strong = "Strong",
}
local FONT_WEIGHT_LABELS = {
    default = "Follow body",
    ["300"] = "Light (300)",
    normal = "Normal (400)",
    ["600"] = "Medium (600)",
    bold = "Bold (700)",
    ["900"] = "Heavy (900)",
}

local function readConfig(ctx)
    if ctx.getReadonlyConfig then
        return ctx.getReadonlyConfig(ctx.ui)
    end
    return ctx.getConfig(ctx.ui)
end

local function getParam(ctx, tweak_key, name)
    local params = readConfig(ctx).tweak_params[tweak_key]
    local value = params and params[name]
    if value == nil then
        local defaults = CSSTemplates.tweak_defaults[tweak_key]
        return defaults and defaults[name]
    end
    return value
end

local function setParam(ctx, tweak_key, name, value)
    local config = ctx.getConfig(ctx.ui)
    config.tweak_params[tweak_key] = config.tweak_params[tweak_key] or {}
    config.tweak_params[tweak_key][name] = value
    ctx.applyStyle(config)
end

local function getDialoguePainter(ctx, name)
    return readConfig(ctx).dialogue_painter[name]
end

local function setDialoguePainter(ctx, name, value)
    local config = ctx.getConfig(ctx.ui)
    config.dialogue_painter[name] = value
    ctx.applyStyle(config)
end

local function getEmphasisPainter(ctx, name)
    return readConfig(ctx).emphasis_painter[name]
end

local function setEmphasisPainter(ctx, name, value)
    local config = ctx.getConfig(ctx.ui)
    config.emphasis_painter[name] = value
    ctx.applyStyle(config)
end

local function setDialogueTintLevel(ctx, value)
    local config = ctx.getConfig(ctx.ui)
    config.tweak_params.dialogue_style = config.tweak_params.dialogue_style or {}
    config.tweak_params.dialogue_style.tint_level = value
    config.dialogue_painter.tint_level = value
    ctx.applyStyle(config)
end

function TweakMenus.dialogueActive(ctx)
    local config = readConfig(ctx)
    return config.tweaks.dialogue_style == true
        or config.dialogue_painter.enabled == true
end

function TweakMenus.toggleDialogue(ctx)
    local config = ctx.getConfig(ctx.ui)
    local turn_on = not (config.tweaks.dialogue_style == true
        or config.dialogue_painter.enabled == true)
    config.tweaks.dialogue_style = turn_on
    config.dialogue_painter.enabled = turn_on
    ctx.applyStyle(config)
end

local function paramRadio(ctx, tweak_key, name, values, label_of)
    local items = {}
    for _, value in ipairs(values or {}) do
        table.insert(items, {
            text = label_of(value),
            radio = true,
            keep_menu_open = true,
            enabled_func = function() return readConfig(ctx).tweaks[tweak_key] == true end,
            checked_func = function() return getParam(ctx, tweak_key, name) == value end,
            callback = function(touchmenu_instance)
                setParam(ctx, tweak_key, name, value)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        })
    end
    return items
end

local function paramSpin(ctx, tweak_key, name, spec)
    local tr = ctx.tr
    local T = ctx.T
    return {
        text_func = function()
            local value = getParam(ctx, tweak_key, name)
            local shown = spec.precision and string.format(spec.precision, value) or tostring(value)
            return T(tr(spec.label), shown .. (spec.unit or ""))
        end,
        keep_menu_open = true,
        enabled_func = function()
            if readConfig(ctx).tweaks[tweak_key] ~= true then return false end
            return not spec.extra_enabled or spec.extra_enabled()
        end,
        callback = function(touchmenu_instance)
            UIManager:show(SpinWidget:new{
                title_text = tr(spec.title),
                value = getParam(ctx, tweak_key, name),
                value_min = spec.min,
                value_max = spec.max,
                value_step = spec.step or 1,
                value_hold_step = spec.hold_step or (spec.step or 1) * 2,
                precision = spec.precision,
                unit = spec.unit,
                default_value = CSSTemplates.tweak_defaults[tweak_key][name],
                ok_always_enabled = true,
                callback = function(spin)
                    setParam(ctx, tweak_key, name, spin.value)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            })
        end,
    }
end

local function paramToggle(ctx, tweak_key, name, label)
    local tr = ctx.tr
    return {
        text = tr(label),
        keep_menu_open = true,
        enabled_func = function() return readConfig(ctx).tweaks[tweak_key] == true end,
        checked_func = function() return getParam(ctx, tweak_key, name) == true end,
        callback = function(touchmenu_instance)
            setParam(ctx, tweak_key, name, not getParam(ctx, tweak_key, name))
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    }
end

local function tweakEnableItem(ctx, tweak_key, title)
    local tr = ctx.tr
    local T = ctx.T
    return {
        text_func = function()
            local on = readConfig(ctx).tweaks[tweak_key] == true
            return T(tr("%1: %2"), tr(title),
                on and tr("Enabled") or tr("Disabled"))
        end,
        keep_menu_open = true,
        checked_func = function() return readConfig(ctx).tweaks[tweak_key] == true end,
        callback = function(touchmenu_instance)
            local config = ctx.getConfig(ctx.ui)
            config.tweaks[tweak_key] = not config.tweaks[tweak_key]
            ctx.applyStyle(config)
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
        separator = true,
    }
end

local function listAvailableFontFaces(ctx)
    if type(ctx.listFontFaces) == "function" then
        return ctx.listFontFaces()
    end
    local faces, seen = {}, {}
    local function collect(list)
        if type(list) ~= "table" then return end
        for _, face in ipairs(list) do
            local sanitized = Config.sanitizeFontFamily(face)
            if sanitized ~= "" and not seen[sanitized] then
                seen[sanitized] = true
                table.insert(faces, sanitized)
            end
        end
    end
    local ok_cre, cre = pcall(require, "libs/libkoreader-cre")
    if ok_cre and cre and type(cre.getFontFaces) == "function" then
        local ok_faces, cre_faces = pcall(cre.getFontFaces)
        if ok_faces then collect(cre_faces) end
    end
    if #faces == 0 then
        local ok_fl, FontList = pcall(require, "ui/fontlist")
        if ok_fl and FontList and type(FontList.getFontList) == "function" then
            local ok_list, fl_faces = pcall(function() return FontList:getFontList() end)
            if ok_list then collect(fl_faces) end
        end
    end
    table.sort(faces)
    return faces
end

function TweakMenus.dialogueFontItems(ctx)
    local tr = ctx.tr
    local T = ctx.T
    local currentFont = function()
        return Config.sanitizeFontFamily(getParam(ctx, "dialogue_style", "font_family"))
    end
    local selectFont = function(face, touchmenu_instance)
        local config = ctx.getConfig(ctx.ui)
        config.tweak_params.dialogue_style = config.tweak_params.dialogue_style or {}
        config.tweak_params.dialogue_style.font_family = face
        if face ~= "" then
            config.tweaks.dialogue_style = true
        end
        ctx.applyStyle(config)
        if touchmenu_instance then touchmenu_instance:updateItems() end

        if face ~= "" and ctx.hasDialogueClassMarkup and not ctx.hasDialogueClassMarkup()
                and ctx.canGenerateDialogueCopy and ctx.canGenerateDialogueCopy() then
            if ctx.hasExistingDialogueCopy and ctx.hasExistingDialogueCopy() then
                UIManager:show(ConfirmBox:new{
                    text = tr("An existing dialogue-tagged copy was found for this book. Open it now to apply the dialogue font?"),
                    ok_text = tr("Open copy"),
                    ok_callback = function()
                        if ctx.openDialogueTaggedCopy then
                            ctx.openDialogueTaggedCopy(touchmenu_instance)
                        end
                    end,
                    cancel_text = tr("Later"),
                })
            else
                UIManager:show(ConfirmBox:new{
                    text = tr("This EPUB has no dialogue class markup yet, so changing the dialogue font requires a dialogue-tagged copy. Generate a cached copy now without modifying the original book?"),
                    ok_text = tr("Generate & open"),
                    ok_callback = function()
                        if ctx.generateDialogueTaggedCopy then
                            ctx.generateDialogueTaggedCopy(touchmenu_instance)
                        end
                    end,
                    cancel_text = tr("Later"),
                })
            end
        end
    end

    local items = {
        {
            text = tr("Follow body font"),
            radio = true,
            keep_menu_open = true,
            checked_func = function() return currentFont() == "" end,
            callback = function(touchmenu_instance)
                selectFont("", touchmenu_instance)
            end,
            separator = true,
        },
    }

    local faces = listAvailableFontFaces(ctx)
    local active = currentFont()
    local active_listed = (active == "")
    for _, face in ipairs(faces) do
        if face == active then active_listed = true end
        table.insert(items, {
            text = face,
            radio = true,
            keep_menu_open = true,
            checked_func = function() return currentFont() == face end,
            callback = function(touchmenu_instance)
                selectFont(face, touchmenu_instance)
            end,
        })
    end
    if not active_listed and active ~= "" then
        table.insert(items, 2, {
            text = T(tr("%1 (saved)"), active),
            radio = true,
            keep_menu_open = true,
            checked_func = function() return currentFont() == active end,
            callback = function(touchmenu_instance)
                selectFont(active, touchmenu_instance)
            end,
        })
    end
    if #faces == 0 then
        table.insert(items, {
            text = tr("No additional fonts detected"),
            enabled = false,
        })
    end
    return items
end

function TweakMenus.dialogueFontWeightItems(ctx)
    local tr = ctx.tr
    local items = {}
    local weights = CSSTemplates.tweak_options.font_weight or { "default", "300", "normal", "600", "bold", "900" }
    for _, value in ipairs(weights) do
        table.insert(items, {
            text = tr(FONT_WEIGHT_LABELS[value] or value),
            radio = true,
            keep_menu_open = true,
            enabled_func = function() return readConfig(ctx).tweaks.dialogue_style == true end,
            checked_func = function()
                local current = getParam(ctx, "dialogue_style", "font_weight") or "default"
                return current == value
            end,
            callback = function(touchmenu_instance)
                setParam(ctx, "dialogue_style", "font_weight", value)
                local config = ctx.getConfig(ctx.ui)
                config.tweak_params.dialogue_style = config.tweak_params.dialogue_style or {}
                if value == "bold" or value == "900" or value == "600" then
                    config.tweak_params.dialogue_style.bold = true
                elseif value == "normal" or value == "300" then
                    config.tweak_params.dialogue_style.bold = false
                end
                ctx.applyStyle(config)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        })
    end
    return items
end

function TweakMenus.dialoguePainterItems(ctx)
    local tr = ctx.tr
    local T = ctx.T
    local O = CSSTemplates.tweak_options
    local painterOn = function() return getDialoguePainter(ctx, "enabled") == true end

    local mode_labels = {
        tint = "Background tint (quoted text)",
        underline = "Underline (quoted text)",
        side_bar = "Side bar (whole line)",
    }
    local mode_items = {}
    for _, value in ipairs({ "tint", "underline", "side_bar" }) do
        table.insert(mode_items, {
            text = tr(mode_labels[value]),
            radio = true,
            keep_menu_open = true,
            enabled_func = painterOn,
            checked_func = function() return getDialoguePainter(ctx, "mode") == value end,
            callback = function(touchmenu_instance)
                setDialoguePainter(ctx, "mode", value)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        })
    end

    local lang_labels = {
        all = "All quotes (Chinese & English)",
        cn = "Chinese quotes (“...” / 「...」)",
        en = "English quotes (“...” / \"...\")",
    }
    local lang_items = {}
    for _, value in ipairs({ "all", "cn", "en" }) do
        table.insert(lang_items, {
            text = tr(lang_labels[value]),
            radio = true,
            keep_menu_open = true,
            enabled_func = painterOn,
            checked_func = function() return getDialoguePainter(ctx, "lang") == value end,
            callback = function(touchmenu_instance)
                setDialoguePainter(ctx, "lang", value)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        })
    end

    local tint_items = {}
    for _, value in ipairs(O.tint_level) do
        table.insert(tint_items, {
            text = tr(TINT_LEVEL_LABELS[value]),
            radio = true,
            keep_menu_open = true,
            checked_func = function()
                return getParam(ctx, "dialogue_style", "tint_level") == value
            end,
            callback = function(touchmenu_instance)
                setDialogueTintLevel(ctx, value)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        })
    end

    return {
        {
            text_func = function()
                local status
                if ctx.isDialoguePainterSuppressedByCss and ctx.isDialoguePainterSuppressedByCss() then
                    status = tr("Auto-paused (class markup active)")
                else
                    status = painterOn() and tr("Enabled") or tr("Disabled")
                end
                return T(tr("%1: %2"), tr("Dynamic quotes (No EPUB edit)"), status)
            end,
            keep_menu_open = true,
            checked_func = painterOn,
            callback = function(touchmenu_instance)
                setDialoguePainter(ctx, "enabled", not painterOn())
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
            separator = true,
        },
        {
            text = tr("Marking style"),
            enabled_func = painterOn,
            sub_item_table = mode_items,
        },
        {
            text = tr("Target quotes language"),
            enabled_func = painterOn,
            sub_item_table = lang_items,
        },
        {
            text = tr("Tint intensity"),
            enabled_func = function()
                local config = readConfig(ctx)
                local css_tint = config.tweaks.dialogue_style == true
                    and getParam(ctx, "dialogue_style", "tint") == true
                local paint_tint = painterOn()
                    and getDialoguePainter(ctx, "mode") == "tint"
                return css_tint or paint_tint
            end,
            sub_item_table = tint_items,
        },
        {
            text_func = function()
                local value = getDialoguePainter(ctx, "vertical_inset") or 0
                if value == 0 then
                    return T(tr("Vertical inset: %1"), tr("None"))
                end
                return T(tr("Vertical inset: %1"), value .. "px")
            end,
            keep_menu_open = true,
            enabled_func = painterOn,
            callback = function(touchmenu_instance)
                UIManager:show(SpinWidget:new{
                    title_text = tr("Mark vertical inset"),
                    info_text = tr("How far the mark keeps off the top and bottom of the line. Applies to all three marking styles."),
                    value = getDialoguePainter(ctx, "vertical_inset") or 0,
                    value_min = 0,
                    value_max = Config.DIALOGUE_INSET_MAX,
                    value_step = 1,
                    value_hold_step = 2,
                    unit = "px",
                    default_value = 0,
                    ok_always_enabled = true,
                    callback = function(spin)
                        setDialoguePainter(ctx, "vertical_inset", spin.value)
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                })
            end,
        },
    }
end

function TweakMenus.emphasisItems(ctx)
    local tr = ctx.tr
    local T = ctx.T
    local on = function() return getEmphasisPainter(ctx, "enabled") == true end
    local defaults = Config.defaults().emphasis_painter
    return {
        {
            text_func = function()
                return T(tr("%1: %2"), tr("Emphasis dots painter"),
                    on() and tr("Enabled") or tr("Disabled"))
            end,
            keep_menu_open = true,
            checked_func = on,
            callback = function(touchmenu_instance)
                setEmphasisPainter(ctx, "enabled", not on())
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
            separator = true,
        },
        {
            text_func = function()
                local value = tonumber(getEmphasisPainter(ctx, "size")) or defaults.size
                return T(tr("Dot size: %1 px"), tostring(value))
            end,
            keep_menu_open = true,
            enabled_func = on,
            callback = function(touchmenu_instance)
                UIManager:show(SpinWidget:new{
                    title_text = tr("Emphasis dot size"),
                    value = tonumber(getEmphasisPainter(ctx, "size")) or defaults.size,
                    value_min = Config.EMPHASIS_SIZE_MIN,
                    value_max = Config.EMPHASIS_SIZE_MAX,
                    value_step = 1,
                    value_hold_step = 1,
                    unit = "px",
                    default_value = defaults.size,
                    ok_always_enabled = true,
                    callback = function(spin)
                        setEmphasisPainter(ctx, "size", spin.value)
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                })
            end,
        },
        {
            text_func = function()
                local value = tonumber(getEmphasisPainter(ctx, "gap")) or defaults.gap
                return T(tr("Dot spacing: %1 px"), tostring(value))
            end,
            keep_menu_open = true,
            enabled_func = on,
            callback = function(touchmenu_instance)
                UIManager:show(SpinWidget:new{
                    title_text = tr("Emphasis dot spacing"),
                    value = tonumber(getEmphasisPainter(ctx, "gap")) or defaults.gap,
                    value_min = Config.EMPHASIS_GAP_MIN,
                    value_max = Config.EMPHASIS_GAP_MAX,
                    value_step = 1,
                    value_hold_step = 2,
                    unit = "px",
                    default_value = defaults.gap,
                    ok_always_enabled = true,
                    callback = function(spin)
                        setEmphasisPainter(ctx, "gap", spin.value)
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                })
            end,
        },
    }
end

function TweakMenus.tweakSubItems(ctx, key)
    local tr = ctx.tr
    local T = ctx.T
    local O = CSSTemplates.tweak_options
    local lineStyle = function()
        return paramRadio(ctx, key, "line_style", O.line_style,
            function(v) return tr(LINE_STYLE_LABELS[v]) end)
    end

    if key == "header_border" then
        return {
            tweakEnableItem(ctx, key, "Chapter title"),
            { text = tr("Border position"),
              enabled_func = function() return readConfig(ctx).tweaks[key] == true end,
              sub_item_table = paramRadio(ctx, key, "border", O.border,
                  function(v) return tr(BORDER_LABELS[v]) end) },
            { text = tr("Line style"),
              enabled_func = function()
                  return readConfig(ctx).tweaks[key] == true
                      and getParam(ctx, key, "border") ~= "none"
              end,
              sub_item_table = lineStyle() },
            paramSpin(ctx, key, "thickness",
                { label = "Line thickness: %1", title = "Header line thickness",
                  min = 1, max = 5, unit = "px",
                  extra_enabled = function() return getParam(ctx, key, "border") ~= "none" end }),
            paramToggle(ctx, key, "centered", "Center headers"),
            paramToggle(ctx, key, "include_centered", "Also style centered paragraphs"),
        }
    elseif key == "blockquote_box" then
        return {
            tweakEnableItem(ctx, key, "Blockquote"),
            paramSpin(ctx, key, "bar",
                { label = "Left bar thickness: %1", title = "Left bar thickness",
                  min = 0, max = 10, unit = "px" }),
            { text = tr("Background tint"),
              enabled_func = function() return readConfig(ctx).tweaks[key] == true end,
              sub_item_table = paramRadio(ctx, key, "tint", O.tint,
                  function(v) return tr(TINT_LABELS[v]) end) },
            paramToggle(ctx, key, "italic", "Italic text"),
        }
    elseif key == "dialogue_style" then
        local items = {}
        for _, item in ipairs(TweakMenus.dialoguePainterItems(ctx)) do
            table.insert(items, item)
        end
        items[#items].separator = true
        table.insert(items, tweakEnableItem(ctx, key, "Styling via class markup"))
        table.insert(items, {
            text_func = function()
                local font = Config.sanitizeFontFamily(getParam(ctx, "dialogue_style", "font_family"))
                return T(tr("Dialogue font: %1"), font ~= "" and font or tr("Follow body font"))
            end,
            keep_menu_open = true,
            enabled_func = function() return readConfig(ctx).tweaks[key] == true end,
            sub_item_table_func = function() return TweakMenus.dialogueFontItems(ctx) end,
        })
        table.insert(items, paramToggle(ctx, key, "include_quotes", "Quote marks inherit dialogue font"))
        table.insert(items, paramSpin(ctx, key, "font_scale", {
            label = "Dialogue font scale: %1",
            title = "Dialogue font scale",
            min = 70, max = 150, step = 5, hold_step = 10,
            unit = "%",
        }))
        table.insert(items, paramSpin(ctx, key, "text_depth", {
            label = "Dialogue text darkness: %1",
            title = "Dialogue text darkness",
            min = 40, max = 100, step = 5, hold_step = 10,
            unit = "%",
        }))
        table.insert(items, {
            text_func = function()
                local weight = getParam(ctx, key, "font_weight") or "default"
                local label = FONT_WEIGHT_LABELS[weight] or "Follow body"
                return T(tr("Dialogue font weight: %1"), tr(label))
            end,
            keep_menu_open = true,
            enabled_func = function() return readConfig(ctx).tweaks[key] == true end,
            sub_item_table_func = function() return TweakMenus.dialogueFontWeightItems(ctx) end,
        })
        table.insert(items, paramToggle(ctx, key, "tint", "Background tint"))
        table.insert(items, paramToggle(ctx, key, "italic", "Italic"))
        items[#items].separator = true
        local doc_file = ctx.ui and ctx.ui.document and ctx.ui.document.file
        if EpubDialogueTagger.isTaggedCopy(doc_file) then
            table.insert(items, {
                text = tr("Dialogue-tagged copy active"),
                enabled_func = function() return false end,
            })
            table.insert(items, {
                text = tr("Return to original book…"),
                keep_menu_open = false,
                callback = function(touchmenu_instance)
                    UIManager:show(ConfirmBox:new{
                        text = tr("Return to original untagged book? Auto-opening the dialogue copy will be paused."),
                        ok_text = tr("Return to original"),
                        ok_callback = function()
                            if ctx.returnToOriginalBook then
                                ctx.returnToOriginalBook(touchmenu_instance)
                            end
                        end,
                        cancel_text = tr("Cancel"),
                    })
                end,
            })
            table.insert(items, {
                text = tr("Regenerate dialogue-tagged copy…"),
                keep_menu_open = true,
                enabled_func = function()
                    return ctx.canGenerateDialogueCopy and ctx.canGenerateDialogueCopy() or false
                end,
                callback = function(touchmenu_instance)
                    if ctx.regenerateDialogueTaggedCopy then
                        ctx.regenerateDialogueTaggedCopy(touchmenu_instance)
                    end
                end,
            })
        elseif ctx.hasExistingDialogueCopy and ctx.hasExistingDialogueCopy() then
            table.insert(items, {
                text = tr("Auto-open dialogue copy"),
                keep_menu_open = true,
                checked_func = function()
                    return ctx.isAutoOpenDialogueCopyEnabled and ctx.isAutoOpenDialogueCopyEnabled() or false
                end,
                callback = function(touchmenu_instance)
                    local curr = ctx.isAutoOpenDialogueCopyEnabled and ctx.isAutoOpenDialogueCopyEnabled() or false
                    if ctx.setAutoOpenDialogueCopyEnabled then
                        ctx.setAutoOpenDialogueCopyEnabled(not curr)
                    end
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            })
            table.insert(items, {
                text = tr("Open existing dialogue copy"),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    if ctx.openDialogueTaggedCopy then
                        ctx.openDialogueTaggedCopy(touchmenu_instance)
                    end
                end,
            })
            table.insert(items, {
                text = tr("Regenerate dialogue-tagged copy…"),
                keep_menu_open = true,
                enabled_func = function()
                    return ctx.canGenerateDialogueCopy and ctx.canGenerateDialogueCopy() or false
                end,
                callback = function(touchmenu_instance)
                    if ctx.regenerateDialogueTaggedCopy then
                        ctx.regenerateDialogueTaggedCopy(touchmenu_instance)
                    end
                end,
            })
        else
            table.insert(items, {
                text = tr("Generate dialogue-tagged copy…"),
                keep_menu_open = true,
                enabled_func = function()
                    return ctx.canGenerateDialogueCopy and ctx.canGenerateDialogueCopy() or false
                end,
                callback = function(touchmenu_instance)
                    if ctx.generateDialogueTaggedCopy then
                        ctx.generateDialogueTaggedCopy(touchmenu_instance)
                    end
                end,
            })
        end
        table.insert(items, {
            text_func = function()
                local info = ctx.getDialogueCacheSummary and ctx.getDialogueCacheSummary()
                if info and info.count > 0 then
                    return T(tr("Clear dialogue cache copies (%1, %2 MB)…"),
                        tostring(info.count), string.format("%.1f", info.total_bytes / (1024 * 1024)))
                end
                return tr("Clear dialogue cache copies…")
            end,
            keep_menu_open = true,
            enabled_func = function()
                local info = ctx.getDialogueCacheSummary and ctx.getDialogueCacheSummary()
                return info ~= nil and info.count > 0
            end,
            callback = function(touchmenu_instance)
                local info = ctx.getDialogueCacheSummary and ctx.getDialogueCacheSummary()
                if not info or info.count == 0 then return end
                UIManager:show(ConfirmBox:new{
                    text = T(tr("Delete %1 cached dialogue-tagged EPUB copy/copies (%2 MB)? Original books will not be affected."),
                        tostring(info.count), string.format("%.1f", info.total_bytes / (1024 * 1024))),
                    ok_text = tr("Delete"),
                    ok_callback = function()
                        if ctx.clearDialogueCache then
                            ctx.clearDialogueCache()
                        end
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                    cancel_text = tr("Cancel"),
                })
            end,
        })
        return items
    elseif key == "chapter_pagebreak" then
        return {
            tweakEnableItem(ctx, key, "Chapter page break"),
            paramToggle(ctx, key, "include_centered", "Also break on centered paragraphs"),
        }
    elseif key == "drop_caps" then
        return {
            tweakEnableItem(ctx, key, "Drop caps"),
            paramSpin(ctx, key, "scale",
                { label = "Size: %1", title = "Drop cap size",
                  min = 1.5, max = 3.5, step = 0.1, hold_step = 0.5,
                  precision = "%.1f", unit = "em" }),
            paramToggle(ctx, key, "bold", "Bold"),
        }
    end
    return nil
end

function TweakMenus.tweakItems(ctx, options)
    local tr = ctx.tr
    local items = {}
    for _, option in ipairs(options or {}) do
        local key = option.key
        local sub_items = TweakMenus.tweakSubItems(ctx, key)
        local is_dialogue = key == "dialogue_style"
        local checked = is_dialogue
            and function() return TweakMenus.dialogueActive(ctx) end
            or function() return readConfig(ctx).tweaks[key] == true end
        local toggle = function(touchmenu_instance)
            if is_dialogue then
                TweakMenus.toggleDialogue(ctx)
            else
                local config = ctx.getConfig(ctx.ui)
                config.tweaks[key] = not config.tweaks[key]
                ctx.applyStyle(config)
            end
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end
        table.insert(items, {
            text = tr(option.text),
            keep_menu_open = true,
            checked_func = checked,
            checkmark_callback = sub_items and toggle or nil,
            callback = not sub_items and toggle or nil,
            sub_item_table = sub_items,
        })
    end
    return items
end

return TweakMenus
