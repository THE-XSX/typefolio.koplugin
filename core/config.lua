local Config = {
    SCHEMA_VERSION = 8,
}

local FOLIO_SCENES = {
    off = true, auto = true, quiet = true, study = true,
    editorial = true, chapter = true,
}

local AWARENESS_DEFAULTS = {
    chapter = {
        start = { enabled = false, style = "single", thickness = 1 },
        ["end"] = { enabled = false, style = "single", thickness = 1 },
    },
}

local SEMANTIC_DEFAULTS = {
    enabled = false,
    headings = true,
    blockquotes = true,
    scene_breaks = true,
    diagnostics = false,
    thickness = 1,
}

local DIALOGUE_PAINTER_DEFAULTS = {
    enabled = false,
    mode = "tint",
    lang = "all",
    thickness = 1,
    tint_level = "light",
}

local EMPHASIS_PAINTER_DEFAULTS = {
    enabled = false,
    size = 2,
    gap = 12,
}

local UNDERLINE_ALIASES = {
    all_lines_dashed_compat = { underline = "all_lines", dash_pattern = "normal" },
    all_lines_dashed = { underline = "all_lines", dash_pattern = "normal" },
    all_lines_solid = { underline = "all_lines", dash_pattern = "solid" },
    all_lines_dotted = { underline = "all_lines", dash_pattern = "dense" },
    thick_lines = { underline = "all_lines", dash_pattern = "thick" },
    para_dashed = { underline = "para", dash_pattern = "normal" },
    para_dotted = { underline = "para", dash_pattern = "dense" },
}

local function clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        copy[clone(key, seen)] = clone(child, seen)
    end
    return copy
end

local function oneOf(value, allowed)
    for _, candidate in ipairs(allowed) do
        if value == candidate then return true end
    end
    return false
end

local function booleanOr(value, default)
    if type(value) == "boolean" then return value end
    return default
end

local function thicknessOr(value, default)
    return type(value) == "number" and value % 1 == 0 and value >= 1 and value <= 3
        and value or default
end

local function boundaryThicknessOr(value, default)
    return type(value) == "number" and value % 1 == 0 and value >= 1 and value <= 5
        and value or default
end

function Config.defaults()
    return {
        schema_version = Config.SCHEMA_VERSION,
        underline = "none",
        line_thickness = "1.5px",
        dash_pattern = "normal",
        tweaks = {},
        tweak_params = {},
        skip_headings = true,
        skip_blockquotes = true,
        folio_scene = "off",
        awareness = clone(AWARENESS_DEFAULTS),
        semantic_drawing = clone(SEMANTIC_DEFAULTS),
        dialogue_painter = clone(DIALOGUE_PAINTER_DEFAULTS),
        emphasis_painter = clone(EMPHASIS_PAINTER_DEFAULTS),
        koreader_settings = {},
    }
end

function Config.clone(value)
    return clone(value)
end

function Config.normalize(value)
    local config = type(value) == "table" and clone(value) or Config.defaults()
    config.koreader_settings = type(config.koreader_settings) == "table"
        and clone(config.koreader_settings) or {}
    config.underline = type(config.underline) == "string" and config.underline or "none"
    config.line_thickness = type(config.line_thickness) == "string"
        and config.line_thickness or "1.5px"
    config.dash_pattern = type(config.dash_pattern) == "string"
        and config.dash_pattern or "normal"
    config.tweaks = type(config.tweaks) == "table" and config.tweaks or {}
    config.tweak_params = type(config.tweak_params) == "table" and config.tweak_params or {}
    config.tweaks.custom_hr_dashed = nil
    config.tweak_params.custom_hr_dashed = nil
    -- Renamed blockquote params: the menu once wrote bar_thickness/bg_tint while
    -- the CSS template reads bar/tint. Migrate any saved values so older
    -- settings keep working, then drop the dead keys.
    local bq_params = config.tweak_params.blockquote_box
    if type(bq_params) == "table" then
        if bq_params.bar == nil and bq_params.bar_thickness ~= nil then
            bq_params.bar = bq_params.bar_thickness
        end
        bq_params.bar_thickness = nil
        if bq_params.tint == nil and bq_params.bg_tint ~= nil then
            bq_params.tint = bq_params.bg_tint
        end
        bq_params.bg_tint = nil
    end
    if config.skip_headings == nil then config.skip_headings = true end
    if config.skip_blockquotes == nil then config.skip_blockquotes = true end
    config.folio_scene = FOLIO_SCENES[config.folio_scene] and config.folio_scene or "off"
    local semantic_source = type(config.semantic_drawing) == "table"
        and config.semantic_drawing or {}
    config.semantic_drawing = {}
    for key, default in pairs(SEMANTIC_DEFAULTS) do
        local value = semantic_source[key]
        config.semantic_drawing[key] = value == nil and default or value
    end
    local semantic = config.semantic_drawing
    semantic.enabled = booleanOr(semantic.enabled, false)
    semantic.headings = booleanOr(semantic.headings, true)
    semantic.blockquotes = booleanOr(semantic.blockquotes, true)
    semantic.scene_breaks = booleanOr(semantic.scene_breaks, true)
    semantic.diagnostics = booleanOr(semantic.diagnostics, false)
    semantic.thickness = thicknessOr(semantic.thickness, 1)

    local dp_source = type(config.dialogue_painter) == "table"
        and config.dialogue_painter or {}
    config.dialogue_painter = {}
    for key, default in pairs(DIALOGUE_PAINTER_DEFAULTS) do
        local value = dp_source[key]
        config.dialogue_painter[key] = value == nil and default or value
    end
    local dp = config.dialogue_painter
    dp.enabled = booleanOr(dp.enabled, false)
    dp.mode = oneOf(dp.mode, { "tint", "underline", "side_bar" }) and dp.mode or "tint"
    dp.lang = oneOf(dp.lang, { "cn", "en", "all" }) and dp.lang or "all"
    dp.thickness = thicknessOr(dp.thickness, 1)
    dp.tint_level = oneOf(dp.tint_level, { "light", "medium", "strong" })
        and dp.tint_level or "light"

    local ep_source = type(config.emphasis_painter) == "table"
        and config.emphasis_painter or {}
    config.emphasis_painter = {}
    for key, default in pairs(EMPHASIS_PAINTER_DEFAULTS) do
        local value = ep_source[key]
        config.emphasis_painter[key] = value == nil and default or value
    end
    local ep = config.emphasis_painter
    ep.enabled = booleanOr(ep.enabled, false)
    ep.size = thicknessOr(ep.size, 2)
    ep.gap = type(ep.gap) == "number" and ep.gap or 12
    config.awareness = type(config.awareness) == "table" and config.awareness or {}
    local chapter_source = type(config.awareness.chapter) == "table"
        and config.awareness.chapter or {}
    local has_boundary_config = type(chapter_source.start) == "table"
        or type(chapter_source["end"]) == "table"
    local function normalizeBoundary(source, enabled_default)
        source = type(source) == "table" and source or {}
        return {
            enabled = booleanOr(source.enabled, enabled_default),
            style = oneOf(source.style, { "single", "double", "wave", "dots", "heart", "custom" })
                and source.style or "single",
            thickness = boundaryThicknessOr(source.thickness, 1),
            char = type(source.char) == "string" and source.char ~= ""
                and source.char or nil,
            count = type(source.count) == "number" and source.count % 1 == 0
                and source.count >= 1 and source.count <= 20 and source.count or nil,
        }
    end
    if has_boundary_config then
        config.awareness.chapter = {
            start = normalizeBoundary(chapter_source.start, false),
            ["end"] = normalizeBoundary(chapter_source["end"], false),
        }
    else
        local legacy_enabled = booleanOr(chapter_source.enabled, false)
        config.awareness.chapter = {
            start = normalizeBoundary({
                enabled = legacy_enabled and booleanOr(chapter_source.show_start, true),
                style = chapter_source.style,
                thickness = chapter_source.thickness,
            }, false),
            ["end"] = normalizeBoundary({
                enabled = legacy_enabled and booleanOr(chapter_source.show_end, true),
                style = chapter_source.style,
                thickness = chapter_source.thickness,
            }, false),
        }
    end
    -- Annotation-aware drawing was removed; discard its legacy per-book settings.
    config.awareness = { chapter = config.awareness.chapter }

    local alias = UNDERLINE_ALIASES[config.underline]
    if alias then
        config.underline = alias.underline
        config.dash_pattern = alias.dash_pattern
    end
    config.schema_version = Config.SCHEMA_VERSION
    return config
end

return Config
