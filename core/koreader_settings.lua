-- SPDX-FileCopyrightText: Copyright (C) 2026 THE-XSX
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- Typefolio (文笺) - KOReader plugin
-- Released under the GNU Affero General Public License v3.0 or later.
-- See the LICENSE file in the project root for the full license text.

-- core/koreader_settings.lua
-- Capture/restore KOReader per-book crengine & chrome settings for presets, and
-- coordinate KOReader's native top/bottom status bars with Type Folio's custom bars.
local item_path = debug.getinfo(1, "S").source:sub(2)
local PLUGIN_ROOT = item_path:match("(.*[/\\]typefolio%.koplugin[/\\])")
    or item_path:match("(.*[/\\])core[/\\]")
    or item_path:match("(.*[/\\])")
    or "plugins/typefolio.koplugin/"

local ModuleLoader = dofile(PLUGIN_ROOT .. "core/module_loader.lua")
local Config = ModuleLoader.load(PLUGIN_ROOT, "core/config.lua")

local KOReaderSettings = {}

KOReaderSettings.SAVED_NATIVE_FOOTER_MODE_KEY = "typefolio_saved_native_footer_mode"

local CRE_ALL_OPTION_KEYS = {
    "copt_font_size", "copt_font_fine_tune", "copt_font_gamma", "copt_font_base_weight",
    "copt_font_hinting", "copt_font_kerning", "copt_line_spacing",
    "copt_h_page_margins", "copt_t_page_margin", "copt_b_page_margin", "copt_sync_t_b_page_margins",
    "copt_visible_pages", "copt_rotation_mode", "copt_view_mode", "copt_block_rendering_mode", "copt_render_dpi",
    "copt_word_spacing", "copt_word_expansion", "copt_cjk_width_scaling",
    "copt_embedded_css", "copt_embedded_fonts", "copt_smooth_scaling", "copt_nightmode_images", "copt_status_line",
    "font_name", "font_family", "font_face", "style_tweaks",
    "page_overlap", "show_overlap_enable", "page_overlap_style", "header_margins", "show_header",
    -- Footer / Bottom Status Bar
    "footer", "reader_footer_mode", "reader_footer_custom_text", "reader_footer_custom_text_repetitions", "footer_visible",
    -- Header / Top Status Bar / Alt Status Bar
    "cre_header_title", "cre_header_author", "cre_header_clock", "cre_header_auto_refresh",
    "cre_header_page_number", "cre_header_page_count", "cre_header_reading_percent",
    "cre_header_battery", "cre_header_battery_percent", "cre_header_chapter_marks",
    "header", "header_visible", "alt_status_bar", "progress_margin",
}

-- Keys a preset may carry that must never be written into a book's doc_settings:
-- css/css_is_fb2 are restored through ReaderTypeset instead, and copt_css /
-- copt_fb2_css are global defaults ReaderTypeset only reads at open time.
local PRESET_ONLY_KEYS = {
    css = true, css_is_fb2 = true, copt_css = true, copt_fb2_css = true,
}

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

function KOReaderSettings.capture(ui)
    if not ui then return {} end
    local captured = {}

    if ui.doc_settings and type(ui.doc_settings.settings) == "table" then
        for k, v in pairs(ui.doc_settings.settings) do
            if k:sub(1, 5) == "copt_" or k:sub(1, 11) == "cre_header_"
                or k == "font_name" or k == "font_family" or k == "font_face"
                or k == "style_tweaks" or k == "page_overlap" or k == "show_overlap_enable"
                or k == "page_overlap_style" or k == "header_margins" or k == "show_header"
                or k == "footer" or k == "reader_footer_mode"
                or k == "reader_footer_custom_text" or k == "reader_footer_custom_text_repetitions"
                or k == "footer_visible" or k == "header" or k == "header_visible"
                or k == "alt_status_bar" or k == "progress_margin" then
                captured[k] = Config.clone(v)
            end
        end
    end

    local settings = rawget(_G, "G_reader_settings")
    local footer_obj = ui.footer or (ui.view and ui.view.footer)
    for _, key in ipairs(CRE_ALL_OPTION_KEYS) do
        if captured[key] == nil then
            local val = nil
            if key:sub(1, 5) == "copt_" and ui.document and ui.document.configurable then
                val = ui.document.configurable[key:sub(6)]
            end
            if val == nil and ui.doc_settings then
                val = ui.doc_settings:readSetting(key)
            end
            if val == nil and footer_obj then
                if key == "footer" and type(footer_obj.settings) == "table" then
                    val = footer_obj.settings
                elseif key == "reader_footer_mode" and footer_obj.mode ~= nil then
                    val = footer_obj.mode
                elseif key == "reader_footer_custom_text" and footer_obj.custom_text ~= nil then
                    val = footer_obj.custom_text
                elseif key == "reader_footer_custom_text_repetitions" and footer_obj.custom_text_repetitions ~= nil then
                    val = footer_obj.custom_text_repetitions
                end
            end
            if val == nil and settings then
                val = settings:readSetting(key)
            end
            if val ~= nil then
                captured[key] = Config.clone(val)
            end
        end
    end

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

function KOReaderSettings.restore(ui, captured, deps)
    if not (ui and ui.doc_settings and type(captured) == "table" and next(captured) ~= nil) then return end
    deps = deps or {}
    local Event = deps.Event or require("ui/event")
    local UIManager = deps.UIManager or require("ui/uimanager")
    local Notification = deps.Notification or require("ui/widget/notification")
    local settings = deps.reader_settings or rawget(_G, "G_reader_settings")
    local index = deps.cre_option_index or getCreOptionIndex()
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
    -- toasts off the screen. Always unwind silent mode + BatchedUpdateDone even
    -- if a callback or custom KOReader widget throws midway.
    UIManager:broadcastEvent(Event:new("BatchedUpdate"))
    UIManager:setSilentMode(true)
    Notification:setNotifySource(Notification.SOURCE_NONE)

    local ok, err = pcall(function()
        if type(deps.on_inside_batch) == "function" then
            deps.on_inside_batch()
        end

        for _, name in ipairs(creRestoreSequence(index)) do
            replay(name, pending[name])
        end

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

        -- Restore KOReader ReaderFooter (bottom status bar)
        if captured.footer ~= nil or captured.reader_footer_mode ~= nil
                or captured.reader_footer_custom_text ~= nil
                or captured.reader_footer_custom_text_repetitions ~= nil then
            if settings then
                if type(captured.footer) == "table" then
                    settings:saveSetting("footer", Config.clone(captured.footer))
                end
                if captured.reader_footer_mode ~= nil then
                    settings:saveSetting("reader_footer_mode", captured.reader_footer_mode)
                end
                if captured.reader_footer_custom_text ~= nil then
                    settings:saveSetting("reader_footer_custom_text", captured.reader_footer_custom_text)
                end
                if captured.reader_footer_custom_text_repetitions ~= nil then
                    settings:saveSetting("reader_footer_custom_text_repetitions", captured.reader_footer_custom_text_repetitions)
                end
            end

            local footer_obj = ui.footer or (ui.view and ui.view.footer)
            if footer_obj then
                if footer_obj.loadPreset then
                    pcall(function()
                        footer_obj:loadPreset({
                            footer = Config.clone(captured.footer or footer_obj.settings),
                            reader_footer_mode = captured.reader_footer_mode or footer_obj.mode,
                            reader_footer_custom_text = captured.reader_footer_custom_text or footer_obj.custom_text,
                            reader_footer_custom_text_repetitions = captured.reader_footer_custom_text_repetitions or footer_obj.custom_text_repetitions,
                        })
                    end)
                else
                    if type(captured.footer) == "table" and settings then
                        footer_obj.settings = settings:readSetting("footer")
                    end
                    if captured.reader_footer_custom_text ~= nil then
                        footer_obj.custom_text = captured.reader_footer_custom_text
                    end
                    if captured.reader_footer_custom_text_repetitions ~= nil then
                        footer_obj.custom_text_repetitions = tonumber(captured.reader_footer_custom_text_repetitions)
                    end
                    pcall(function() if footer_obj.set_mode_index then footer_obj:set_mode_index() end end)
                    pcall(function() if footer_obj.set_has_no_mode then footer_obj:set_has_no_mode() end end)
                    pcall(function() if footer_obj.applyFooterMode and captured.reader_footer_mode ~= nil then footer_obj:applyFooterMode(captured.reader_footer_mode) end end)
                    pcall(function() if footer_obj.updateFooterTextGenerator then footer_obj:updateFooterTextGenerator() end end)
                    pcall(function() if footer_obj.updateFooterFont then footer_obj:updateFooterFont() end end)
                    pcall(function() if footer_obj.setTocMarkers then footer_obj:setTocMarkers() end end)
                    pcall(function() if footer_obj.refreshFooter then footer_obj:refreshFooter(true, true) end end)
                end
            end
            pcall(function() ui:handleEvent(Event:new("RecreateFooter")) end)
            pcall(function() ui:handleEvent(Event:new("UpdateFooter", true, true)) end)
            pcall(function() ui:handleEvent(Event:new("UpdateStatusbar")) end)
        end

        if captured.footer_visible ~= nil then
            pcall(function() ui:handleEvent(Event:new("ToggleFooter", captured.footer_visible)) end)
        end

        -- Restore KOReader Crengine Header / Top Status Line / Alt Status Bar
        local has_cre_header = false
        local cre_header_keys = {
            "cre_header_title", "cre_header_author", "cre_header_clock", "cre_header_auto_refresh",
            "cre_header_page_number", "cre_header_page_count", "cre_header_reading_percent",
            "cre_header_battery", "cre_header_battery_percent", "cre_header_chapter_marks",
        }
        for _, k in ipairs(cre_header_keys) do
            if captured[k] ~= nil then
                has_cre_header = true
                if settings then settings:saveSetting(k, captured[k]) end
            end
        end

        if has_cre_header and ui.document and ui.document._document then
            pcall(function()
                if captured.cre_header_title ~= nil then
                    ui.document._document:setIntProperty("window.status.title", captured.cre_header_title)
                end
                if captured.cre_header_author ~= nil then
                    ui.document._document:setIntProperty("window.status.author", captured.cre_header_author)
                end
                if captured.cre_header_clock ~= nil then
                    ui.document._document:setIntProperty("window.status.clock", captured.cre_header_clock)
                end
                if captured.cre_header_page_number ~= nil then
                    ui.document._document:setIntProperty("window.status.pos.page.number", captured.cre_header_page_number)
                end
                if captured.cre_header_page_count ~= nil then
                    ui.document._document:setIntProperty("window.status.pos.page.count", captured.cre_header_page_count)
                end
                if captured.cre_header_chapter_marks ~= nil then
                    ui.document._document:setIntProperty("crengine.page.header.chapter.marks", captured.cre_header_chapter_marks)
                end
                if captured.cre_header_battery ~= nil then
                    ui.document._document:setIntProperty("window.status.battery", captured.cre_header_battery)
                end
                if captured.cre_header_battery_percent ~= nil then
                    ui.document._document:setIntProperty("window.status.battery.percent", captured.cre_header_battery_percent)
                end
                if captured.cre_header_reading_percent ~= nil then
                    ui.document._document:setIntProperty("window.status.pos.percent", captured.cre_header_reading_percent)
                end
            end)
        end

        if has_cre_header then
            if ui.coptlistener then
                pcall(function()
                    if ui.coptlistener.onTimeFormatChanged then ui.coptlistener:onTimeFormatChanged() end
                    if ui.coptlistener.updateHeader then ui.coptlistener:updateHeader() end
                end)
            end
            pcall(function() ui:handleEvent(Event:new("UpdateHeader")) end)
            pcall(function() ui:handleEvent(Event:new("RecreateHeader")) end)
        end

        if captured.alt_status_bar ~= nil then
            if settings then settings:saveSetting("alt_status_bar", captured.alt_status_bar) end
            pcall(function() ui:handleEvent(Event:new("SetAltStatusbar", captured.alt_status_bar)) end)
        end

        if captured.header ~= nil or captured.header_visible ~= nil then
            pcall(function() ui:handleEvent(Event:new("SetHeader", captured.header)) end)
            pcall(function() ui:handleEvent(Event:new("RecreateHeader")) end)
            pcall(function() ui:handleEvent(Event:new("UpdateHeader")) end)
        end
    end)

    pcall(function() Notification:resetNotifySource() end)
    pcall(function() UIManager:setSilentMode(false) end)
    pcall(function() UIManager:broadcastEvent(Event:new("BatchedUpdateDone")) end)

    if not ok and deps.rethrow then
        error(err, 0)
    end
    return ok, err
end

-- Hide KOReader's native crengine top status line (0 = on, 1 = off) when the custom
-- header is active so the two bars never collide.
function KOReaderSettings.syncNativeHeaderBar(ui, custom_header_enabled)
    if custom_header_enabled ~= true then return end
    if not (ui and ui.document and ui.document.configurable) then return end
    if ui.document.configurable.status_line == 0 then
        ui.document.configurable.status_line = 1
        if ui.doc_settings then
            pcall(function() ui.doc_settings:saveSetting("copt_status_line", 1) end)
        end
        pcall(function()
            local Event = require("ui/event")
            ui:handleEvent(Event:new("ConfigChange", "status_line", 1))
            ui:handleEvent(Event:new("SetStatusLine", 1))
        end)
    end
end

-- Coordinate KOReader's native bottom footer symmetrically with the custom footer:
-- when custom footer turns on, remember the active native footer mode and hide it;
-- when custom footer turns off, restore the remembered mode once.
function KOReaderSettings.syncNativeFooterBar(ui, custom_footer_enabled, settings_override)
    local footer = ui and ui.view and ui.view.footer
    if not (footer and footer.mode_list and footer.applyFooterMode) then return end
    local settings = settings_override or rawget(_G, "G_reader_settings")
    local off = footer.mode_list.off or 0
    local key = KOReaderSettings.SAVED_NATIVE_FOOTER_MODE_KEY

    if custom_footer_enabled == true then
        local is_active = ui.view.footer_visible == true
            or (type(footer.mode) == "number" and footer.mode ~= off)
        if is_active then
            local current_mode = footer.mode
            if type(current_mode) ~= "number" or current_mode == off then
                current_mode = settings and settings:readSetting("reader_footer_mode")
            end
            if settings and type(current_mode) == "number" and current_mode ~= off then
                pcall(function() settings:saveSetting(key, current_mode) end)
            end
            pcall(function() footer:applyFooterMode(off) end)
            if settings then
                pcall(function() settings:saveSetting("reader_footer_mode", off) end)
            end
            if footer.refreshFooter then
                pcall(function() footer:refreshFooter(true, true) end)
            end
        end
    else
        if settings then
            local saved = settings:readSetting(key)
            if type(saved) == "number" and saved ~= off then
                pcall(function() settings:delSetting(key) end)
                pcall(function() footer:applyFooterMode(saved) end)
                pcall(function() settings:saveSetting("reader_footer_mode", saved) end)
                if footer.refreshFooter then
                    pcall(function() footer:refreshFooter(true, true) end)
                end
            end
        end
    end
end

return KOReaderSettings
