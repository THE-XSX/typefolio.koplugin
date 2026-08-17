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
    swiss = true,
    terminal = true,
    quote = true,
    ticket = true,
    cover = true,
    gallery = true,
    dossier = true,
    archive = true,
    bookpost = true,
    architecture = true,
    zen = true,
    mei = true,
    lan = true,
    zhu = true,
    ju = true,
    custom = true,
    random = true,
}

local SCENE_TO_STYLE = {
    quiet = "zen",
    study = "quote",
    editorial = "bookpost",
    chapter = "architecture",
}

local STYLE_TO_CONTENT_MODE = {
    study = "highlight_progress",
    quote = "highlight_progress",
}

local function automaticScene(config)
    local awareness = config.awareness or {}
    local chapter = awareness.chapter or {}
    local tweaks = config.tweaks or {}
    local semantic = config.semantic_drawing or {}
    local dialogue_painter = config.dialogue_painter or {}

    if tweaks.blockquote_box or tweaks.dialogue_style
            or (dialogue_painter and dialogue_painter.enabled)
            or (semantic and semantic.enabled and semantic.blockquotes) then
        return "study"
    end
    if tweaks.header_border
            or (chapter.start and chapter.start.enabled)
            or (chapter["end"] and chapter["end"].enabled)
            or (semantic and semantic.enabled and semantic.headings) then
        return "chapter"
    end
    if tweaks.drop_caps or (semantic and semantic.enabled and semantic.scene_breaks) then
        return "editorial"
    end
    return "quiet"
end

function FolioScene.normalizeMode(value)
    return MODES[value] and value or "off"
end

function FolioScene.snapshot(config)
    config = type(config) == "table" and config or {}
    local mode = FolioScene.normalizeMode(config.folio_scene)
    local scene = mode == "auto" and automaticScene(config) or mode
    local style_id = SCENE_TO_STYLE[scene] or (scene ~= "off" and scene or nil)
    local content_mode = STYLE_TO_CONTENT_MODE[scene] or STYLE_TO_CONTENT_MODE[style_id] or "reading_folio"
    return {
        format = FolioScene.FORMAT,
        interface_version = FolioScene.INTERFACE_VERSION,
        source = "typefolio",
        enabled = scene ~= "off",
        mode = mode,
        scene = scene,
        style_id = style_id,
        content_mode = content_mode,
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
