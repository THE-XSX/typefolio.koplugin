-- settings/presets.lua
-- Presets settings: Built-in presets, custom presets CRUD, import/export preset files
local item_path = debug.getinfo(1, "S").source:sub(2)
local PLUGIN_ROOT = item_path:match("(.*[/\\]typefolio%.koplugin[/\\])") or item_path:match("(.*[/\\])settings[/\\]") or item_path:match("(.*[/\\])") or "plugins/typefolio.koplugin/"
local CSSTemplates = dofile(PLUGIN_ROOT .. "css/css_templates.lua")
local InputDialog = require("ui/widget/inputdialog")
local PresetCodec = dofile(PLUGIN_ROOT .. "css/preset_codec.lua")
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
        table.insert(items, {
            text = name,
            keep_menu_open = true,
            sub_item_table_func = function() return PresetsSettings.customPresetEntryItems(ctx, name) end,
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
    table.sort(keys)
    local items = {}
    for _, key in ipairs(keys) do
        local preset = CSSTemplates.presets[key]
        table.insert(items, {
            text = T(tr("Preset: %1"), tr(preset.name)),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                -- Start from the reader's current config and let the preset overwrite only
                -- what it actually defines. This used to be a hand-written list of the keys
                -- worth carrying over, which meant every setting added afterwards -- the
                -- dialogue and emphasis painters, "skip blockquotes" -- was absent from the
                -- table and Config.normalize quietly reset it to its default the first time
                -- a preset was applied. getConfig already returns a normalized copy, so
                -- mutating it here cannot touch the stored config.
                local config = getConfig(ui)
                config.underline = preset.underline
                config.dash_pattern = preset.dash_pattern or "normal"
                -- A preset is not a KOReader-settings payload; drop anything left over.
                config.koreader_settings = {}
                config.tweaks = {}
                for tweak, enabled in pairs(preset.tweaks) do
                    config.tweaks[tweak] = enabled
                end
                applyStyle(config)
                notify(T(tr("Applied preset: %1"), tr(preset.name)))
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        })
    end
    table.insert(items, {
        text = tr("Restore default typesetting"),
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            applyStyle({
                underline = "none",
                line_thickness = "1.5px",
                dash_pattern = "normal",
                tweaks = {},
                tweak_params = {},
            })
            notify(tr("All typesetting tweaks reset"))
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    })
    table.insert(items, {
        text = tr("Custom presets"),
        sub_item_table_func = function() return PresetsSettings.customPresetItems(ctx) end,
    })
    table.insert(items, {
        text = tr("Import / export presets"),
        sub_item_table_func = function() return PresetsSettings.presetFileItems(ctx) end,
    })
    return items
end

return PresetsSettings
