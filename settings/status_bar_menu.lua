-- SPDX-FileCopyrightText: Copyright (C) 2026 THE-XSX
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- Typefolio (文笺) - KOReader plugin
-- Released under the GNU Affero General Public License v3.0 or later.
-- See the LICENSE file in the project root for the full license text.

-- settings/status_bar_menu.lua
-- Shared menu vocabulary and rows for the custom header (页眉) and custom footer (页脚).
--
-- Both bars are the same widget with a different anchor, so they must offer the same
-- slots and the same dividers. They used to keep private copies of those lists, and the
-- copies drifted: the header menu had no `progress_bar` divider, neither menu offered
-- the shipped default `modern` preset, presets were iterated with `pairs` (so the order
-- changed between openings), and the footer menu had five presets against the header's
-- eight. Everything here is derived from Config.STATUS_* -- the single source of truth --
-- and tests/status_bar_spec.lua pins the parity, so an id added to core/config.lua fails
-- the suite until it has a label here and a resolver in the painter.
--
-- Labels are looked up by canonical id. Adding an id to Config.STATUS_SLOTS without a
-- label here is a spec failure, not a silent blank menu row.
local item_path = debug.getinfo(1, "S").source:sub(2)
local PLUGIN_ROOT = item_path:match("(.*[/\\]typefolio%.koplugin[/\\])") or item_path:match("(.*[/\\])settings[/\\]") or item_path:match("(.*[/\\])") or "plugins/typefolio.koplugin/"

local Event = require("ui/event")
local InputDialog = require("ui/widget/inputdialog")
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")

local ModuleLoader = dofile(PLUGIN_ROOT .. "core/module_loader.lua")
local Config = ModuleLoader.load(PLUGIN_ROOT, "core/config.lua")

local StatusBarMenu = {}

-- One clone of the shipped defaults, so spin widgets and text_func fallbacks never
-- re-list a default number that core/config.lua already owns.
local DEFAULTS = Config.defaults()

local SLOT_LABELS = {
    none = "None (Empty)",
    chapter_title = "Chapter title",
    book_title = "Book title",
    author = "Author",
    clock = "Current time (24h Clock e.g. 18:22)",
    clock_12h = "Current time (12h e.g. 下午7:55)",
    battery = "Battery icon and percentage",
    time_battery = "Time · Battery icon and percentage",
    battery_time = "Battery icon and percentage · Time",
    reading_percent = "Reading progress percentage (e.g. 1%)",
    page_progress = "Page progress (e.g. 42 / 319)",
    page_progress_cn = "Page progress Chinese (e.g. 28 之 285)",
    progress_combo = "Progress · Page count (e.g. 42% · 45/320)",
    progress_combo_cn = "Progress · Chinese pages (e.g. 42% · 28 之 285)",
    pages_left_chapter = "Pages left in chapter (e.g. 本章还剩 5 页)",
    time_left_chapter = "Time left in chapter (e.g. 本章还剩：9分)",
    time_left_book = "Time left in book (e.g. 预计3时4分后读完)",
    time_left_book_pages = "Time left in book & Pages (e.g. 预计3时4分后读完 42/319)",
    book_title_page_progress_cn = "Book title · Chinese pages (e.g. 浮生六记... · 28 之 285)",
    custom_text = "Custom text",
}

local DIVIDER_LABELS = {
    none = "None (Blank)",
    solid = "Solid line",
    dashed = "Dashed line",
    dots_small = "Small dots (· · ·)",
    progress_bar = "Mini reading progress bar",
    custom = "Custom symbol / pattern",
}

-- Every preset describes BOTH bars. Applying one writes the complete pair, including
-- enabled state, because the top and bottom status bars are one reading chrome.
-- `footer_name` overrides `name` in the footer menu where a bar-specific wording exists;
-- both spellings are already translated, so no new locale keys are needed here.
local PRESETS = {
    minimal = {
        name = "Minimal (Centered chapter · No divider)",
        header = { enabled = true, left = "none", center = "chapter_title", right = "none", divider_style = "none" },
        footer = { enabled = true, left = "none", center = "page_progress_cn", right = "none", divider_style = "none" },
    },
    modern = {
        name = "Modern (Left chapter · Right time/battery)",
        header = { enabled = true, left = "chapter_title", center = "none", right = "time_battery", divider_style = "none" },
        footer = { enabled = true, left = "time_left_chapter", center = "none", right = "reading_percent", divider_style = "none" },
    },
    classic = {
        name = "Classic (Left book · Center chapter · Right pages)",
        header = { enabled = true, left = "book_title", center = "chapter_title", right = "page_progress", divider_style = "none" },
        footer = { enabled = true, left = "none", center = "page_progress_cn", right = "none", divider_style = "progress_bar" },
    },
    reading = {
        name = "Reading (Left chapter · Center progress · Right time)",
        header = { enabled = true, left = "chapter_title", center = "reading_percent", right = "clock", divider_style = "none" },
        footer = { enabled = true, left = "time_left_chapter", center = "none", right = "progress_combo", divider_style = "none" },
    },
    wechat_duokan = {
        name = "Kindle Native (Centered time · Time left · Percent)",
        header = { enabled = true, left = "none", center = "clock", right = "none", divider_style = "none" },
        footer = { enabled = true, left = "time_left_book", center = "none", right = "reading_percent", divider_style = "none" },
    },
    classic_folio = {
        name = "Kobo Native (Centered chapter · Book and page · Progress bar)",
        header = { enabled = true, left = "none", center = "chapter_title", right = "none", divider_style = "none" },
        footer = { enabled = true, left = "none", center = "book_title_page_progress_cn", right = "none", divider_style = "progress_bar", divider_position = "below" },
    },
    kobo_split = {
        name = "Kobo Split (Book and chapter · Time and reading estimate)",
        header = { enabled = true, left = "book_title", center = "none", right = "chapter_title", divider_style = "none" },
        footer = { enabled = true, left = "clock", center = "none", right = "time_left_book_pages", divider_style = "none" },
    },
    ireader = {
        name = "iReader Style (Book and chapter · Reading estimate · Pages)",
        header = { enabled = true, left = "book_title", center = "none", right = "chapter_title", divider_style = "none" },
        footer = { enabled = true, left = "clock", center = "time_left_book", right = "page_progress", divider_style = "none" },
    },
    hanvon = {
        name = "Hanvon Style (Chapter · Battery/time · Pages)",
        header = { enabled = true, left = "chapter_title", center = "none", right = "none", divider_style = "none" },
        footer = { enabled = true, left = "battery_time", center = "none", right = "page_progress", divider_style = "none" },
    },
    boox = {
        name = "BOOX Style (Book/chapter · Time/battery · Percent)",
        header = { enabled = true, left = "book_title", center = "chapter_title", right = "time_battery", divider_style = "none" },
        footer = { enabled = true, left = "chapter_title", center = "none", right = "reading_percent", divider_style = "none" },
    },
    wechat_reading = {
        name = "WeRead Style (Chapter · Time · Pages)",
        header = { enabled = true, left = "chapter_title", center = "none", right = "none", divider_style = "none", hide_on_chapter_start = true },
        footer = { enabled = true, left = "clock", center = "none", right = "page_progress", divider_style = "none" },
    },
    minimal_pages = {
        name = "Minimalist Pages (No header)",
        footer_name = "Minimalist Pages (Centered X of Y)",
        header = { enabled = false, left = "none", center = "none", right = "none", divider_style = "none" },
        footer = { enabled = true, left = "none", center = "page_progress_cn", right = "none", divider_style = "none" },
    },
    modern_full = {
        name = "Modern Full (Left chapter · Right time/battery)",
        footer_name = "Modern Full (Left chapter time · Right combo progress · Progress bar)",
        header = { enabled = true, left = "chapter_title", center = "none", right = "time_battery", divider_style = "none" },
        footer = { enabled = true, left = "time_left_chapter", center = "none", right = "progress_combo_cn", divider_style = "progress_bar" },
    },
}

-- Per-bar wording and the two keys that genuinely differ between the bars.
local BARS = {
    custom_header = {
        half = "header",
        other = "custom_footer",
        toggle_label = "Custom top header",
        font_title = "Header font size",
        divider_label = "Divider style",
        offset_key = "top_offset",
        offset_label = "Top margin offset: %1 px",
        offset_title = "Top margin offset",
        gap_key = "padding_bottom",
        native = "top",
    },
    custom_footer = {
        half = "footer",
        other = "custom_header",
        toggle_label = "Custom bottom footer",
        font_title = "Footer font size",
        divider_label = "Divider / Progress bar style",
        offset_key = "bottom_offset",
        offset_label = "Bottom margin offset: %1 px",
        offset_title = "Bottom margin offset",
        gap_key = "padding_top",
        native = "bottom",
    },
}

local function barConfig(ctx, bar)
    local config = ctx.getReadonlyConfig and ctx.getReadonlyConfig(ctx.ui) or ctx.getConfig(ctx.ui)
    return config[bar] or {}
end

local function barDefault(bar, key)
    local defaults = DEFAULTS[bar] or {}
    return defaults[key]
end

local function setParam(ctx, bar, key, value)
    local config = ctx.getConfig(ctx.ui)
    config[bar] = config[bar] or {}
    config[bar][key] = value
    ctx.applyStyle(config)
end

local function barOn(ctx, bar)
    return barConfig(ctx, bar).enabled == true
end

function StatusBarMenu.applyPreset(ctx, bar, preset_id)
    local preset = PRESETS[preset_id]
    if not preset then return end
    local config = ctx.getConfig(ctx.ui)
    for _, target_bar in ipairs({ "custom_header", "custom_footer" }) do
        local half = preset[BARS[target_bar].half]
        if half then
            config[target_bar] = config[target_bar] or {}
            local target = config[target_bar]
            target.preset = preset_id
            target.left = half.left
            target.center = half.center
            target.right = half.right
            target.divider_style = half.divider_style
            target.divider_position = half.divider_position or "auto"
            target.hide_on_chapter_start = (half.hide_on_chapter_start == true)
            if half.enabled ~= nil then
                target.enabled = half.enabled
            end
        end
    end
    ctx.applyStyle(config)
end

function StatusBarMenu.slotItems(ctx, bar, slot_name)
    local tr = ctx.tr
    local items = {}
    for _, id in ipairs(Config.STATUS_SLOTS) do
        local label = SLOT_LABELS[id]
        if label then
            table.insert(items, {
                text = tr(label),
                radio = true,
                keep_menu_open = true,
                enabled_func = function() return barOn(ctx, bar) end,
                checked_func = function() return barConfig(ctx, bar)[slot_name] == id end,
                callback = function(touchmenu_instance)
                    local config = ctx.getConfig(ctx.ui)
                    config[bar] = config[bar] or {}
                    config[bar][slot_name] = id
                    -- Hand-picking a slot leaves the preset behind by definition.
                    config[bar].preset = "custom"
                    ctx.applyStyle(config)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            })
        end
    end
    return items
end

function StatusBarMenu.dividerItems(ctx, bar)
    local tr = ctx.tr
    local items = {}
    for _, id in ipairs(Config.STATUS_DIVIDERS) do
        local label = DIVIDER_LABELS[id]
        if label then
            table.insert(items, {
                text = tr(label),
                radio = true,
                keep_menu_open = true,
                enabled_func = function() return barOn(ctx, bar) end,
                checked_func = function() return barConfig(ctx, bar).divider_style == id end,
                callback = function(touchmenu_instance)
                    setParam(ctx, bar, "divider_style", id)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            })
        end
    end
    return items
end

function StatusBarMenu.presetItems(ctx, bar, options)
    local tr = ctx.tr
    local footer_menu = (bar == "custom_footer")
    local items = {}
    for _, id in ipairs(Config.STATUS_PRESETS) do
        -- "custom" is the marker written when a slot is hand-picked, not a look you
        -- can choose; it stays valid in the config but never appears as a radio.
        local preset = (id ~= "custom") and PRESETS[id] or nil
        if preset then
            local label = (footer_menu and preset.footer_name) or preset.name
            table.insert(items, {
                text = tr(label),
                radio = true,
                keep_menu_open = true,
                enabled_func = options and options.enabled_func
                    or function() return barOn(ctx, bar) end,
                checked_func = function()
                    if options and options.synchronized then
                        return barConfig(ctx, "custom_header").preset == id
                            and barConfig(ctx, "custom_footer").preset == id
                    end
                    return barConfig(ctx, bar).preset == id
                end,
                callback = function(touchmenu_instance)
                    StatusBarMenu.applyPreset(ctx, bar, id)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            })
        end
    end
    return items
end

local function textInputRow(ctx, opts)
    return {
        text_func = opts.text_func,
        keep_menu_open = true,
        enabled_func = opts.enabled_func,
        callback = function(touchmenu_instance)
            local dialog
            dialog = InputDialog:new{
                title = ctx.tr(opts.title),
                input = tostring(opts.get() or ""),
                buttons = {{
                    {
                        text = ctx.tr("Cancel"),
                        callback = function() UIManager:close(dialog) end,
                    },
                    {
                        text = ctx.tr("Save"),
                        is_enter_default = true,
                        callback = function()
                            local text = dialog:getInputText()
                            if opts.allow_empty or (text and text ~= "") then
                                opts.set(text or "")
                            end
                            UIManager:close(dialog)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    },
                }},
            }
            UIManager:show(dialog)
            dialog:onShowKeyboard()
        end,
        separator = opts.separator,
    }
end

local function spinRow(ctx, opts)
    return {
        text_func = opts.text_func,
        keep_menu_open = true,
        enabled_func = opts.enabled_func,
        callback = function(touchmenu_instance)
            UIManager:show(SpinWidget:new{
                title_text = ctx.tr(opts.title),
                value = opts.get(),
                value_min = opts.min,
                value_max = opts.max,
                value_step = opts.step or 1,
                unit = opts.unit,
                default_value = opts.default,
                ok_always_enabled = true,
                callback = function(spin)
                    opts.set(spin.value)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            })
        end,
        separator = opts.separator,
    }
end

local function toggleRow(ctx, bar, label, key, default_on, extra_enabled)
    return {
        text = ctx.tr(label),
        keep_menu_open = true,
        enabled_func = function()
            if not barOn(ctx, bar) then return false end
            if extra_enabled then return extra_enabled() end
            return true
        end,
        checked_func = function()
            if default_on then return barConfig(ctx, bar)[key] ~= false end
            return barConfig(ctx, bar)[key] == true
        end,
        callback = function(touchmenu_instance)
            local current
            if default_on then
                current = barConfig(ctx, bar)[key] ~= false
            else
                current = barConfig(ctx, bar)[key] == true
            end
            setParam(ctx, bar, key, not current)
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    }
end

-- The crengine "alt status bar" at the top of the page. 0 enables it, 1 disables it
-- (crengine's own convention). It only exists for reflowable documents, and main.lua's
-- applyStyle forces it off while the custom header is painting, so the row is disabled
-- in both of those cases instead of silently losing the user's tap.
local function nativeTopRow(ctx, bar)
    local tr = ctx.tr
    local T = ctx.T
    local function configurable()
        local ui = ctx.ui
        if ui and ui.rolling and ui.document then return ui.document.configurable end
        return nil
    end
    local function isOn()
        local conf = configurable()
        return conf ~= nil and conf.status_line == 0
    end
    return {
        text_func = function()
            local status = isOn() and tr("Enabled") or tr("Disabled")
            return T(tr("%1: %2"), tr("KOReader native top status bar"), status)
        end,
        keep_menu_open = true,
        enabled_func = function()
            return configurable() ~= nil and not barOn(ctx, bar)
        end,
        checked_func = isOn,
        callback = function(touchmenu_instance)
            local conf = configurable()
            if not conf then return end
            local next_val = isOn() and 1 or 0
            conf.status_line = next_val
            -- ReaderConfig persists configurable under the copt_ prefix on close; write
            -- it now too so the choice survives a crash mid-session.
            if ctx.ui.doc_settings then
                pcall(function() ctx.ui.doc_settings:saveSetting("copt_status_line", next_val) end)
            end
            pcall(function() ctx.ui:handleEvent(Event:new("SetStatusLine", next_val)) end)
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    }
end

-- KOReader's own bottom bar. Visibility lives in view.footer_visible and is changed
-- through ReaderFooter:applyFooterMode + refreshFooter; the doc_settings key
-- "footer_visible" and the methods setVisible / recalculateMargins this row used to
-- call have never existed, so the row did nothing but redraw its own label.
local function nativeBottomRow(ctx, bar)
    local tr = ctx.tr
    local T = ctx.T
    local function footer()
        local ui = ctx.ui
        local f = ui and ui.view and ui.view.footer
        if f and f.mode_list and f.applyFooterMode then return f end
        return nil
    end
    local function isVisible()
        local ui = ctx.ui
        return ui ~= nil and ui.view ~= nil and ui.view.footer_visible == true
    end
    return {
        text_func = function()
            local status = isVisible() and tr("Visible") or tr("Hidden")
            return T(tr("KOReader native bottom status bar: %1"), status)
        end,
        keep_menu_open = true,
        enabled_func = function() return footer() ~= nil and not barOn(ctx, bar) end,
        checked_func = isVisible,
        callback = function(touchmenu_instance)
            local f = footer()
            if not f then return end
            local off = f.mode_list.off or 0
            local target
            if isVisible() then
                target = off
            else
                local settings = rawget(_G, "G_reader_settings")
                local saved = settings and settings:readSetting("reader_footer_mode")
                if type(saved) == "number" and saved ~= off then
                    target = saved
                else
                    target = f.mode_list.page_progress or 1
                end
            end
            pcall(function() f:applyFooterMode(target) end)
            local settings = rawget(_G, "G_reader_settings")
            if settings then
                pcall(function() settings:saveSetting("reader_footer_mode", target) end)
            end
            if f.refreshFooter then
                pcall(function() f:refreshFooter(true, true) end)
            end
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    }
end

function StatusBarMenu.items(ctx, bar, options)
    local spec = BARS[bar]
    if not spec then return {} end
    local tr = ctx.tr
    local T = ctx.T
    local on = function() return barOn(ctx, bar) end
    local cfg = function() return barConfig(ctx, bar) end

    local advanced_items = {
        spinRow(ctx, {
            title = "Divider thickness",
            unit = "px",
            min = 1,
            -- From Config, not a literal: this row offered 4, normalize accepted 1..3 and
            -- replaced anything else with the *default*, so picking the thickest divider
            -- silently gave you the thinnest one.
            max = Config.STATUS_DIVIDER_THICKNESS_MAX,
            default = barDefault(bar, "divider_thickness"),
            text_func = function()
                return T(tr("Divider thickness: %1 px"),
                    tostring(cfg().divider_thickness or barDefault(bar, "divider_thickness")))
            end,
            enabled_func = function() return on() and cfg().divider_style ~= "none" end,
            get = function() return cfg().divider_thickness or barDefault(bar, "divider_thickness") end,
            set = function(value) setParam(ctx, bar, "divider_thickness", value) end,
        }),
        spinRow(ctx, {
            title = "Gap between text and divider",
            unit = "px",
            min = 0,
            max = Config.STATUS_PADDING_MAX,
            default = barDefault(bar, spec.gap_key),
            text_func = function()
                return T(tr("Gap between text and divider: %1 px"),
                    tostring(cfg()[spec.gap_key] or barDefault(bar, spec.gap_key)))
            end,
            enabled_func = function() return on() and cfg().divider_style ~= "none" end,
            get = function() return cfg()[spec.gap_key] or barDefault(bar, spec.gap_key) end,
            set = function(value) setParam(ctx, bar, spec.gap_key, value) end,
        }),
        toggleRow(ctx, bar, "Chapter tick marks on progress bar", "chapter_ticks", true, function()
            return cfg().divider_style == "progress_bar"
        end),
        textInputRow(ctx, {
            title = "Custom divider character / symbol",
            text_func = function()
                local char = cfg().divider_custom_char or barDefault(bar, "divider_custom_char")
                return T(tr("Custom divider symbol: %1"), tostring(char))
            end,
            enabled_func = function() return on() and cfg().divider_style == "custom" end,
            get = function() return cfg().divider_custom_char or barDefault(bar, "divider_custom_char") end,
            set = function(text) setParam(ctx, bar, "divider_custom_char", text) end,
        }),
        textInputRow(ctx, {
            title = "Custom slot text",
            allow_empty = true,
            text_func = function()
                local text = cfg().custom_text or ""
                return T(tr("Custom text: %1"), text ~= "" and text or tr("Empty"))
            end,
            enabled_func = on,
            get = function() return cfg().custom_text or "" end,
            set = function(text) setParam(ctx, bar, "custom_text", text) end,
            separator = true,
        }),
        toggleRow(ctx, bar, "Bold text", "font_bold", false),
        -- No italic row: KOReader's TextWidget has no italic field, so font_italic could
        -- never render. The key is still accepted by Config for older saved settings.
        toggleRow(ctx, bar, "Hide on chapter start page", "hide_on_chapter_start", false),
        toggleRow(ctx, bar, "Facing pages layout (Recto/Verso alternate)", "facing_pages", false),
        toggleRow(ctx, bar, "Align to page text margin", "margin_inset", true),
    }
    advanced_items[#advanced_items].separator = true
    if spec.native == "top" then
        table.insert(advanced_items, nativeTopRow(ctx, bar))
    else
        table.insert(advanced_items, nativeBottomRow(ctx, bar))
    end

    local items = {
        {
            text_func = function()
                local status = on() and tr("Enabled") or tr("Disabled")
                return T(tr("%1: %2"), tr(spec.toggle_label), status)
            end,
            keep_menu_open = true,
            checked_func = on,
            callback = function(touchmenu_instance)
                local config = ctx.getConfig(ctx.ui)
                config[bar] = config[bar] or {}
                config[bar].enabled = not on()
                ctx.applyStyle(config)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
            separator = true,
        },
        {
            text = tr("Left slot"),
            enabled_func = on,
            sub_item_table_func = function() return StatusBarMenu.slotItems(ctx, bar, "left") end,
        },
        {
            text = tr("Center slot"),
            enabled_func = on,
            sub_item_table_func = function() return StatusBarMenu.slotItems(ctx, bar, "center") end,
        },
        {
            text = tr("Right slot"),
            enabled_func = on,
            sub_item_table_func = function() return StatusBarMenu.slotItems(ctx, bar, "right") end,
            separator = true,
        },
        {
            text = tr(spec.divider_label),
            enabled_func = on,
            sub_item_table_func = function() return StatusBarMenu.dividerItems(ctx, bar) end,
        },
        spinRow(ctx, {
            title = spec.font_title,
            unit = "pt",
            min = Config.STATUS_FONT_MIN,
            max = Config.STATUS_FONT_MAX,
            default = barDefault(bar, "font_size"),
            text_func = function()
                return T(tr("Font size: %1 pt"), tostring(cfg().font_size or barDefault(bar, "font_size")))
            end,
            enabled_func = on,
            get = function() return cfg().font_size or barDefault(bar, "font_size") end,
            set = function(value) setParam(ctx, bar, "font_size", value) end,
        }),
        spinRow(ctx, {
            title = spec.offset_title,
            unit = "px",
            min = 0,
            max = Config.STATUS_OFFSET_MAX,
            default = barDefault(bar, spec.offset_key),
            text_func = function()
                return T(tr(spec.offset_label),
                    tostring(cfg()[spec.offset_key] or barDefault(bar, spec.offset_key)))
            end,
            enabled_func = on,
            get = function() return cfg()[spec.offset_key] or barDefault(bar, spec.offset_key) end,
            set = function(value) setParam(ctx, bar, spec.offset_key, value) end,
            separator = true,
        }),
        {
            text = tr("More appearance & options"),
            sub_item_table = advanced_items,
        },
    }
    if not options or options.include_presets ~= false then
        table.insert(items, 2, {
            text = tr("Layout presets"),
            enabled_func = on,
            sub_item_table_func = function() return StatusBarMenu.presetItems(ctx, bar) end,
        })
    end

    return items
end

-- The two bars form one reading chrome. Keep their shared presets in one menu and
-- retain separate submenus (with quick checkmark toggles) for detailed top/bottom adjustments.
function StatusBarMenu.combinedItems(ctx)
    local tr = ctx.tr
    local function toggleBar(bar, touchmenu_instance)
        local config = ctx.getConfig(ctx.ui)
        config[bar] = config[bar] or {}
        config[bar].enabled = not (config[bar].enabled == true)
        ctx.applyStyle(config)
        if touchmenu_instance then touchmenu_instance:updateItems() end
    end
    return {
        {
            text = tr("Layout presets"),
            sub_item_table_func = function()
                return StatusBarMenu.presetItems(ctx, "custom_header", {
                    enabled_func = function() return true end,
                    synchronized = true,
                })
            end,
            separator = true,
        },
        {
            text = tr("Custom top header"),
            keep_menu_open = true,
            checked_func = function() return barOn(ctx, "custom_header") end,
            checkmark_callback = function(touchmenu_instance)
                toggleBar("custom_header", touchmenu_instance)
            end,
            sub_item_table_func = function()
                return StatusBarMenu.items(ctx, "custom_header", { include_presets = false })
            end,
        },
        {
            text = tr("Custom bottom footer"),
            keep_menu_open = true,
            checked_func = function() return barOn(ctx, "custom_footer") end,
            checkmark_callback = function(touchmenu_instance)
                toggleBar("custom_footer", touchmenu_instance)
            end,
            sub_item_table_func = function()
                return StatusBarMenu.items(ctx, "custom_footer", { include_presets = false })
            end,
        },
    }
end

-- Exported for tests/status_bar_spec.lua: the labelled vocabularies must cover exactly
-- what Config can persist.
function StatusBarMenu.labelledSlots() return SLOT_LABELS end
function StatusBarMenu.labelledDividers() return DIVIDER_LABELS end
function StatusBarMenu.labelledPresets() return PRESETS end

return StatusBarMenu
