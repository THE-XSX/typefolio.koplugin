-- settings/folio_scenes.lua
local item_path = debug.getinfo(1, "S").source:sub(2)
local PLUGIN_ROOT = item_path:match("(.*[/\\]typefolio%.koplugin[/\\])") or item_path:match("(.*[/\\])settings[/\\]") or item_path:match("(.*[/\\])") or "plugins/typefolio.koplugin/"
local FolioScene = dofile(PLUGIN_ROOT .. "core/folio_scene.lua")

local Event = require("ui/event")
local UIManager = require("ui/uimanager")

local FolioScenesSettings = {}

local FOLIO_SCENE_LABELS = {
    off = "Off",
    auto = "Follow typesetting automatically",
    quiet = "Quiet reading",
    study = "Study notes",
    editorial = "Editorial",
    chapter = "Chapter focus",
    swiss = "Swiss grid",
    terminal = "Terminal",
    quote = "Quote poster",
    ticket = "Ticket stub",
    cover = "Cover first",
    gallery = "Gallery folio",
    dossier = "Reading dossier",
    archive = "Library archive",
    bookpost = "Book post",
    architecture = "Reading architecture",
    zen = "Japanese minimal",
    mei = "Plum blossom",
    lan = "Orchid",
    zhu = "Bamboo",
    ju = "Chrysanthemum",
    custom = "Custom layout",
    random = "Random style",
}

local SCENE_MODES = {
    "off",
    "auto",
    "quiet",
    "study",
    "editorial",
    "chapter",
}

local STYLE_MODES = {
    "swiss",
    "dossier",
    "ticket",
    "cover",
    "gallery",
    "archive",
    "terminal",
    "mei",
    "lan",
    "zhu",
    "ju",
    "zen",
    "quote",
    "bookpost",
    "architecture",
    "custom",
    "random",
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
    local tr = ctx.tr

    local items = {}
    for _, scene_mode in ipairs(SCENE_MODES) do
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
                if scene_mode ~= "off" then
                    UIManager:broadcastEvent(Event:new("ShowReadingFolio"))
                end
            end,
        })
    end

    local style_items = {}
    for _, style_mode in ipairs(STYLE_MODES) do
        table.insert(style_items, {
            text = FolioScenesSettings.label(ctx, style_mode),
            radio = true,
            keep_menu_open = true,
            checked_func = function() return getConfig(ui).folio_scene == style_mode end,
            callback = function(touchmenu_instance)
                local config = getConfig(ui)
                config.folio_scene = style_mode
                applyStyle(config)
                if touchmenu_instance then
                    if touchmenu_instance.updateItems then
                        touchmenu_instance:updateItems()
                    end
                end
                UIManager:broadcastEvent(Event:new("ShowReadingFolio"))
            end,
        })
    end

    table.insert(items, {
        text = tr("Select Reading Folio style…"),
        keep_menu_open = true,
        sub_item_table = style_items,
        separator = true,
    })

    return items
end

return FolioScenesSettings
