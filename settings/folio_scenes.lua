-- settings/folio_scenes.lua
local item_path = debug.getinfo(1, "S").source:sub(2)
local PLUGIN_ROOT = item_path:match("(.*[/\\]typefolio%.koplugin[/\\])") or item_path:match("(.*[/\\])settings[/\\]") or item_path:match("(.*[/\\])") or "plugins/typefolio.koplugin/"
local FolioScene = dofile(PLUGIN_ROOT .. "core/folio_scene.lua")

local FolioScenesSettings = {}

local FOLIO_SCENE_LABELS = {
    off = "Off",
    auto = "Follow typesetting automatically",
    quiet = "Quiet reading",
    study = "Study notes",
    editorial = "Editorial",
    chapter = "Chapter focus",
}

function FolioScenesSettings.label(ctx, value)
    local tr = ctx.tr
    return tr(FOLIO_SCENE_LABELS[value] or FOLIO_SCENE_LABELS.off)
end

function FolioScenesSettings.menuLabel(ctx)
    local tr = ctx.tr
    local T = ctx.T
    local getConfig = ctx.getConfig
    local ui = ctx.ui

    local config = getConfig(ui)
    local label = FolioScenesSettings.label(ctx, config.folio_scene)
    if config.folio_scene == "auto" then
        label = label .. " · " .. FolioScenesSettings.label(ctx, FolioScene.snapshot(config).scene)
    end
    return T(tr("Folio Scenes: %1"), label)
end

function FolioScenesSettings.items(ctx)
    local getConfig = ctx.getConfig
    local applyStyle = ctx.applyStyle
    local ui = ctx.ui

    local items = {}
    for _, mode in ipairs({ "off", "auto", "quiet", "study", "editorial", "chapter" }) do
        local scene_mode = mode
        table.insert(items, {
            text = FolioScenesSettings.label(ctx, scene_mode),
            radio = true,
            keep_menu_open = true,
            checked_func = function() return getConfig(ui).folio_scene == scene_mode end,
            callback = function(touchmenu_instance)
                local config = getConfig(ui)
                config.folio_scene = scene_mode
                applyStyle(config)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        })
    end
    return items
end

return FolioScenesSettings
