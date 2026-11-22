-- SPDX-FileCopyrightText: Copyright (C) 2026 THE-XSX
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- Typefolio (文笺) - KOReader plugin
-- Released under the GNU Affero General Public License v3.0 or later.
-- See the LICENSE file in the project root for the full license text.

-- typefolio.koplugin/main.lua
-- 文笺 / Type Folio: underline and typesetting tweaks for CRE books, applied
-- through KOReader's official Style tweaks mechanism (a generated
-- styletweaks/99_typefolio.css enabled per book via doc_settings).
local item_path = debug.getinfo(1, "S").source:sub(2)
local PLUGIN_ROOT = item_path:match("(.*[/\\]typefolio%.koplugin[/\\])") or item_path:match("(.*[/\\])") or "plugins/typefolio.koplugin/"

local ModuleLoader = dofile(PLUGIN_ROOT .. "core/module_loader.lua")
local CSSTemplates = ModuleLoader.load(PLUGIN_ROOT, "css/css_templates.lua")
local BookContext = ModuleLoader.load(PLUGIN_ROOT, "core/book_context.lua")
local SemanticIndex = ModuleLoader.load(PLUGIN_ROOT, "tools/semantic_index.lua")
local HealthCheck = ModuleLoader.load(PLUGIN_ROOT, "tools/health_check.lua")
local SelectorHelper = ModuleLoader.load(PLUGIN_ROOT, "tools/selector_helper.lua")
local EpubDialogueTagger = ModuleLoader.load(PLUGIN_ROOT, "tools/epub_dialogue_tagger.lua")
local Painter = ModuleLoader.load(PLUGIN_ROOT, "painters/painter.lua")
local ContextPainter = ModuleLoader.load(PLUGIN_ROOT, "painters/context_painter.lua")
local HeaderPainter = ModuleLoader.load(PLUGIN_ROOT, "painters/header_painter.lua")
local FooterPainter = ModuleLoader.load(PLUGIN_ROOT, "painters/footer_painter.lua")
local Config = ModuleLoader.load(PLUGIN_ROOT, "core/config.lua")
local PerfCounter = ModuleLoader.load(PLUGIN_ROOT, "core/perf_counter.lua")
local RenderPlanner = ModuleLoader.load(PLUGIN_ROOT, "core/render_planner.lua")
local Engine = ModuleLoader.load(PLUGIN_ROOT, "core/engine.lua")
local FolioScene = ModuleLoader.load(PLUGIN_ROOT, "core/folio_scene.lua")
local MenuPreview = ModuleLoader.load(PLUGIN_ROOT, "core/menu_preview.lua")
local KOReaderSettings = ModuleLoader.load(PLUGIN_ROOT, "core/koreader_settings.lua")
local PresetCodec = ModuleLoader.load(PLUGIN_ROOT, "css/preset_codec.lua")
local Settings = ModuleLoader.load(PLUGIN_ROOT, "settings/init.lua")
local TweakMenus = ModuleLoader.load(PLUGIN_ROOT, "settings/tweak_menus.lua")
local I18n = ModuleLoader.load(PLUGIN_ROOT, "i18n/i18n.lua")
local tr = I18n.new(PLUGIN_ROOT, { language_setting = "typefolio_language" })

local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local time = require("ui/time")
local util = require("util")
local Screen = Device.screen
local T = require("ffi/util").template
local io = require("io")

local CONFIG_KEY = "typefolio_config"
local TWEAK_ID = "99_typefolio.css"
local CUSTOM_PRESETS_KEY = "typefolio_custom_presets"
local DEFAULT_NEW_BOOK_PRESET_KEY = "typefolio_default_new_book_preset"
local LEGACY_EXPERIMENT_BACKUP_KEY = "typefolio_experiment_backup"
local PLUGIN_VERSION = (dofile(PLUGIN_ROOT .. "_meta.lua") or {}).version or "0.0.0"
local PRESET_FOLDER_NAME = "typefolio_presets"
local PERF_ENABLED_KEY = "typefolio_performance_counters"
local PERF_REPORT_FILENAME = "typefolio-performance.log"
local PREVIEW_ON_CHANGE_KEY = "typefolio_preview_on_change"

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

local function previewOnChangeEnabled()
    return G_reader_settings:readSetting(PREVIEW_ON_CHANGE_KEY) ~= false
end

local function setPreviewOnChangeEnabled(enabled)
    G_reader_settings:saveSetting(PREVIEW_ON_CHANGE_KEY, enabled and true or false)
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

local function getDefaultNewBookPreset()
    local name = G_reader_settings:readSetting(DEFAULT_NEW_BOOK_PRESET_KEY)
    if type(name) ~= "string" or name == "" then return nil end
    local presets = getCustomPresets()
    if presets[name] == nil then return nil end
    return name
end

local function setDefaultNewBookPreset(name)
    if type(name) == "string" and name ~= "" then
        G_reader_settings:saveSetting(DEFAULT_NEW_BOOK_PRESET_KEY, name)
    else
        G_reader_settings:delSetting(DEFAULT_NEW_BOOK_PRESET_KEY)
    end
end

local function saveCustomPreset(name, config, ui)
    local presets = getCustomPresets()
    local full_config = Config.clone(config)
    if ui and ui.doc_settings
            and (type(full_config.koreader_settings) ~= "table"
                or next(full_config.koreader_settings) == nil) then
        full_config.koreader_settings = KOReaderSettings.capture(ui)
    end
    presets[name] = full_config
    G_reader_settings:saveSetting(CUSTOM_PRESETS_KEY, presets)
end

local function deleteCustomPreset(name)
    local presets = getCustomPresets()
    presets[name] = nil
    G_reader_settings:saveSetting(CUSTOM_PRESETS_KEY, presets)
    if G_reader_settings:readSetting(DEFAULT_NEW_BOOK_PRESET_KEY) == name then
        G_reader_settings:delSetting(DEFAULT_NEW_BOOK_PRESET_KEY)
    end
end

local function renameCustomPreset(old_name, new_name)
    local presets = getCustomPresets()
    if not presets[old_name] or new_name == "" or presets[new_name] then return false end
    presets[new_name] = presets[old_name]
    presets[old_name] = nil
    G_reader_settings:saveSetting(CUSTOM_PRESETS_KEY, presets)
    if G_reader_settings:readSetting(DEFAULT_NEW_BOOK_PRESET_KEY) == old_name then
        G_reader_settings:saveSetting(DEFAULT_NEW_BOOK_PRESET_KEY, new_name)
    end
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
        if persist then
            KOReaderSettings.restore(self.ui, config.koreader_settings)
        end
        config = Config.clone(config)
        config.koreader_settings = {}
    end
    local result
    if self.perf_counter then
        result = self.perf_counter:measure("phase.engine.apply", function()
            return self.engine:apply(config, { persist = persist })
        end)
    else
        result = self.engine:apply(config, { persist = persist })
    end
    self._cached_config = result.config
    if self.header_painter then self.header_painter:setConfig(result.config) end
    if self.footer_painter then self.footer_painter:setConfig(result.config) end
    local header_on = result.config and result.config.custom_header
        and result.config.custom_header.enabled == true
    local footer_on = result.config and result.config.custom_footer
        and result.config.custom_footer.enabled == true
    local disable_system_bars = result.config and result.config.disable_system_bars == true
    KOReaderSettings.applyDisableSystemBars(self.ui, disable_system_bars)
    KOReaderSettings.syncNativeHeaderBar(self.ui, header_on, disable_system_bars)
    KOReaderSettings.syncNativeFooterBar(self.ui, footer_on, nil, disable_system_bars)
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
        full_config.koreader_settings = KOReaderSettings.capture(ui)
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

local function folioSceneLabel(value)
    return tr(Config.FOLIO_SCENE_LABELS[value] or Config.FOLIO_SCENE_LABELS.off)
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

function TypeFolio:_getReadonlyConfig(ui)
    local target_ui = ui or self.ui
    if target_ui == self.ui and self._cached_config ~= nil then
        return self._cached_config
    end
    local cfg = getConfig(target_ui)
    if target_ui == self.ui then
        self._cached_config = cfg
    end
    return cfg
end

function TypeFolio:_initEngine()
    if self.engine then return end
    self.engine = Engine.new({
        config = Config,
        planner = RenderPlanner,
        get_policy = getRenderPolicy,
        painter_available = function() return self.painter ~= nil end,
        get_capabilities = function()
            return {
                has_dialogue_class = self.book_context
                    and self.book_context:hasDialogueClassMarkup() or false,
            }
        end,
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
        apply_painter = function(enabled, config, plan)
            if self.perf_counter then self.perf_counter:mark("config.apply_painter") end
            if self.painter then
                self.painter.enabled = enabled
                self.painter:setConfig(config)
            end
            if self.context_painter then self.context_painter:setConfig(config, plan) end
            if self.header_painter then self.header_painter:setConfig(config) end
            if self.footer_painter then self.footer_painter:setConfig(config) end
            if self.book_context then self.book_context:invalidate("config_apply") end
        end,
        refresh = function()
            if self.perf_counter then self.perf_counter:mark("paint.refresh_requested") end
            UIManager:setDirty(self.ui.view and self.ui.view.dialog, "partial")
        end,
    })
end

function TypeFolio:init()
    self.perf_counter = PerfCounter.new{
        enabled = G_reader_settings:readSetting(PERF_ENABLED_KEY) == true,
        clock = function() return time.to_ms(time.monotonic()) end,
    }
    self.perf_counter:mark("event.plugin_init")
    self:_initEngine()
    self:_initMenuPreview()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function TypeFolio:_initMenuPreview()
    if self.menu_preview then return end
    self.menu_preview = MenuPreview.new{
        ui_manager = UIManager,
        is_enabled = previewOnChangeEnabled,
        schedule = function(action) UIManager:nextTick(action) end,
        make_trap = function(dismiss_callback)
            local ok, TrapWidget = pcall(require, "ui/widget/trapwidget")
            if not ok or type(TrapWidget) ~= "table" then return nil end
            return TrapWidget:new{ dismiss_callback = dismiss_callback }
        end,
        mark = function(name)
            if self.perf_counter then self.perf_counter:mark(name) end
        end,
    }
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
    if self.perf_counter then self.perf_counter:mark("event.reader_ready") end
    self._cached_config = nil
    self.book_context = BookContext.new{
        ui = self.ui,
        screen_size = function() return Screen:getWidth(), Screen:getHeight() end,
        perf = self.perf_counter,
    }
    self.semantic_index = SemanticIndex.new{
        context = self.book_context,
        perf = self.perf_counter,
    }
    self.painter = Painter:new{
        context = self.book_context,
        perf = self.perf_counter,
    }
    self.context_painter = ContextPainter:new{
        context = self.book_context,
        semantic_index = self.semantic_index,
        perf = self.perf_counter,
    }
    self.header_painter = HeaderPainter:new{
        context = self.book_context,
        perf = self.perf_counter,
        tr = tr,
    }
    self.footer_painter = FooterPainter:new{
        context = self.book_context,
        perf = self.perf_counter,
        tr = tr,
    }
    self.view:registerViewModule("typefolio_painter", self.painter)
    self.view:registerViewModule("typefolio_context_painter", self.context_painter)
    self.view:registerViewModule("typefolio_header_painter", self.header_painter)
    self.view:registerViewModule("typefolio_footer_painter", self.footer_painter)

    local backup = self.ui.doc_settings:readSetting(LEGACY_EXPERIMENT_BACKUP_KEY)
    if type(backup) == "table" then
        self.ui.doc_settings:saveSetting(CONFIG_KEY, Config.normalize(backup))
        self.ui.doc_settings:delSetting(LEGACY_EXPERIMENT_BACKUP_KEY)
    end

    local saved_book_config = self.ui.doc_settings:readSetting(CONFIG_KEY)
    if saved_book_config == nil then
        local default_preset_name = getDefaultNewBookPreset()
        local default_preset = default_preset_name and getCustomPresets()[default_preset_name]
        if type(default_preset) == "table" then
            applyStyle(self, Config.clone(default_preset), { persist = true })
            return
        end
    end
    applyStyle(self, getConfig(self.ui), { skip_persist = true })
end

function TypeFolio:_invalidatePainter(reason)
    reason = reason or "unknown"
    if self.perf_counter then self.perf_counter:mark("event." .. reason) end
    if self.book_context then self.book_context:invalidate(reason) end
    if self.semantic_index then self.semantic_index:invalidate(reason) end
    if self.header_painter then self.header_painter:invalidate(reason) end
    if self.footer_painter then self.footer_painter:invalidate(reason) end
end

function TypeFolio:onPageUpdate() self:_invalidatePainter("page_update") end
function TypeFolio:onPosUpdate() self:_invalidatePainter("pos_update") end
function TypeFolio:onDocumentRerendered() self:_invalidatePainter("document_rerendered") end
function TypeFolio:onDocumentPartiallyRerendered() self:_invalidatePainter("document_partially_rerendered") end
function TypeFolio:onChangeViewMode() self:_invalidatePainter("change_view_mode") end
function TypeFolio:onSetPageMargins() self:_invalidatePainter("set_page_margins") end
function TypeFolio:onSetStatusLine() self:_invalidatePainter("set_status_line") end

function TypeFolio:onRecreateFooter()
    local config = getConfig(self.ui)
    if config and config.disable_system_bars == true then
        KOReaderSettings.applyDisableSystemBars(self.ui, true)
        KOReaderSettings.syncNativeFooterBar(self.ui, config.custom_footer and config.custom_footer.enabled == true, nil, true)
    end
end

function TypeFolio:onCloseDocument()
    if self.menu_preview then self.menu_preview:cancel() end
    self._cached_config = nil
end

function TypeFolio:_canGenerateDialogueCopy()
    local doc_file = self.ui and self.ui.document and self.ui.document.file
    if type(doc_file) ~= "string" or doc_file == "" then return false end
    if EpubDialogueTagger.isTaggedCopy(doc_file) then
        local original = self.ui and self.ui.doc_settings and self.ui.doc_settings:readSetting("typefolio_source_file")
        return type(original) == "string" and original ~= "" and lfs.attributes(original) ~= nil
    end
    return doc_file:lower():match("%.epub$") ~= nil
end

function TypeFolio:_generateDialogueTaggedCopy(touchmenu_instance)
    if not self:_canGenerateDialogueCopy() then
        showInfo(tr("Dialogue-tagged copies are only supported for standard EPUB books."))
        return
    end
    local src_path = self.ui.document.file
    if EpubDialogueTagger.isTaggedCopy(src_path) and self.ui and self.ui.doc_settings then
        local original = self.ui.doc_settings:readSetting("typefolio_source_file")
        if type(original) == "string" and original ~= "" and lfs.attributes(original) then
            src_path = original
        end
    end
    local data_dir = DataStorage:getDataDir()
    local cache_dir = EpubDialogueTagger.cacheDir(data_dir)
    util.makePath(cache_dir)
    local config = getConfig(self.ui)
    local lang = config.dialogue_painter and config.dialogue_painter.lang or "all"
    local include_quotes = not (config.tweak_params and config.tweak_params.dialogue_style
        and config.tweak_params.dialogue_style.include_quotes == false)
    local attr = lfs.attributes(src_path)
    local dest_path = EpubDialogueTagger.buildCachePath(src_path, data_dir, {
        lang = lang,
        include_quotes = include_quotes,
        size = attr and attr.size or 0,
        mtime = attr and attr.modification or 0,
    })
    if not dest_path then
        showInfo(tr("Failed to compute cache path for this book."))
        return
    end

    local working_msg = InfoMessage:new{
        text = tr("Generating dialogue-tagged EPUB copy…"),
    }
    UIManager:show(working_msg)
    UIManager:forceRePaint()

    local out_path, stats_or_err = EpubDialogueTagger.processEpub(src_path, dest_path, {
        lang = lang,
        include_quotes = include_quotes,
    })
    UIManager:close(working_msg)

    if not out_path then
        showInfo(T(tr("Failed to generate dialogue-tagged copy: %1"), tostring(stats_or_err or "unknown")))
        return
    end
    local stats = type(stats_or_err) == "table" and stats_or_err or {}

    -- Copy Type Folio config (with CSS dialogue styling enabled) and reading position
    -- hint into the cached copy's doc_settings so the reader picks up seamlessly.
    pcall(function()
        local DocSettings = require("docsettings")
        local dest_settings = DocSettings:open(out_path)
        if dest_settings then
            local next_cfg = Config.clone(config)
            next_cfg.tweaks.dialogue_style = true
            next_cfg.koreader_settings = {}
            dest_settings:saveSetting(CONFIG_KEY, next_cfg)
            local tweaks = dest_settings:readSetting("style_tweaks") or {}
            tweaks[TWEAK_ID] = true
            dest_settings:saveSetting("style_tweaks", tweaks)
            dest_settings:saveSetting("typefolio_source_file", src_path)
            if self.ui and self.ui.doc_settings then
                local percent = self.ui.doc_settings:readSetting("percent_finished")
                if percent ~= nil then
                    dest_settings:saveSetting("percent_finished", percent)
                end
                local font_face = self.ui.doc_settings:readSetting("font_face")
                if font_face ~= nil then
                    dest_settings:saveSetting("font_face", font_face)
                end
            end
            dest_settings:flush()
        end
    end)

    notify(T(tr("Tagged %1 dialogue runs across %2 chapters. Opening copy…"),
        tostring(stats.quotes_tagged or 0), tostring(stats.files_modified or 0)))

    if touchmenu_instance and touchmenu_instance.close_callback then
        pcall(touchmenu_instance.close_callback)
    end
    local ok_reader, ReaderUI = pcall(require, "apps/reader/readerui")
    if ok_reader and ReaderUI and type(ReaderUI.showReader) == "function" then
        UIManager:nextTick(function()
            ReaderUI:showReader(out_path)
        end)
    else
        showInfo(T(tr("Dialogue-tagged copy saved to: %1"), out_path))
    end
end

function TypeFolio:_getDialogueCacheSummary()
    local _, total_bytes, count = EpubDialogueTagger.listCachedCopies(DataStorage:getDataDir())
    return {
        count = count or 0,
        total_bytes = total_bytes or 0,
    }
end

function TypeFolio:_clearDialogueCache()
    local removed, freed = EpubDialogueTagger.clearCache(DataStorage:getDataDir())
    notify(T(tr("Cleared %1 cached copy/copies (%2 MB)"),
        tostring(removed or 0), string.format("%.1f", (freed or 0) / (1024 * 1024))))
end

function TypeFolio:_setPerformanceCountersEnabled(enabled)
    enabled = enabled == true
    G_reader_settings:saveSetting(PERF_ENABLED_KEY, enabled)
    if not self.perf_counter then return end
    if enabled then
        self.perf_counter:setEnabled(true)
        self.perf_counter:reset()
        self.perf_counter:mark("event.counters_enabled")
    else
        self.perf_counter:mark("event.counters_disabled")
        self.perf_counter:setEnabled(false)
    end
end

function TypeFolio:_resetPerformanceCounters()
    if not self.perf_counter then return end
    self.perf_counter:reset()
    self.perf_counter:mark("event.counters_reset")
end

function TypeFolio:_performanceReport()
    local config = self:_getReadonlyConfig(self.ui)
    local chapter = config.awareness and config.awareness.chapter or {}
    local chapter_start = chapter.start and chapter.start.enabled == true
    local chapter_end = chapter["end"] and chapter["end"].enabled == true
    local configurable = self.ui and self.ui.document and self.ui.document.configurable or {}
    local report_path = DataStorage:getDataDir() .. "/" .. PERF_REPORT_FILENAME
    local lines = {
        "Type Folio performance report",
        "format_version=1",
        "generated_at=" .. os.date("%Y-%m-%d %H:%M:%S"),
        "typefolio_version=" .. PLUGIN_VERSION,
        "report_path=" .. report_path,
        string.format("screen=%dx%d", Screen:getWidth(), Screen:getHeight()),
        "view_mode=" .. tostring(configurable.view_mode or "unknown"),
        "visible_pages=" .. tostring(configurable.visible_pages or "unknown"),
        "render_policy=" .. tostring(getRenderPolicy()),
        "underline=" .. tostring(config.underline),
        "dash_pattern=" .. tostring(config.dash_pattern),
        "skip_headings=" .. tostring(config.skip_headings ~= false),
        "skip_blockquotes=" .. tostring(config.skip_blockquotes ~= false),
        "semantic_drawing=" .. tostring(config.semantic_drawing.enabled == true),
        "semantic_diagnostics=" .. tostring(config.semantic_drawing.diagnostics == true),
        "dialogue_painter=" .. tostring(config.dialogue_painter.enabled == true),
        "dialogue_backend=" .. tostring(self.last_apply and self.last_apply.plan and self.last_apply.plan.dialogue_backend or "unknown"),
        "dialogue_mode=" .. tostring(config.dialogue_painter.mode),
        "dialogue_lang=" .. tostring(config.dialogue_painter.lang),
        "emphasis_painter=" .. tostring(config.emphasis_painter.enabled == true),
        "chapter_start=" .. tostring(chapter_start),
        "chapter_end=" .. tostring(chapter_end),
        "",
        self.perf_counter and self.perf_counter:format() or "counter_unavailable=true",
    }
    return table.concat(lines, "\n"), report_path
end

function TypeFolio:_logPerformanceReport(report)
    for line in (report .. "\n"):gmatch("(.-)\n") do
        logger.info("[TYPEFOLIO-PERF]", line)
    end
end

function TypeFolio:_getPerformanceReport()
    if self.perf_counter then self.perf_counter:mark("event.report_generated") end
    local report, path = self:_performanceReport()
    local file, err = io.open(path, "w")
    if file then
        file:write(report)
        file:write("\n")
        file:close()
    end
    self:_logPerformanceReport(report)
    return report, file and path or nil, err
end

function TypeFolio:_buildContext()
    local ctx
    ctx = {
        ui = self.ui,
        tr = tr,
        T = T,
        Screen = Screen,
        Device = Device,
        Config = Config,
        RENDER_POLICY_KEY = RENDER_POLICY_KEY,
        getRenderPolicy = getRenderPolicy,
        getConfig = function(ui) return getConfig(ui) end,
        getReadonlyConfig = function(ui) return self:_getReadonlyConfig(ui) end,
        applyStyle = function(config, opts)
            local result = applyStyle(self, config, opts)
            if self.menu_preview and not (opts and opts.preview == false) then
                self.menu_preview:requestAfterChange()
            end
            return result
        end,
        previewOnChangeEnabled = previewOnChangeEnabled,
        setPreviewOnChangeEnabled = setPreviewOnChangeEnabled,
        notify = notify,
        showInfo = showInfo,
        getCustomPresets = getCustomPresets,
        saveCustomPreset = function(name, config, ui) return saveCustomPreset(name, config, ui or self.ui) end,
        deleteCustomPreset = deleteCustomPreset,
        renameCustomPreset = renameCustomPreset,
        getDefaultNewBookPreset = getDefaultNewBookPreset,
        setDefaultNewBookPreset = setDefaultNewBookPreset,
        listPresetFiles = listPresetFiles,
        getPresetFolder = getPresetFolder,
        writePresetFile = function(name, config, ui) return writePresetFile(name, config, ui or self.ui) end,
        readPresetFile = readPresetFile,
        deletePresetFile = deletePresetFile,
        uniquePresetName = uniquePresetName,
        tweakItems = function(options) return TweakMenus.tweakItems(ctx, options) end,
        hasDialogueClassMarkup = function()
            return self.book_context and self.book_context:hasDialogueClassMarkup() or false
        end,
        isDialoguePainterSuppressedByCss = function()
            return self.last_apply and self.last_apply.plan
                and self.last_apply.plan.dialogue_suppressed_by_css == true or false
        end,
        canGenerateDialogueCopy = function() return self:_canGenerateDialogueCopy() end,
        generateDialogueTaggedCopy = function(touchmenu_instance)
            return self:_generateDialogueTaggedCopy(touchmenu_instance)
        end,
        getDialogueCacheSummary = function() return self:_getDialogueCacheSummary() end,
        clearDialogueCache = function() return self:_clearDialogueCache() end,
        getSemanticIndex = function() return self.semantic_index end,
        getLastSelectorSnippet = function() return self.last_selector_snippet end,
        setLastSelectorSnippet = function(val) self.last_selector_snippet = val end,
        folioSceneLabel = function(val) return folioSceneLabel(val) end,
        enabledEffects = function(config) return enabledEffects(config) end,
        performanceCountersEnabled = function()
            return self.perf_counter and self.perf_counter:isEnabled() or false
        end,
        setPerformanceCountersEnabled = function(enabled)
            self:_setPerformanceCountersEnabled(enabled)
        end,
        resetPerformanceCounters = function()
            self:_resetPerformanceCounters()
        end,
        getPerformanceReport = function()
            return self:_getPerformanceReport()
        end,
        getPerformanceCounter = function()
            return self.perf_counter
        end,
    }
    return ctx
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
