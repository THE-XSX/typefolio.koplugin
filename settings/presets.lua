-- SPDX-FileCopyrightText: Copyright (C) 2026 THE-XSX
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- Typefolio (文笺) - KOReader plugin
-- Released under the GNU Affero General Public License v3.0 or later.
-- See the LICENSE file in the project root for the full license text.

-- settings/presets.lua
-- Presets settings: Built-in presets, custom presets CRUD, import/export preset files
local item_path = debug.getinfo(1, "S").source:sub(2)
local PLUGIN_ROOT = item_path:match("(.*[/\\]typefolio%.koplugin[/\\])") or item_path:match("(.*[/\\])settings[/\\]") or item_path:match("(.*[/\\])") or "plugins/typefolio.koplugin/"
local ModuleLoader = dofile(PLUGIN_ROOT .. "core/module_loader.lua")
local CSSTemplates = ModuleLoader.load(PLUGIN_ROOT, "css/css_templates.lua")
local InputDialog = require("ui/widget/inputdialog")
local PresetCodec = ModuleLoader.load(PLUGIN_ROOT, "css/preset_codec.lua")
local UIManager = require("ui/uimanager")
local ConfirmBox = require("ui/widget/confirmbox")

local PresetsSettings = {}

local function presetSummary(ctx, bundle, current)
    local tr = ctx.tr
    local folioSceneLabel = ctx.folioSceneLabel
    local enabledEffects = ctx.enabledEffects
    local config = bundle.config
    return string.format("%s\n\n%s\n%s: %s → %s\n%s: %s/%s → %s/%s\n%s: %s → %s\n%s:\n%s\n→ %s",
        bundle.name,
        tr("Current → Imported"),
        tr("Underline"), current.underline, config.underline,
        tr("Stroke"), current.dash_pattern, current.line_thickness,
            config.dash_pattern, config.line_thickness,
        tr("Folio scene"), folioSceneLabel(current.folio_scene), folioSceneLabel(config.folio_scene),
        tr("Effects"), enabledEffects(current), enabledEffects(config))
end

function PresetsSettings.customPresetEntryItems(ctx, name)
    local tr = ctx.tr
    local T = ctx.T
    local getCustomPresets = ctx.getCustomPresets
    local saveCustomPreset = ctx.saveCustomPreset
    local deleteCustomPreset = ctx.deleteCustomPreset
    local renameCustomPreset = ctx.renameCustomPreset
    local writePresetFile = ctx.writePresetFile
    local Config = ctx.Config
    local applyStyle = ctx.applyStyle
    local notify = ctx.notify

    return {
        {
            text = tr("Apply this preset"),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local preset = getCustomPresets()[name]
                if preset then
                    applyStyle(Config.clone(preset))
                    notify(T(tr("Applied preset: %1"), name))
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end
            end,
        },
        {
            text_func = function()
                local is_default = ctx.getDefaultNewBookPreset
                    and ctx.getDefaultNewBookPreset() == name
                return is_default and tr("Unset as default for new books")
                    or tr("Set as default for new books")
            end,
            keep_menu_open = true,
            checked_func = function()
                return ctx.getDefaultNewBookPreset and ctx.getDefaultNewBookPreset() == name
            end,
            callback = function(touchmenu_instance)
                if not ctx.setDefaultNewBookPreset then return end
                local is_default = ctx.getDefaultNewBookPreset
                    and ctx.getDefaultNewBookPreset() == name
                if is_default then
                    ctx.setDefaultNewBookPreset(nil)
                    notify(tr("Cleared default preset for new books"))
                else
                    ctx.setDefaultNewBookPreset(name)
                    notify(T(tr("Default preset for new books: %1"), name))
                end
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        },
        {
            text = tr("Export this preset"),
            keep_menu_open = true,
            callback = function()
                local preset = getCustomPresets()[name]
                local ui = ctx.ui
                local path, err = preset and writePresetFile(name, preset, ui)
                if path then
                    notify(T(tr("Preset exported to %1"), path))
                else
                    notify(T(tr("Preset export failed: %1"), tostring(err or "unknown")))
                end
            end,
        },
        {
            text = tr("Rename…"),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local dialog
                dialog = InputDialog:new{
                    title = tr("Rename preset"),
                    input = name,
                    buttons = {{{
                        text = tr("Cancel"),
                        callback = function() UIManager:close(dialog) end,
                    }, {
                        text = tr("Save"),
                        is_enter_default = true,
                        callback = function()
                            local new_name = dialog:getInputText()
                            if not new_name or new_name == "" or new_name == name then
                                UIManager:close(dialog)
                                return
                            end
                            if renameCustomPreset(name, new_name) then
                                UIManager:close(dialog)
                                notify(T(tr("Renamed to: %1"), new_name))
                                if touchmenu_instance then
                                    if touchmenu_instance.onSubMenuClose then
                                        touchmenu_instance:onSubMenuClose()
                                    end
                                    touchmenu_instance:updateItems()
                                end
                            else
                                notify(tr("Name already in use"))
                            end
                        end,
                    }}},
                }
                UIManager:show(dialog)
                dialog:onShowKeyboard()
            end,
        },
        {
            text = T(tr("Delete \"%1\""), name),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                deleteCustomPreset(name)
                notify(T(tr("Deleted preset: %1"), name))
                if touchmenu_instance then
                    if touchmenu_instance.onSubMenuClose then
                        touchmenu_instance:onSubMenuClose()
                    end
                    touchmenu_instance:updateItems()
                end
            end,
        },
    }
end

function PresetsSettings.customPresetItems(ctx)
    local tr = ctx.tr
    local T = ctx.T
    local getCustomPresets = ctx.getCustomPresets
    local saveCustomPreset = ctx.saveCustomPreset
    local getConfig = ctx.getConfig
    local notify = ctx.notify
    local ui = ctx.ui

    local presets = getCustomPresets()
    local names = {}
    for name in pairs(presets) do table.insert(names, name) end
    table.sort(names)
    local items = {}
    table.insert(items, {
        text = tr("＋ Save current as new preset"),
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            local dialog
            dialog = InputDialog:new{
                title = tr("Preset name"),
                input = T(tr("My preset %1"), tostring(#names + 1)),
                input_hint = tr("e.g. Night serif body"),
                buttons = {{{
                    text = tr("Cancel"),
                    callback = function() UIManager:close(dialog) end,
                }, {
                    text = tr("Save"),
                    is_enter_default = true,
                    callback = function()
                        local name = dialog:getInputText()
                        if not name or name == "" then return end
                        if presets[name] then
                            notify(tr("Name already in use"))
                            return
                        end
                        saveCustomPreset(name, getConfig(ui), ui)
                        UIManager:close(dialog)
                        notify(T(tr("Saved preset: %1"), name))
                        if touchmenu_instance then
                            touchmenu_instance:updateItems()
                        end
                    end,
                }}},
            }
            UIManager:show(dialog)
            dialog:onShowKeyboard()
        end,
    })
    if #names == 0 then
        table.insert(items, { text = tr("No custom presets yet"), enabled = false })
        return items
    end
    for _, name in ipairs(names) do
        local preset_name = name
        table.insert(items, {
            text_func = function()
                if ctx.getDefaultNewBookPreset and ctx.getDefaultNewBookPreset() == preset_name then
                    return "★ " .. preset_name
                end
                return preset_name
            end,
            keep_menu_open = true,
            sub_item_table_func = function() return PresetsSettings.customPresetEntryItems(ctx, preset_name) end,
        })
    end
    return items
end

function PresetsSettings.presetFileEntryItems(ctx, filename)
    local tr = ctx.tr
    local T = ctx.T
    local getPresetFolder = ctx.getPresetFolder
    local readPresetFile = ctx.readPresetFile
    local deletePresetFile = ctx.deletePresetFile
    local uniquePresetName = ctx.uniquePresetName
    local getCustomPresets = ctx.getCustomPresets
    local saveCustomPreset = ctx.saveCustomPreset
    local getConfig = ctx.getConfig
    local notify = ctx.notify
    local ui = ctx.ui

    local function closeAndRefresh(touchmenu_instance)
        if not touchmenu_instance then return end
        if touchmenu_instance.onSubMenuClose then
            touchmenu_instance:onSubMenuClose()
        end
        touchmenu_instance:updateItems()
    end

    return {
        {
            text = tr("Import this file"),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local bundle, err = readPresetFile(getPresetFolder() .. "/" .. filename)
                if not bundle then
                    notify(T(tr("Preset import failed: %1"), tostring(err or "unknown")))
                    return
                end
                UIManager:show(ConfirmBox:new{
                    text = presetSummary(ctx, bundle, getConfig(ui)),
                    ok_text = tr("Import"),
                    ok_callback = function()
                        local name = uniquePresetName(bundle.name, getCustomPresets())
                        saveCustomPreset(name, bundle.config)
                        notify(T(tr("Imported preset: %1"), name))
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                    cancel_text = tr("Cancel"),
                })
            end,
        },
        {
            text = tr("Delete this file"),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                UIManager:show(ConfirmBox:new{
                    text = T(tr("Delete preset file \"%1\"?"), filename),
                    ok_text = tr("Delete"),
                    ok_callback = function()
                        local ok, err = deletePresetFile(filename)
                        if ok then
                            notify(T(tr("Deleted preset file: %1"), filename))
                            closeAndRefresh(touchmenu_instance)
                        else
                            notify(T(tr("Preset file delete failed: %1"), tostring(err or "unknown")))
                        end
                    end,
                    cancel_text = tr("Cancel"),
                })
            end,
        },
    }
end

function PresetsSettings.presetFileItems(ctx)
    local tr = ctx.tr
    local T = ctx.T
    local listPresetFiles = ctx.listPresetFiles
    local getPresetFolder = ctx.getPresetFolder
    local writePresetFile = ctx.writePresetFile
    local getConfig = ctx.getConfig
    local notify = ctx.notify
    local ui = ctx.ui

    local files = listPresetFiles()
    local items = {
        {
            text = tr("Export current settings…"),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local dialog
                dialog = InputDialog:new{
                    title = tr("Preset name"),
                    input = tr("Exported preset"),
                    buttons = {{{
                        text = tr("Cancel"),
                        callback = function() UIManager:close(dialog) end,
                    }, {
                        text = tr("Export"),
                        is_enter_default = true,
                        callback = function()
                            local name = dialog:getInputText()
                            if not name or not name:match("%S") then return end
                            local path, err = writePresetFile(name, getConfig(ui), ui)
                            if path then
                                UIManager:close(dialog)
                                notify(T(tr("Preset exported to %1"), path))
                                if touchmenu_instance then touchmenu_instance:updateItems() end
                            else
                                notify(T(tr("Preset export failed: %1"), tostring(err or "unknown")))
                            end
                        end,
                    }}},
                }
                UIManager:show(dialog)
                dialog:onShowKeyboard()
            end,
        },
        {
            text = T(tr("Preset folder: %1"), getPresetFolder()),
            enabled = false,
            separator = true,
        },
    }

    if #files == 0 then
        table.insert(items, { text = tr("No preset files found"), enabled = false })
        return items
    end

    for _, filename in ipairs(files) do
        table.insert(items, {
            text = filename,
            keep_menu_open = true,
            sub_item_table_func = function() return PresetsSettings.presetFileEntryItems(ctx, filename) end,
        })
    end
    return items
end

function PresetsSettings.items(ctx)
    local tr = ctx.tr
    local T = ctx.T
    local getConfig = ctx.getConfig
    local applyStyle = ctx.applyStyle
    local notify = ctx.notify
    local ui = ctx.ui

    local keys = {}
    for key in pairs(CSSTemplates.presets) do table.insert(keys, key) end
    table.sort(keys, function(a, b)
        local pa, pb = CSSTemplates.presets[a], CSSTemplates.presets[b]
        local oa, ob = (pa and pa.order) or 999, (pb and pb.order) or 999
        if oa ~= ob then return oa < ob end
        return a < b
    end)
    local items = {}
    for _, key in ipairs(keys) do
        local preset = CSSTemplates.presets[key]
        table.insert(items, {
            text = T(tr("Preset: %1"), tr(preset.name)),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                -- Start from the reader's current config and let the preset overwrite only
                -- what it actually defines, preserving unrelated toggles (dialogue/emphasis
                -- painters, skip_headings, skip_blockquotes, awareness, etc.).
                local config = getConfig(ui)
                config.underline = preset.underline
                config.dash_pattern = preset.dash_pattern or "normal"
                config.tweaks = {}
                for tweak, enabled in pairs(preset.tweaks or {}) do
                    config.tweaks[tweak] = enabled
                end
                if type(preset.tweak_params) == "table" then
                    config.tweak_params = config.tweak_params or {}
                    for tweak, params in pairs(preset.tweak_params) do
                        if type(params) == "table" then
                            local copy = {}
                            for pk, pv in pairs(params) do copy[pk] = pv end
                            config.tweak_params[tweak] = copy
                        end
                    end
                end
                for _, bar in ipairs({ "custom_header", "custom_footer" }) do
                    local spec = preset[bar]
                    if type(spec) == "table" then
                        config[bar] = config[bar] or {}
                        for sk, sv in pairs(spec) do
                            config[bar][sk] = sv
                        end
                    end
                end
                config.koreader_settings = {}
                if type(preset.koreader_settings) == "table" then
                    for kk, kv in pairs(preset.koreader_settings) do
                        if type(kv) == "table" then
                            local list = {}
                            for idx, item_val in ipairs(kv) do list[idx] = item_val end
                            config.koreader_settings[kk] = list
                        else
                            config.koreader_settings[kk] = kv
                        end
                    end
                end
                applyStyle(config)
                notify(T(tr("Applied preset: %1"), tr(preset.name)))
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        })
    end
    if #items > 0 then
        items[#items].separator = true
    end
    table.insert(items, {
        text = tr("Custom presets"),
        sub_item_table_func = function() return PresetsSettings.customPresetItems(ctx) end,
    })
    table.insert(items, {
        text = tr("Import / export presets"),
        sub_item_table_func = function() return PresetsSettings.presetFileItems(ctx) end,
        separator = true,
    })
    table.insert(items, {
        text = tr("Restore default typesetting"),
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            -- Same hazard as the preset rows above, and it was still live here: a bare
            -- literal handed to applyStyle is not a patch. Config.normalize fills every
            -- absent section from the defaults, so this row also switched off both status
            -- bars, the folio scene and all three painters -- while the notification
            -- promised only that the typesetting tweaks were reset. Start from the current
            -- config (getConfig returns a normalized copy) and reset the typesetting keys
            -- only.
            local config = getConfig(ui)
            config.underline = "none"
            config.line_thickness = "1.5px"
            config.dash_pattern = "normal"
            config.tweaks = {}
            config.tweak_params = {}
            config.koreader_settings = {}
            applyStyle(config)
            notify(tr("All typesetting tweaks reset"))
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    })
    return items
end

return PresetsSettings
