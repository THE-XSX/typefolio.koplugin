local FolioScene = {
    KEY = "typefolio_folio_scene",
    FORMAT = "folio-scene",
    INTERFACE_VERSION = 1,
}

local MODES = {
    off = true,
    auto = true,
    quiet = true,
    study = true,
    editorial = true,
    chapter = true,
}

local function automaticScene(config)
    local awareness = config.awareness or {}
    local chapter = awareness.chapter or {}
    local tweaks = config.tweaks or {}
    if tweaks.blockquote_box or tweaks.dialogue_style then
        return "study"
    end
    if tweaks.header_border
            or chapter.start and chapter.start.enabled
            or chapter["end"] and chapter["end"].enabled then
        return "chapter"
    end
    if tweaks.drop_caps then return "editorial" end
    return "quiet"
end

function FolioScene.normalizeMode(value)
    return MODES[value] and value or "off"
end

function FolioScene.snapshot(config)
    config = type(config) == "table" and config or {}
    local mode = FolioScene.normalizeMode(config.folio_scene)
    local scene = mode == "auto" and automaticScene(config) or mode
    return {
        format = FolioScene.FORMAT,
        interface_version = FolioScene.INTERFACE_VERSION,
        source = "typefolio",
        enabled = scene ~= "off",
        mode = mode,
        scene = scene,
    }
end

function FolioScene.publish(ui, config, persist)
    if not ui then return nil end
    local snapshot = FolioScene.snapshot(config)
    if persist then
        ui.typefolio_folio_scene_preview = nil
        if ui.doc_settings then ui.doc_settings:saveSetting(FolioScene.KEY, snapshot) end
    else
        ui.typefolio_folio_scene_preview = snapshot
    end
    return snapshot
end

return FolioScene
