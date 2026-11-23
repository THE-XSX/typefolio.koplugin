-- SPDX-FileCopyrightText: Copyright (C) 2026 THE-XSX
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- Typefolio (文笺) - KOReader plugin
-- Released under the GNU Affero General Public License v3.0 or later.
-- See the LICENSE file in the project root for the full license text.

local Config = {
    SCHEMA_VERSION = 8,
}

local function toSet(list)
    local set = {}
    for _, v in ipairs(list) do
        set[v] = true
    end
    return set
end

-- Status bar (custom header / custom footer) vocabularies.
-- SINGLE SOURCE OF TRUTH. Config.normalize, css/preset_codec.lua,
-- settings/custom_header.lua, settings/custom_footer.lua and
-- painters/status_bar_helper.lua all derive from these lists; never re-list an id
-- anywhere else. Order is menu order. tests/status_bar_spec.lua pins the parity, so a
-- new id added here fails the suite until the painter and both menus know it too.
Config.STATUS_SLOTS = {
    "none", "chapter_title", "book_title", "author", "clock", "clock_12h", "battery",
    "time_battery", "battery_time", "reading_percent", "page_progress", "page_progress_cn",
    "progress_combo", "progress_combo_cn", "pages_left_chapter", "time_left_chapter",
    "time_left_book", "time_left_book_pages", "book_title_page_progress_cn", "custom_text",
}
Config.STATUS_PRESETS = {
    "minimal", "modern", "classic", "reading",
    "wechat_duokan", "classic_folio", "kobo_split", "ireader", "hanvon", "boox",
    "wechat_reading", "minimal_pages", "modern_full", "custom",
}
Config.STATUS_DIVIDERS = {
    "none", "solid", "dashed", "dots_small", "progress_bar", "custom",
}
-- One font-size range for both bars, shared with the importer and the spin widgets.
Config.STATUS_FONT_MIN = 8
Config.STATUS_FONT_MAX = 28
-- Divider thickness is in unscaled units (paintBar runs it through Screen:scaleBySize),
-- so 3 is already a heavy rule on a 300 DPI screen. The spin row and the importer read
-- this instead of writing a literal; a spin row that went one higher than normalize
-- accepted is exactly how "pick the thickest divider, get the thinnest" happened.
Config.STATUS_DIVIDER_THICKNESS_MAX = 3

-- The other two numeric bounds the status bar menus offer: distance from the screen edge
-- to the text, and from the text to the divider. Same reason they live here -- normalize()
-- resets an out-of-range value to the default, so a spin row whose max exceeds the bound
-- silently discards the reader's choice.
Config.STATUS_OFFSET_MAX = 60
Config.STATUS_PADDING_MAX = 30

-- How far a dialogue mark may keep off the top and bottom of the line box, in unscaled
-- units (the painter runs it through Screen:scaleBySize like every other px setting here).
-- 8 is past useful on any sane line height -- the painter also clamps to 40% of the actual
-- box, so a large value on a short line cannot collapse the mark -- but the spin row has to
-- stop somewhere, and it has to stop where normalize() stops or the reader's pick is
-- silently discarded. That is the divider-thickness bug; see the note above it.
Config.DIALOGUE_INSET_MAX = 8

-- Emphasis dots (着重号) unscaled geometry bounds, shared by normalize(), preset_codec
-- and the emphasis submenu spin widgets.
Config.EMPHASIS_SIZE_MIN = 1
Config.EMPHASIS_SIZE_MAX = 6
Config.EMPHASIS_GAP_MIN = 4
Config.EMPHASIS_GAP_MAX = 32

-- Chapter boundary decoration vocabularies and numeric bounds.
Config.CHAPTER_STYLES = { "single", "double", "dots", "custom" }
Config.CHAPTER_STYLE_ALIASES = { wave = "single", heart = "dots" }
Config.CHAPTER_THICKNESS_MAX = 5
Config.CHAPTER_COUNT_MAX = 20

-- Folio scenes vocabulary (SSOT for config.lua, folio_scene.lua, preset_codec.lua,
-- main.lua, and settings/folio_scenes.lua).
Config.FOLIO_SCENES = {
    "off", "auto", "quiet", "study", "editorial", "chapter",
    "swiss", "terminal", "quote", "ticket", "cover", "gallery",
    "dossier", "archive", "bookpost", "architecture", "zen",
    "mei", "lan", "zhu", "ju", "custom", "random",
}
Config.FOLIO_SCENE_SET = toSet(Config.FOLIO_SCENES)
Config.FOLIO_SCENE_LABELS = {
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

-- Slot and divider ids that older versions persisted. normalize() translates these
-- before validating, so a config saved by an earlier build keeps the layout the reader
-- chose instead of being reset to the defaults -- and an exported preset from that build
-- still imports. painters/status_bar_helper.lua reads these tables rather than keeping
-- its own copy.
Config.STATUS_SLOT_ALIASES = {
    chapter = "chapter_title",
    clock_battery = "time_battery",
    progress_percent = "reading_percent",
    pages_left_in_chapter = "pages_left_chapter",
}
Config.STATUS_DIVIDER_ALIASES = {
    dots_big = "dots_small",
    vertical_bar = "dashed",
    bars = "dashed",
    slash = "dashed",
    slashes = "dashed",
    double_slash = "dashed",
    double_slashes = "dashed",
}

-- Legacy underline ids -> canonical { underline, dash_pattern }. Shared with
-- painters/painter.lua and css/css_templates.lua so aliases never drift.
Config.UNDERLINE_ALIASES = {
    all_lines_dashed_compat = { underline = "all_lines", dash_pattern = "normal" },
    all_lines_dashed = { underline = "all_lines", dash_pattern = "normal" },
    all_lines_solid = { underline = "all_lines", dash_pattern = "solid" },
    all_lines_dotted = { underline = "all_lines", dash_pattern = "dense" },
    thick_lines = { underline = "all_lines", dash_pattern = "thick" },
    para_dashed = { underline = "para", dash_pattern = "normal" },
    para_dotted = { underline = "para", dash_pattern = "dense" },
}

-- Prebuilt O(1) lookup sets so Config.normalize() allocates zero temporary tables
-- per validation check.
local STATUS_SLOT_SET = toSet(Config.STATUS_SLOTS)
local STATUS_PRESET_SET = toSet(Config.STATUS_PRESETS)
local STATUS_DIVIDER_SET = toSet(Config.STATUS_DIVIDERS)
local DIVIDER_POSITION_SET = toSet({ "auto", "above", "below" })
local DIALOGUE_MODE_SET = toSet({ "tint", "underline", "side_bar" })
local DIALOGUE_LANG_SET = toSet({ "cn", "en", "all" })
local DIALOGUE_FONT_COLOR_SET = toSet({ "default", "black", "dark", "medium", "light" })
local TINT_LEVEL_SET = toSet({ "light", "medium", "strong" })
local CHAPTER_STYLE_SET = toSet(Config.CHAPTER_STYLES)

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
    vertical_inset = 0,
}

local EMPHASIS_PAINTER_DEFAULTS = {
    enabled = false,
    size = 2,
    gap = 12,
}

local CUSTOM_HEADER_DEFAULTS = {
    enabled = false,
    preset = "modern",
    left = "chapter_title",
    center = "none",
    right = "time_battery",
    custom_text = "",
    font_size = 13,
    font_bold = false,
    divider_style = "solid",
    divider_position = "auto",
    divider_thickness = 1,
    divider_custom_char = "✦",
    top_offset = 12,
    padding_bottom = 6,
    hide_on_chapter_start = false,
    -- Only read when divider_style == "progress_bar"; kept here so the header and the
    -- footer accept the same keys (normalize() drops anything not defaulted).
    chapter_ticks = true,
    facing_pages = false,
    margin_inset = true,
    -- font_italic is accepted and persisted for older saved settings, but nothing
    -- renders it: KOReader's TextWidget has no italic field, so the painter cannot
    -- honour it. Do not add a menu row for it.
    font_italic = false,
}

local CUSTOM_FOOTER_DEFAULTS = {
    enabled = false,
    preset = "wechat_duokan",
    left = "time_left_chapter",
    center = "none",
    right = "reading_percent",
    custom_text = "",
    font_size = 12,
    font_bold = false,
    divider_style = "none",
    divider_position = "auto",
    divider_thickness = 1,
    divider_custom_char = "✦",
    bottom_offset = 12,
    padding_top = 6,
    hide_on_chapter_start = false,
    chapter_ticks = true,
    facing_pages = false,
    margin_inset = true,
    -- See the note in CUSTOM_HEADER_DEFAULTS: persisted, never rendered.
    font_italic = false,
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

local function booleanOr(value, default)
    if type(value) == "boolean" then return value end
    return default
end

local function thicknessOr(value, default)
    return type(value) == "number" and value % 1 == 0 and value >= 1 and value <= 3
        and value or default
end

local function boundaryThicknessOr(value, default)
    return type(value) == "number" and value % 1 == 0
        and value >= 1 and value <= Config.CHAPTER_THICKNESS_MAX
        and value or default
end

local function clampedIntOr(value, min_val, max_val, default)
    if type(value) ~= "number" or value ~= value or value % 1 ~= 0 then return default end
    if value < min_val then return min_val end
    if value > max_val then return max_val end
    return value
end

-- A status bar divider thickness above the range is clamped, not reset: a reader who
-- picked the thickest rule from a build whose spin row went one too far should get the
-- thickest one that exists, not the thinnest.
local function dividerThicknessOr(value, default)
    if type(value) ~= "number" or value % 1 ~= 0 or value < 1 then return default end
    return math.min(value, Config.STATUS_DIVIDER_THICKNESS_MAX)
end

-- Legacy id -> current id, for a value that is about to be validated against one of the
-- Config.STATUS_* vocabularies. An unknown value is returned untouched so the caller's
-- own lookup check still decides.
local function canonical(value, aliases)
    if type(value) ~= "string" then return value end
    return aliases[value] or value
end

-- Sanitizes a user/imported font-family name before it ever reaches CSS.
-- Rejects any payload containing control characters or CSS delimiter/injection characters.
function Config.sanitizeFontFamily(value)
    if type(value) ~= "string" then return "" end
    local trimmed = value:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == "" or #trimmed > 120 then return "" end
    if trimmed:find("[%c;{}\"'\\:<>]") then return "" end
    return trimmed
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
        custom_header = clone(CUSTOM_HEADER_DEFAULTS),
        custom_footer = clone(CUSTOM_FOOTER_DEFAULTS),
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
    -- Removed global body typography overrides (redundant with KOReader's native contrast/weight).
    config.tweaks.body_bold = nil
    config.tweaks.body_italic = nil
    config.tweaks.pure_black = nil
    config.tweak_params.body_bold = nil
    config.tweak_params.body_italic = nil
    config.tweak_params.pure_black = nil
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
    local dlg_params = config.tweak_params.dialogue_style
    if type(dlg_params) == "table" then
        if dlg_params.font_family ~= nil then
            dlg_params.font_family = Config.sanitizeFontFamily(dlg_params.font_family)
        end
        if dlg_params.font_color ~= nil and not DIALOGUE_FONT_COLOR_SET[dlg_params.font_color] then
            dlg_params.font_color = "default"
        end
    end
    if config.skip_headings == nil then config.skip_headings = true end
    if config.skip_blockquotes == nil then config.skip_blockquotes = true end
    config.folio_scene = Config.FOLIO_SCENE_SET[config.folio_scene] and config.folio_scene or "off"

    local semantic_source = type(config.semantic_drawing) == "table"
        and config.semantic_drawing or {}
    config.semantic_drawing = {}
    for key, default in pairs(SEMANTIC_DEFAULTS) do
        local val = semantic_source[key]
        config.semantic_drawing[key] = val == nil and default or val
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
        local val = dp_source[key]
        config.dialogue_painter[key] = val == nil and default or val
    end
    local dp = config.dialogue_painter
    dp.enabled = false
    dp.mode = DIALOGUE_MODE_SET[dp.mode] and dp.mode or "tint"
    dp.lang = DIALOGUE_LANG_SET[dp.lang] and dp.lang or "all"
    dp.thickness = thicknessOr(dp.thickness, 1)
    dp.tint_level = TINT_LEVEL_SET[dp.tint_level] and dp.tint_level or "light"
    -- Clamped rather than reset, for the reason spelled out at dividerThicknessOr: a value
    -- saved by a build whose spin row went higher should give the largest inset that exists,
    -- not snap back to zero and look like the setting was ignored.
    dp.vertical_inset = (type(dp.vertical_inset) == "number" and dp.vertical_inset % 1 == 0
        and dp.vertical_inset >= 0)
        and math.min(dp.vertical_inset, Config.DIALOGUE_INSET_MAX) or 0

    local ep_source = type(config.emphasis_painter) == "table"
        and config.emphasis_painter or {}
    config.emphasis_painter = {}
    for key, default in pairs(EMPHASIS_PAINTER_DEFAULTS) do
        local val = ep_source[key]
        config.emphasis_painter[key] = val == nil and default or val
    end
    local ep = config.emphasis_painter
    ep.enabled = booleanOr(ep.enabled, false)
    ep.size = clampedIntOr(ep.size, Config.EMPHASIS_SIZE_MIN, Config.EMPHASIS_SIZE_MAX, 2)
    ep.gap = clampedIntOr(ep.gap, Config.EMPHASIS_GAP_MIN, Config.EMPHASIS_GAP_MAX, 12)

    config.awareness = type(config.awareness) == "table" and config.awareness or {}
    local chapter_source = type(config.awareness.chapter) == "table"
        and config.awareness.chapter or {}
    local has_boundary_config = type(chapter_source.start) == "table"
        or type(chapter_source["end"]) == "table"
    local function normalizeBoundary(source, enabled_default)
        source = type(source) == "table" and source or {}
        local style = canonical(source.style, Config.CHAPTER_STYLE_ALIASES)
        return {
            enabled = booleanOr(source.enabled, enabled_default),
            style = CHAPTER_STYLE_SET[style] and style or "single",
            thickness = boundaryThicknessOr(source.thickness, 1),
            char = type(source.char) == "string" and source.char ~= ""
                and source.char or nil,
            count = type(source.count) == "number" and source.count % 1 == 0
                and source.count >= 1 and source.count <= Config.CHAPTER_COUNT_MAX
                and source.count or nil,
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

    -- Custom reading header normalization
    local header_source = type(config.custom_header) == "table"
        and config.custom_header or {}
    config.custom_header = {}
    for key, default in pairs(CUSTOM_HEADER_DEFAULTS) do
        local val = header_source[key]
        config.custom_header[key] = val == nil and default or val
    end
    local ch = config.custom_header
    ch.enabled = booleanOr(ch.enabled, false)
    ch.preset = STATUS_PRESET_SET[ch.preset] and ch.preset or "modern"
    ch.left = canonical(ch.left, Config.STATUS_SLOT_ALIASES)
    ch.center = canonical(ch.center, Config.STATUS_SLOT_ALIASES)
    ch.right = canonical(ch.right, Config.STATUS_SLOT_ALIASES)
    ch.left = STATUS_SLOT_SET[ch.left] and ch.left or "chapter_title"
    ch.center = STATUS_SLOT_SET[ch.center] and ch.center or "none"
    ch.right = STATUS_SLOT_SET[ch.right] and ch.right or "time_battery"
    ch.custom_text = type(ch.custom_text) == "string" and ch.custom_text or ""
    ch.font_size = (type(ch.font_size) == "number"
        and ch.font_size >= Config.STATUS_FONT_MIN and ch.font_size <= Config.STATUS_FONT_MAX)
        and ch.font_size or 13
    ch.font_bold = booleanOr(ch.font_bold, false)
    ch.font_italic = booleanOr(ch.font_italic, false)
    ch.divider_style = canonical(ch.divider_style, Config.STATUS_DIVIDER_ALIASES)
    ch.divider_style = STATUS_DIVIDER_SET[ch.divider_style] and ch.divider_style or "solid"
    ch.divider_position = DIVIDER_POSITION_SET[ch.divider_position]
        and ch.divider_position or "auto"
    ch.divider_thickness = dividerThicknessOr(ch.divider_thickness, 1)
    ch.divider_custom_char = type(ch.divider_custom_char) == "string" and ch.divider_custom_char ~= ""
        and ch.divider_custom_char or "✦"
    ch.top_offset = (type(ch.top_offset) == "number" and ch.top_offset >= 0
        and ch.top_offset <= Config.STATUS_OFFSET_MAX)
        and ch.top_offset or 12
    ch.padding_bottom = (type(ch.padding_bottom) == "number" and ch.padding_bottom >= 0
        and ch.padding_bottom <= Config.STATUS_PADDING_MAX)
        and ch.padding_bottom or 6
    ch.hide_on_chapter_start = booleanOr(ch.hide_on_chapter_start, false)
    ch.chapter_ticks = booleanOr(ch.chapter_ticks, true)
    ch.facing_pages = booleanOr(ch.facing_pages, false)
    ch.margin_inset = booleanOr(ch.margin_inset, true)

    -- Custom reading footer normalization
    local footer_source = type(config.custom_footer) == "table"
        and config.custom_footer or {}
    config.custom_footer = {}
    for key, default in pairs(CUSTOM_FOOTER_DEFAULTS) do
        local val = footer_source[key]
        config.custom_footer[key] = val == nil and default or val
    end
    local cf = config.custom_footer
    cf.enabled = booleanOr(cf.enabled, false)
    cf.preset = STATUS_PRESET_SET[cf.preset] and cf.preset or "wechat_duokan"
    cf.left = canonical(cf.left, Config.STATUS_SLOT_ALIASES)
    cf.center = canonical(cf.center, Config.STATUS_SLOT_ALIASES)
    cf.right = canonical(cf.right, Config.STATUS_SLOT_ALIASES)
    cf.left = STATUS_SLOT_SET[cf.left] and cf.left or "time_left_chapter"
    cf.center = STATUS_SLOT_SET[cf.center] and cf.center or "none"
    cf.right = STATUS_SLOT_SET[cf.right] and cf.right or "reading_percent"
    cf.custom_text = type(cf.custom_text) == "string" and cf.custom_text or ""
    cf.font_size = (type(cf.font_size) == "number"
        and cf.font_size >= Config.STATUS_FONT_MIN and cf.font_size <= Config.STATUS_FONT_MAX)
        and cf.font_size or 12
    cf.font_bold = booleanOr(cf.font_bold, false)
    cf.font_italic = booleanOr(cf.font_italic, false)
    cf.divider_style = canonical(cf.divider_style, Config.STATUS_DIVIDER_ALIASES)
    cf.divider_style = STATUS_DIVIDER_SET[cf.divider_style] and cf.divider_style or "none"
    cf.divider_position = DIVIDER_POSITION_SET[cf.divider_position]
        and cf.divider_position or "auto"
    -- Kobo's native footer places its progress track below the centered book/page
    -- label. Apply this to older saved configs too, which predate divider_position.
    if cf.preset == "classic_folio" and cf.divider_style == "progress_bar"
            and cf.divider_position == "auto" then
        cf.divider_position = "below"
    end
    cf.divider_thickness = dividerThicknessOr(cf.divider_thickness, 1)
    cf.divider_custom_char = type(cf.divider_custom_char) == "string" and cf.divider_custom_char ~= ""
        and cf.divider_custom_char or "✦"
    cf.bottom_offset = (type(cf.bottom_offset) == "number" and cf.bottom_offset >= 0
        and cf.bottom_offset <= Config.STATUS_OFFSET_MAX)
        and cf.bottom_offset or 12
    cf.padding_top = (type(cf.padding_top) == "number" and cf.padding_top >= 0
        and cf.padding_top <= Config.STATUS_PADDING_MAX)
        and cf.padding_top or 6
    cf.hide_on_chapter_start = booleanOr(cf.hide_on_chapter_start, false)
    cf.chapter_ticks = booleanOr(cf.chapter_ticks, true)
    cf.facing_pages = booleanOr(cf.facing_pages, false)
    cf.margin_inset = booleanOr(cf.margin_inset, true)

    local alias = Config.UNDERLINE_ALIASES[config.underline]
    if alias then
        config.underline = alias.underline
        config.dash_pattern = alias.dash_pattern
    end
    config.schema_version = Config.SCHEMA_VERSION
    return config
end

return Config
