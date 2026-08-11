-- typefolio.koplugin/main.lua
-- 文笺 / Type Folio: underline and typesetting tweaks for CRE books, applied
-- through KOReader's official Style tweaks mechanism (a generated
-- styletweaks/99_typefolio.css enabled per book via doc_settings).
local item_path = debug.getinfo(1, "S").source:sub(2)
local PLUGIN_ROOT = item_path:match("(.*[/\\]typefolio%.koplugin[/\\])") or item_path:match("(.*[/\\])") or "plugins/typefolio.koplugin/"

local CSSTemplates = dofile(PLUGIN_ROOT .. "css/css_templates.lua")
local BookContext = dofile(PLUGIN_ROOT .. "core/book_context.lua")
local SemanticIndex = dofile(PLUGIN_ROOT .. "tools/semantic_index.lua")
local HealthCheck = dofile(PLUGIN_ROOT .. "tools/health_check.lua")
local SelectorHelper = dofile(PLUGIN_ROOT .. "tools/selector_helper.lua")
local Painter = dofile(PLUGIN_ROOT .. "painters/painter.lua")
local ContextPainter = dofile(PLUGIN_ROOT .. "painters/context_painter.lua")
local Config = dofile(PLUGIN_ROOT .. "core/config.lua")
local RenderPlanner = dofile(PLUGIN_ROOT .. "core/render_planner.lua")
local Engine = dofile(PLUGIN_ROOT .. "core/engine.lua")
local FolioScene = dofile(PLUGIN_ROOT .. "core/folio_scene.lua")
local PresetCodec = dofile(PLUGIN_ROOT .. "css/preset_codec.lua")
local Settings = dofile(PLUGIN_ROOT .. "settings/init.lua")
local I18n = dofile(PLUGIN_ROOT .. "i18n/i18n.lua")
local tr = I18n.new(PLUGIN_ROOT, { language_setting = "typefolio_language" })

local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Notification = require("ui/widget/notification")
local SpinWidget = require("ui/widget/spinwidget")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local Screen = Device.screen
local T = require("ffi/util").template
local io = require("io")

local CONFIG_KEY = "typefolio_config"
local TWEAK_ID = "99_typefolio.css"
local CUSTOM_PRESETS_KEY = "typefolio_custom_presets"
local LEGACY_EXPERIMENT_BACKUP_KEY = "typefolio_experiment_backup"
local PLUGIN_VERSION = "3.0.4"
local PRESET_FOLDER_NAME = "typefolio_presets"

local RENDER_POLICY_KEY = "typefolio_render_policy"
local LEGACY_RENDER_MODE_KEY = "typefolio_render_mode"

local function getRenderPolicy()
    local policy = G_reader_settings:readSetting(RENDER_POLICY_KEY)
    if policy == nil then
        local legacy = G_reader_settings:readSetting(LEGACY_RENDER_MODE_KEY)
        policy = legacy == "paint" and "paint" or (legacy == "css" and "css" or "auto")
        G_reader_settings:saveSetting(RENDER_POLICY_KEY, policy)
    end
    return RenderPlanner.normalizePolicy(policy)
end

local function getStyleTweaksFolder()
    return DataStorage:getDataDir() .. "/styletweaks/"
end

local function saveCssToStyleTweaks(css)
    local file = io.open(getStyleTweaksFolder() .. TWEAK_ID, "w")
    if file then
        file:write(css)
        file:close()
    end
end

local function getConfig(ui)
    local config = ui and ui.doc_settings and ui.doc_settings:readSetting(CONFIG_KEY)
    return Config.normalize(config)
end

local function getCustomPresets()
    local t = G_reader_settings:readSetting(CUSTOM_PRESETS_KEY)
    return type(t) == "table" and t or {}
end

local CRE_ALL_OPTION_KEYS = {
    "copt_font_size", "copt_font_fine_tune", "copt_font_gamma", "copt_font_base_weight",
    "copt_font_hinting", "copt_font_kerning", "copt_line_spacing",
    "copt_h_page_margins", "copt_t_page_margin", "copt_b_page_margin", "copt_sync_t_b_page_margins",
    "copt_visible_pages", "copt_rotation_mode", "copt_view_mode", "copt_block_rendering_mode", "copt_render_dpi",
    "copt_word_spacing", "copt_word_expansion", "copt_cjk_width_scaling",
    "copt_embedded_css", "copt_embedded_fonts", "copt_smooth_scaling", "copt_nightmode_images", "copt_status_line",
    "font_name", "font_family", "font_face", "style_tweaks",
    "page_overlap", "show_overlap_enable", "page_overlap_style", "header_margins", "show_header",
}

-- Keys a preset may carry that must never be written into a book's doc_settings:
-- css/css_is_fb2 are restored through ReaderTypeset instead, and copt_css /
-- copt_fb2_css are global defaults ReaderTypeset only reads at open time.
local PRESET_ONLY_KEYS = {
    css = true, css_is_fb2 = true, copt_css = true, copt_fb2_css = true,
}

local function captureKOReaderDocSettings(ui)
    if not ui then return {} end
    local captured = {}

    if ui.doc_settings and type(ui.doc_settings.settings) == "table" then
        for k, v in pairs(ui.doc_settings.settings) do
            if k:sub(1, 5) == "copt_" or k == "font_name" or k == "font_family" or k == "font_face"
                or k == "style_tweaks" or k == "page_overlap" or k == "show_overlap_enable"
                or k == "header_margins" or k == "show_header" then
                captured[k] = Config.clone(v)
            end
        end
    end

    for _, key in ipairs(CRE_ALL_OPTION_KEYS) do
        if captured[key] == nil then
            local val = nil
            if key:sub(1, 5) == "copt_" and ui.document and ui.document.configurable then
                val = ui.document.configurable[key:sub(6)]
            end
            if val == nil and ui.doc_settings then
                val = ui.doc_settings:readSetting(key)
            end
            if val == nil then
                val = G_reader_settings:readSetting(key)
            end
            if val ~= nil then
                captured[key] = Config.clone(val)
            end
        end
    end

    -- The stylesheet that actually reaches the open document is the per-book
    -- "css" key, not copt_css. Record which flavour it belongs to so a preset
    -- taken from an FB2 book never pushes fb2.css onto an EPUB.
    local css = ui.doc_settings and ui.doc_settings:readSetting("css")
    if type(css) ~= "string" or css == "" then
        css = ui.typeset and ui.typeset.css
    end
    if type(css) == "string" and css ~= "" then
        captured.css = css
        captured.css_is_fb2 = (ui.document and ui.document.is_fb2) and true or false
    end

    return captured
end

-- A crengine option only reaches the document through the per-option `event`
-- declared in ui/data/creoptions.lua. ConfigChange just mirrors the value into
-- document.configurable (ReaderCoptListener:onConfigChange) and never calls
-- crengine, which is why a preset used to look applied while nothing moved
-- until the book was reopened. So replay the real events, the same way
-- ConfigDialog and Dispatcher do.
local cre_option_index

-- font_fine_tune is a relative nudge (ChangeSize ±0.5), not an absolute value;
-- replaying it would drift the font size on every apply. The top/bottom margins
-- and their sync toggle are sent together further down.
local CRE_MANUAL_OPTIONS = {
    font_fine_tune = true,
    t_page_margin = true,
    b_page_margin = true,
    sync_t_b_page_margins = true,
}

-- Screen geometry and layout mode first, so the reflows that follow measure the
-- final page box; anything creoptions gains later is appended in name order.
local CRE_RESTORE_ORDER = {
    "rotation_mode", "view_mode", "visible_pages", "status_line",
    "block_rendering_mode", "embedded_css", "embedded_fonts", "render_dpi",
    "font_size", "font_base_weight", "font_hinting", "font_kerning", "font_gamma",
    "line_spacing", "word_spacing", "word_expansion", "cjk_width_scaling",
    "smooth_scaling", "nightmode_images", "h_page_margins",
}

local function getCreOptionIndex()
    if cre_option_index then return cre_option_index end
    local index = {}
    local ok, CreOptions = pcall(require, "ui/data/creoptions")
    if ok and type(CreOptions) == "table" then
        for _, group in ipairs(CreOptions) do
            for _, option in ipairs(type(group) == "table" and group.options or {}) do
                if type(option) == "table" and option.name and option.event then
                    index[option.name] = {
                        event = option.event,
                        values = option.values,
                        args = option.args,
                    }
                end
            end
        end
    end
    cre_option_index = index
    return index
end

local function sameOptionValue(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

-- creoptions saves `values` but feeds `args` to the event, and for several
-- options the two differ: view_mode 0/1 → "page"/"scroll", embedded_css /
-- embedded_fonts / smooth_scaling / nightmode_images 0/1 → false/true. This is
-- the index mapping Dispatcher does, inverted. A fine-tuned value that is not
-- in the list (custom font size or margin) passes through, which is correct
-- because those options declare args identical to values.
local function creEventArg(option, value)
    if type(option.values) ~= "table" or type(option.args) ~= "table" then
        return value
    end
    for i, candidate in ipairs(option.values) do
        if sameOptionValue(candidate, value) then return Config.clone(option.args[i]) end
    end
    return value
end

local function creRestoreSequence(index)
    local order, seen = {}, {}
    for _, name in ipairs(CRE_RESTORE_ORDER) do
        if index[name] then
            seen[name] = true
            table.insert(order, name)
        end
    end
    local rest = {}
    for name in pairs(index) do
        if not seen[name] and not CRE_MANUAL_OPTIONS[name] then
            table.insert(rest, name)
        end
    end
    table.sort(rest)
    for _, name in ipairs(rest) do table.insert(order, name) end
    return order
end

local function restoreKOReaderDocSettings(ui, captured)
    if not (ui and ui.doc_settings and type(captured) == "table" and next(captured) ~= nil) then return end
    local Event = require("ui/event")
    local index = getCreOptionIndex()
    local configurable = ui.document and ui.document.configurable
    local pending = {}

    for key, val in pairs(captured) do
        if not PRESET_ONLY_KEYS[key] then
            ui.doc_settings:saveSetting(key, Config.clone(val))
            if key:sub(1, 5) == "copt_" then
                local name = key:sub(6)
                if configurable then configurable[name] = Config.clone(val) end
                if index[name] then pending[name] = Config.clone(val) end
            end
        end
    end

    local function replay(name, value)
        local option = index[name]
        if not option or value == nil then return end
        pcall(function() ui:handleEvent(Event:new("ConfigChange", name, Config.clone(value))) end)
        pcall(function() ui:handleEvent(Event:new(option.event, creEventArg(option, value))) end)
    end

    -- Collapse ~20 reflows into a single UpdatePos, and keep the per-option
    -- toasts off the screen: on e-ink that is one refresh instead of twenty.
    UIManager:broadcastEvent(Event:new("BatchedUpdate"))
    UIManager:setSilentMode(true)
    Notification:setNotifySource(Notification.SOURCE_NONE)

    for _, name in ipairs(creRestoreSequence(index)) do
        replay(name, pending[name])
    end

    -- One SetPageTopAndBottomMargin rather than SetPageTopMargin plus
    -- SetPageBottomMargin, otherwise ReaderTypeset's Sync T/B handling
    -- overwrites whichever of the two we sent first.
    local t_margin = pending.t_page_margin or (configurable and configurable.t_page_margin)
    local b_margin = pending.b_page_margin or (configurable and configurable.b_page_margin)
    if (pending.t_page_margin or pending.b_page_margin)
        and type(t_margin) == "number" and type(b_margin) == "number" then
        pcall(function() ui:handleEvent(Event:new("ConfigChange", "t_page_margin", t_margin)) end)
        pcall(function() ui:handleEvent(Event:new("ConfigChange", "b_page_margin", b_margin)) end)
        pcall(function()
            ui:handleEvent(Event:new("SetPageTopAndBottomMargin", { t_margin, b_margin }))
        end)
    end
    replay("sync_t_b_page_margins", pending.sync_t_b_page_margins)
    if configurable and pending.sync_t_b_page_margins ~= nil then
        configurable.sync_t_b_page_margins = pending.sync_t_b_page_margins
    end

    local font_face = captured.font_face or captured.font_name or captured.font_family
    if type(font_face) == "string" and font_face ~= "" then
        pcall(function() ui:handleEvent(Event:new("SetFont", font_face)) end)
    end

    if type(captured.style_tweaks) == "table" and ui.styletweak then
        pcall(function()
            ui.styletweak.doc_tweaks = Config.clone(captured.style_tweaks)
            ui.styletweak:updateCssText(true)
        end)
    end

    if type(captured.css) == "string" and ui.typeset and ui.typeset.setStyleSheet
        and captured.css_is_fb2 == ((ui.document and ui.document.is_fb2) and true or false) then
        ui.doc_settings:saveSetting("css", captured.css)
        pcall(function() ui.typeset:setStyleSheet(captured.css) end)
    end

    Notification:resetNotifySource()
    UIManager:setSilentMode(false)
    UIManager:broadcastEvent(Event:new("BatchedUpdateDone"))
end

local function saveCustomPreset(name, config, ui)
    local presets = getCustomPresets()
    local full_config = Config.clone(config)
    -- A config loaded from an exported preset file already carries its own
    -- koreader_settings payload. Only "Save current as new preset" captures the
    -- live book; re-capturing here would silently replace the exported font,
    -- margins and layout with the importing device's current ones.
    if ui and ui.doc_settings
            and (type(full_config.koreader_settings) ~= "table"
                or next(full_config.koreader_settings) == nil) then
        full_config.koreader_settings = captureKOReaderDocSettings(ui)
    end
    presets[name] = full_config
    G_reader_settings:saveSetting(CUSTOM_PRESETS_KEY, presets)
end

local function deleteCustomPreset(name)
    local presets = getCustomPresets()
    presets[name] = nil
    G_reader_settings:saveSetting(CUSTOM_PRESETS_KEY, presets)
end

local function renameCustomPreset(old_name, new_name)
    local presets = getCustomPresets()
    if not presets[old_name] or new_name == "" or presets[new_name] then return false end
    presets[new_name] = presets[old_name]
    presets[old_name] = nil
    G_reader_settings:saveSetting(CUSTOM_PRESETS_KEY, presets)
    return true
end

local function buildUnderlineCss(config)
    if not config or not config.underline or config.underline == "none" then return "" end
    return CSSTemplates.getUnderlineCss(
        config.underline, config.line_thickness, config.dash_pattern,
        config.skip_headings ~= false, config.skip_blockquotes ~= false) or ""
end

local function buildTweakCss(config)
    if not config then return "" end
    local parts = {}
    for key, enabled in pairs(config.tweaks or {}) do
        local template = CSSTemplates.layout_tweaks[key]
        if enabled and template then
            local css = template(config.tweak_params[key])
            if css and css ~= "" then table.insert(parts, css) end
        end
    end
    table.sort(parts)
    return table.concat(parts, "\n\n")
end

local function setTweakEnabled(ui, enabled)
    if not ui then return end

    if ui.styletweak then
        ui.styletweak.doc_tweaks[TWEAK_ID] = enabled
    end

    if ui.doc_settings then
        local tweaks = ui.doc_settings:readSetting("style_tweaks") or {}
        tweaks[TWEAK_ID] = enabled
        ui.doc_settings:saveSetting("style_tweaks", tweaks)
    end
end

local function applyStyle(self, config, opts)
    if not (self.ui and self.ui.doc_settings) then return end
    if not self.engine then self:_initEngine() end
    local persist = not (opts and (opts.skip_persist or opts.persist == false))
    if config and type(config.koreader_settings) == "table" and next(config.koreader_settings) ~= nil then
        -- A preset's KOReader settings are a one-shot payload: applied to the
        -- book, never stored on it. Replaying them on open would undo whatever
        -- the reader has since changed in the bottom menu, so they are dropped
        -- before the config is persisted. On open (skip_persist) there is
        -- nothing to replay -- KOReader has just loaded the book's own settings
        -- -- and any leftover payload from an older release is discarded.
        if persist then
            restoreKOReaderDocSettings(self.ui, config.koreader_settings)
        end
        config = Config.clone(config)
        config.koreader_settings = {}
    end
    local result = self.engine:apply(config, { persist = persist })
    FolioScene.publish(self.ui, result.config, persist)
    self.last_apply = result
    return result
end

local function getPresetFolder()
    return DataStorage:getDataDir() .. "/" .. PRESET_FOLDER_NAME
end

local function safePresetFilename(name)
    local filename = name:gsub("[%c<>:\"/\\|%?%*]", "_"):gsub("%s+", "_")
    filename = filename:gsub("^%.*", ""):gsub("_+", "_")
    if filename == "" then filename = "typefolio_preset" end
    return filename .. ".typefolio.json"
end

local function writePresetFile(name, config, ui)
    local folder = getPresetFolder()
    local ok, err = util.makePath(folder)
    if not ok then return nil, err end
    local full_config = Config.clone(config)
    if ui and ui.doc_settings and (type(full_config.koreader_settings) ~= "table" or next(full_config.koreader_settings) == nil) then
        full_config.koreader_settings = captureKOReaderDocSettings(ui)
    end
    local encoded_ok, text = pcall(PresetCodec.encode, name, full_config, PLUGIN_VERSION)
    if not encoded_ok then return nil, text end
    local path = folder .. "/" .. safePresetFilename(name)
    local file, open_err = io.open(path, "w")
    if not file then return nil, open_err end
    file:write(text)
    file:close()
    return path
end

local function readPresetFile(path)
    local file, err = io.open(path, "r")
    if not file then return nil, err end
    local text = file:read("*a")
    file:close()
    return PresetCodec.decode(text)
end

-- Deleting an exported preset used to need a file manager: the menu only ever
-- offered to import it. Only names listPresetFiles could have produced are
-- accepted -- with no path separator the name cannot escape the preset folder.
local function deletePresetFile(filename)
    if type(filename) ~= "string" or filename:find("[/\\]") then return false, "invalid filename" end
    if not filename:match("%.typefolio%.json$") then return false, "not a preset file" end
    local ok, err = os.remove(getPresetFolder() .. "/" .. filename)
    if not ok then return false, err end
    return true
end

local function listPresetFiles()
    local folder = getPresetFolder()
    util.makePath(folder)
    local files = {}
    local ok, iterator, state = pcall(lfs.dir, folder)
    if not ok or not iterator then return files end
    for filename in iterator, state do
        if filename:match("%.typefolio%.json$") then table.insert(files, filename) end
    end
    table.sort(files)
    return files
end

local function uniquePresetName(name, presets)
    if not presets[name] then return name end
    local index = 2
    while presets[string.format("%s (%d)", name, index)] do index = index + 1 end
    return string.format("%s (%d)", name, index)
end

local EFFECT_LABELS = {
    dialogue_style = "Dialogue highlight",
    blockquote_box = "Blockquote decoration",
    header_border = "Chapter heading decoration",
    chapter_pagebreak = "Chapter page break",
    drop_caps = "Newspaper drop caps",
    pure_black = "Force pure black text",
    body_bold = "Global body bold",
    body_italic = "Global body italic",
}

local FOLIO_SCENE_LABELS = {
    off = "Off",
    auto = "Follow typesetting automatically",
    quiet = "Quiet reading",
    study = "Study notes",
    editorial = "Editorial",
    chapter = "Chapter focus",
}

local function folioSceneLabel(value)
    return tr(FOLIO_SCENE_LABELS[value] or FOLIO_SCENE_LABELS.off)
end

local function enabledEffects(config)
    local effects = {}
    for key, enabled in pairs(config.tweaks or {}) do
        if enabled then table.insert(effects, tr(EFFECT_LABELS[key] or key)) end
    end
    local awareness = config.awareness or {}
    local chapter = awareness.chapter or {}
    if chapter.start and chapter.start.enabled
            or chapter["end"] and chapter["end"].enabled then
        table.insert(effects, tr("Chapter-aware typesetting"))
    end
    if config.semantic_drawing and config.semantic_drawing.enabled then
        table.insert(effects, tr("Semantic drawing"))
    end
    table.sort(effects)
    return #effects > 0 and table.concat(effects, ", ") or tr("None")
end

local function notify(text)
    UIManager:show(Notification:new{ text = text })
end

local function showInfo(text)
    UIManager:show(InfoMessage:new{ text = text })
end

local TypeFolio = WidgetContainer:extend{
    name = "typefolio",
    is_doc_only = true,
}

function TypeFolio:_initEngine()
    if self.engine then return end
    self.engine = Engine.new({
        config = Config,
        planner = RenderPlanner,
        get_policy = getRenderPolicy,
        painter_available = function() return self.painter ~= nil end,
        build_underline_css = buildUnderlineCss,
        build_tweak_css = buildTweakCss,
        persist = function(config)
            self.ui.doc_settings:saveSetting(CONFIG_KEY, config)
        end,
        apply_css = function(css, enabled, changed)
            setTweakEnabled(self.ui, enabled)
            if changed then
                saveCssToStyleTweaks(css)
                if self.ui.styletweak then self.ui.styletweak:updateCssText(true) end
            end
        end,
        apply_painter = function(enabled, config)
            if self.painter then
                self.painter.enabled = enabled
                self.painter:setConfig(config)
            end
            if self.context_painter then self.context_painter:setConfig(config) end
            if self.book_context then self.book_context:invalidate() end
        end,
        refresh = function()
            UIManager:setDirty(self.ui.view and self.ui.view.dialog, "partial")
        end,
    })
end

function TypeFolio:init()
    self:_initEngine()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function TypeFolio:onDispatcherRegisterActions()
    Dispatcher:registerAction("typefolio_show", {
        category = "none",
        event = "ShowTypeFolioMenu",
        title = tr("Type Folio"),
        rolling = true,
    })
end

function TypeFolio:onShowTypeFolioMenu()
    if not (self.ui and self.ui.doc_settings) then return true end

    local TouchMenu = require("ui/widget/touchmenu")

    local tab = self:menuItems()
    tab.icon = "appbar.typeset"
    tab.title = tr("Type Folio")
    tab.remember = false

    local container = CenterContainer:new{
        covers_header = true,
        ignore = "height",
        dimen = Screen:getSize(),
    }
    container[1] = TouchMenu:new{
        width = Screen:getWidth(),
        show_parent = container,
        tab_item_table = { tab },
    }
    UIManager:show(container)
    return true
end

function TypeFolio:onReaderReady()
    if self.ui.paging then return end
    self.book_context = BookContext.new{
        ui = self.ui,
        screen_size = function() return Screen:getWidth(), Screen:getHeight() end,
    }
    self.semantic_index = SemanticIndex.new{ context = self.book_context }
    self.painter = Painter:new{ context = self.book_context }
    self.context_painter = ContextPainter:new{
        context = self.book_context,
        semantic_index = self.semantic_index,
    }
    self.view:registerViewModule("typefolio_painter", self.painter)
    self.view:registerViewModule("typefolio_context_painter", self.context_painter)
    local backup = self.ui.doc_settings:readSetting(LEGACY_EXPERIMENT_BACKUP_KEY)
    if type(backup) == "table" then
        self.ui.doc_settings:saveSetting(CONFIG_KEY, Config.normalize(backup))
        self.ui.doc_settings:delSetting(LEGACY_EXPERIMENT_BACKUP_KEY)
    end
    applyStyle(self, getConfig(self.ui), { skip_persist = true })
end

function TypeFolio:_invalidatePainter()
    if self.book_context then self.book_context:invalidate() end
    if self.semantic_index then self.semantic_index:invalidate() end
end

TypeFolio.onPageUpdate = TypeFolio._invalidatePainter
TypeFolio.onPosUpdate = TypeFolio._invalidatePainter
TypeFolio.onDocumentRerendered = TypeFolio._invalidatePainter
TypeFolio.onDocumentPartiallyRerendered = TypeFolio._invalidatePainter
TypeFolio.onChangeViewMode = TypeFolio._invalidatePainter
TypeFolio.onSetPageMargins = TypeFolio._invalidatePainter
TypeFolio.onSetStatusLine = TypeFolio._invalidatePainter

function TypeFolio:_getParam(tweak_key, name)
    local params = getConfig(self.ui).tweak_params[tweak_key]
    local value = params and params[name]
    if value == nil then
        local defaults = CSSTemplates.tweak_defaults[tweak_key]
        return defaults and defaults[name]
    end
    return value
end

function TypeFolio:_setParam(tweak_key, name, value)
    local config = getConfig(self.ui)
    config.tweak_params[tweak_key] = config.tweak_params[tweak_key] or {}
    config.tweak_params[tweak_key][name] = value
    applyStyle(self, config)
end

function TypeFolio:_paramRadio(tweak_key, name, values, label_of)
    local items = {}
    for _, value in ipairs(values or {}) do
        table.insert(items, {
            text = label_of(value),
            radio = true,
            keep_menu_open = true,
            enabled_func = function() return getConfig(self.ui).tweaks[tweak_key] == true end,
            checked_func = function() return self:_getParam(tweak_key, name) == value end,
            callback = function(touchmenu_instance)
                self:_setParam(tweak_key, name, value)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        })
    end
    return items
end

function TypeFolio:_paramSpin(tweak_key, name, spec)
    return {
        text_func = function()
            local value = self:_getParam(tweak_key, name)
            local shown = spec.precision and string.format(spec.precision, value) or tostring(value)
            return T(tr(spec.label), shown .. (spec.unit or ""))
        end,
        keep_menu_open = true,
        enabled_func = function()
            if getConfig(self.ui).tweaks[tweak_key] ~= true then return false end
            return not spec.extra_enabled or spec.extra_enabled()
        end,
        callback = function(touchmenu_instance)
            UIManager:show(SpinWidget:new{
                title_text = tr(spec.title),
                value = self:_getParam(tweak_key, name),
                value_min = spec.min,
                value_max = spec.max,
                value_step = spec.step or 1,
                value_hold_step = spec.hold_step or (spec.step or 1) * 2,
                precision = spec.precision,
                unit = spec.unit,
                default_value = CSSTemplates.tweak_defaults[tweak_key][name],
                ok_always_enabled = true,
                callback = function(spin)
                    self:_setParam(tweak_key, name, spin.value)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            })
        end,
    }
end

function TypeFolio:_paramToggle(tweak_key, name, label)
    return {
        text = tr(label),
        keep_menu_open = true,
        enabled_func = function() return getConfig(self.ui).tweaks[tweak_key] == true end,
        checked_func = function() return self:_getParam(tweak_key, name) == true end,
        callback = function(touchmenu_instance)
            self:_setParam(tweak_key, name, not self:_getParam(tweak_key, name))
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    }
end

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

function TypeFolio:_tweakEnableItem(tweak_key, title)
    return {
        text_func = function()
            local on = getConfig(self.ui).tweaks[tweak_key] == true
            return T(tr("%1: %2"), tr(title),
                on and tr("Enabled") or tr("Disabled"))
        end,
        keep_menu_open = true,
        checked_func = function() return getConfig(self.ui).tweaks[tweak_key] == true end,
        callback = function(touchmenu_instance)
            local config = getConfig(self.ui)
            config.tweaks[tweak_key] = not config.tweaks[tweak_key]
            applyStyle(self, config)
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
        separator = true,
    }
end

function TypeFolio:_getDialoguePainter(name)
    return getConfig(self.ui).dialogue_painter[name]
end

function TypeFolio:_setDialoguePainter(name, value)
    local config = getConfig(self.ui)
    config.dialogue_painter[name] = value
    applyStyle(self, config)
end

-- One visible "tint intensity" control drives both dialogue paths, so the
-- merged menu behaves like a single feature.
function TypeFolio:_setDialogueTintLevel(value)
    local config = getConfig(self.ui)
    config.tweak_params.dialogue_style = config.tweak_params.dialogue_style or {}
    config.tweak_params.dialogue_style.tint_level = value
    config.dialogue_painter.tint_level = value
    applyStyle(self, config)
end

-- True when either dialogue path is active (CSS class styling or the painter).
function TypeFolio:_dialogueActive()
    local config = getConfig(self.ui)
    return config.tweaks.dialogue_style == true
        or config.dialogue_painter.enabled == true
end

-- Tapping the parent checkbox turns the whole feature off, or on. Enabling both
-- paths at once matters because many converted EPUBs carry no .dialogue class
-- markup at all, so CSS alone would silently do nothing.
function TypeFolio:_toggleDialogue()
    local config = getConfig(self.ui)
    local turn_on = not (config.tweaks.dialogue_style == true
        or config.dialogue_painter.enabled == true)
    config.tweaks.dialogue_style = turn_on
    config.dialogue_painter.enabled = turn_on
    applyStyle(self, config)
end

function TypeFolio:_dialoguePainterItems()
    local O = CSSTemplates.tweak_options
    local painterOn = function() return self:_getDialoguePainter("enabled") == true end

    -- Tint and underline are drawn over the quoted run only; a margin rule has
    -- no per-quote equivalent, so it stays line-level and the labels say so.
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
            checked_func = function() return self:_getDialoguePainter("mode") == value end,
            callback = function(touchmenu_instance)
                self:_setDialoguePainter("mode", value)
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
            checked_func = function() return self:_getDialoguePainter("lang") == value end,
            callback = function(touchmenu_instance)
                self:_setDialoguePainter("lang", value)
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
                return self:_getParam("dialogue_style", "tint_level") == value
            end,
            callback = function(touchmenu_instance)
                self:_setDialogueTintLevel(value)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        })
    end

    return {
        {
            text_func = function()
                return T(tr("%1: %2"), tr("Dynamic quotes (No EPUB edit)"),
                    painterOn() and tr("Enabled") or tr("Disabled"))
            end,
            keep_menu_open = true,
            checked_func = painterOn,
            callback = function(touchmenu_instance)
                self:_setDialoguePainter("enabled", not painterOn())
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
                local config = getConfig(self.ui)
                local css_tint = config.tweaks.dialogue_style == true
                    and self:_getParam("dialogue_style", "tint") == true
                local paint_tint = painterOn()
                    and self:_getDialoguePainter("mode") == "tint"
                return css_tint or paint_tint
            end,
            sub_item_table = tint_items,
        },
    }
end

function TypeFolio:_tweakSubItems(key)
    local O = CSSTemplates.tweak_options
    local lineStyle = function() return self:_paramRadio(key, "line_style", O.line_style,
        function(v) return tr(LINE_STYLE_LABELS[v]) end) end

    if key == "header_border" then
        return {
            self:_tweakEnableItem(key, "Chapter title"),
            { text = tr("Border position"),
              enabled_func = function() return getConfig(self.ui).tweaks[key] == true end,
              sub_item_table = self:_paramRadio(key, "border", O.border,
                  function(v) return tr(BORDER_LABELS[v]) end) },
            { text = tr("Line style"),
              enabled_func = function()
                  return getConfig(self.ui).tweaks[key] == true
                      and self:_getParam(key, "border") ~= "none"
              end,
              sub_item_table = lineStyle() },
            self:_paramSpin(key, "thickness",
                { label = "Line thickness: %1", title = "Header line thickness",
                  min = 1, max = 5, unit = "px",
                  extra_enabled = function() return self:_getParam(key, "border") ~= "none" end }),
            self:_paramToggle(key, "centered", "Center headers"),
            self:_paramToggle(key, "include_centered", "Also style centered paragraphs"),
        }
    elseif key == "blockquote_box" then
        return {
            self:_tweakEnableItem(key, "Blockquote"),
            { text = tr("Left bar thickness"),
              enabled_func = function() return getConfig(self.ui).tweaks[key] == true end,
              sub_item_table = self:_paramSpin(key, "bar",
                  { label = "Line thickness: %1", title = "Left bar thickness",
                    min = 0, max = 10, unit = "px" }) },
            { text = tr("Background tint"),
              enabled_func = function() return getConfig(self.ui).tweaks[key] == true end,
              sub_item_table = self:_paramRadio(key, "tint", O.tint,
                  function(v) return tr(TINT_LABELS[v]) end) },
            self:_paramToggle(key, "italic", "Italic text"),
        }
    elseif key == "dialogue_style" then
        -- Both dialogue paths live here: the CSS path needs .dialogue class
        -- markup in the book, the painter path needs nothing and works directly
        -- on quoted text.
        local items = {}
        for _, item in ipairs(self:_dialoguePainterItems()) do
            table.insert(items, item)
        end
        -- The CSS path owns bold and italic: it runs during layout, so it can
        -- re-render glyphs, which the painter cannot. It needs class markup in
        -- the book, so its enable row and its three attributes are grouped
        -- below the painter rows rather than interleaved with them.
        items[#items].separator = true
        table.insert(items, self:_tweakEnableItem(key, "Styling via class markup"))
        table.insert(items, self:_paramToggle(key, "tint", "Background tint"))
        table.insert(items, self:_paramToggle(key, "bold", "Bold"))
        table.insert(items, self:_paramToggle(key, "italic", "Italic"))
        return items
    elseif key == "chapter_pagebreak" then
        return {
            self:_tweakEnableItem(key, "Chapter page break"),
            self:_paramToggle(key, "include_centered", "Also break on centered paragraphs"),
        }
    elseif key == "drop_caps" then
        return {
            self:_tweakEnableItem(key, "Drop caps"),
            self:_paramSpin(key, "scale",
                { label = "Size: %1", title = "Drop cap size",
                  min = 1.5, max = 3.5, step = 0.1, hold_step = 0.5,
                  precision = "%.1f", unit = "em" }),
            self:_paramToggle(key, "bold", "Bold"),
        }
    end
    return nil
end

function TypeFolio:_tweakItems(options)
    local ui = self.ui
    local items = {}
    for _, option in ipairs(options or {}) do
        local key = option.key
        local sub_items = self:_tweakSubItems(key)
        -- Dialogue owns two independent backends, so its checkbox and checkmark
        -- state cover both instead of just the CSS tweak flag.
        local is_dialogue = key == "dialogue_style"
        local checked = is_dialogue
            and function() return self:_dialogueActive() end
            or function() return getConfig(ui).tweaks[key] == true end
        local toggle = function(touchmenu_instance)
            if is_dialogue then
                self:_toggleDialogue()
            else
                local config = getConfig(ui)
                config.tweaks[key] = not config.tweaks[key]
                applyStyle(self, config)
            end
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end
        table.insert(items, {
            text = tr(option.text),
            keep_menu_open = true,
            checked_func = checked,
            -- With a sub-menu, the checkbox toggles and the row opens the
            -- sub-menu; without one, the whole row toggles.
            checkmark_callback = sub_items and toggle or nil,
            callback = not sub_items and toggle or nil,
            sub_item_table = sub_items,
        })
    end
    return items
end

function TypeFolio:_buildContext()
    return {
        ui = self.ui,
        tr = tr,
        T = T,
        Screen = Screen,
        Config = Config,
        RENDER_POLICY_KEY = RENDER_POLICY_KEY,
        getRenderPolicy = getRenderPolicy,
        getConfig = function(ui) return getConfig(ui) end,
        applyStyle = function(config, opts) return applyStyle(self, config, opts) end,
        notify = notify,
        showInfo = showInfo,
        getCustomPresets = getCustomPresets,
        saveCustomPreset = function(name, config, ui) return saveCustomPreset(name, config, ui or self.ui) end,
        deleteCustomPreset = deleteCustomPreset,
        renameCustomPreset = renameCustomPreset,
        listPresetFiles = listPresetFiles,
        getPresetFolder = getPresetFolder,
        writePresetFile = function(name, config, ui) return writePresetFile(name, config, ui or self.ui) end,
        readPresetFile = readPresetFile,
        deletePresetFile = deletePresetFile,
        uniquePresetName = uniquePresetName,
        tweakItems = function(options) return self:_tweakItems(options) end,
        getSemanticIndex = function() return self.semantic_index end,
        getLastSelectorSnippet = function() return self.last_selector_snippet end,
        setLastSelectorSnippet = function(val) self.last_selector_snippet = val end,
        folioSceneLabel = function(val) return folioSceneLabel(val) end,
        enabledEffects = function(config) return enabledEffects(config) end,
    }
end

function TypeFolio:menuItems()
    return Settings.menuItems(self:_buildContext())
end

function TypeFolio:addToMainMenu(menu_items)
    menu_items.typefolio = {
        sorting_hint = "typeset",
        text = tr("Type Folio"),
        sub_item_table_func = function() return self:menuItems() end,
    }
end

return TypeFolio
