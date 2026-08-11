local item_path = debug.getinfo(1, "S").source:sub(2)
local PLUGIN_ROOT = item_path:match("(.*[/\\]typefolio%.koplugin[/\\])") or item_path:match("(.*[/\\])") or "plugins/typefolio.koplugin/"
local SETTINGS_ROOT = PLUGIN_ROOT .. "settings/"
local HelpSettings = dofile(SETTINGS_ROOT .. "help.lua")
local TextMarksSettings = dofile(SETTINGS_ROOT .. "text_marks.lua")
local ChapterSettings = dofile(SETTINGS_ROOT .. "chapters.lua")
local TextStylingSettings = dofile(SETTINGS_ROOT .. "text_styling.lua")
local TypesettingToolsSettings = dofile(SETTINGS_ROOT .. "typesetting_tools.lua")
local FolioScenesSettings = dofile(SETTINGS_ROOT .. "folio_scenes.lua")
local PresetsSettings = dofile(SETTINGS_ROOT .. "presets.lua")

local Settings = {
    Help = HelpSettings,
    TextMarks = TextMarksSettings,
    Chapters = ChapterSettings,
    TextStyling = TextStylingSettings,
    TypesettingTools = TypesettingToolsSettings,
    FolioScenes = FolioScenesSettings,
    Presets = PresetsSettings,
}

function Settings.menuItems(ctx)
    local tr = ctx.tr
    local items = {}

    table.insert(items, {
        text = tr("Help / user guide"),
        sub_item_table_func = function() return HelpSettings.subItems(ctx) end,
        separator = true,
    })
    table.insert(items, {
        text = tr("Chapters"),
        sub_item_table_func = function() return ChapterSettings.items(ctx) end,
        separator = true,
    })
    table.insert(items, {
        text = tr("Text styling"),
        sub_item_table_func = function() return TextStylingSettings.items(ctx) end,
        separator = true,
    })
    table.insert(items, {
        text = tr("Typesetting tools"),
        sub_item_table_func = function() return TypesettingToolsSettings.items(ctx) end,
        separator = true,
    })
    table.insert(items, {
        text_func = function() return FolioScenesSettings.menuLabel(ctx) end,
        sub_item_table_func = function() return FolioScenesSettings.items(ctx) end,
        separator = true,
    })
    table.insert(items, {
        text = tr("Presets"),
        sub_item_table_func = function() return PresetsSettings.items(ctx) end,
    })

    return items
end

return Settings
