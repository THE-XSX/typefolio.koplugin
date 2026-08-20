-- settings/custom_header.lua
-- Settings for Typefolio Modern Custom Reading Header (页眉 / 顶部状态栏)
local item_path = debug.getinfo(1, "S").source:sub(2)
local PLUGIN_ROOT = item_path:match("(.*[/\\]typefolio%.koplugin[/\\])") or item_path:match("(.*[/\\])settings[/\\]") or item_path:match("(.*[/\\])") or "plugins/typefolio.koplugin/"

local InputDialog = require("ui/widget/inputdialog")
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")

local CustomHeaderSettings = {}

local SLOT_ITEMS = {
    { key = "none", text = "None (Empty)" },
    { key = "chapter_title", text = "Chapter title" },
    { key = "book_title", text = "Book title" },
    { key = "author", text = "Author" },
    { key = "clock", text = "Current time (Clock)" },
    { key = "battery", text = "Battery percentage" },
    { key = "time_battery", text = "Time · Battery" },
    { key = "reading_percent", text = "Reading progress percentage" },
    { key = "page_progress", text = "Page progress (X / Y)" },
    { key = "progress_combo", text = "Progress · Page count (42% · 45/320)" },
    { key = "pages_left_chapter", text = "Pages left in chapter" },
    { key = "custom_text", text = "Custom text" },
}

local DIVIDER_STYLES = {
    { key = "none", text = "None (Blank)" },
    { key = "solid", text = "Solid line" },
    { key = "dashed", text = "Dashed line" },
    { key = "dots_small", text = "Small dots (· · ·)" },
    { key = "dots_big", text = "Big dots (● ● ●)" },
    { key = "vertical_bar", text = "Vertical bars (| | |)" },
    { key = "slash", text = "Slashes (/ / /)" },
    { key = "double_slash", text = "Double slashes (// // //)" },
    { key = "custom", text = "Custom symbol / pattern" },
}

local PRESETS = {
    modern = {
        name = "Modern (Left chapter · Right time/battery · Solid)",
        left = "chapter_title",
        center = "none",
        right = "time_battery",
        divider_style = "solid",
    },
    minimal = {
        name = "Minimal (Centered chapter · No divider)",
        left = "none",
        center = "chapter_title",
        right = "none",
        divider_style = "none",
    },
    classic = {
        name = "Classic (Left book · Center chapter · Right pages · Solid)",
        left = "book_title",
        center = "chapter_title",
        right = "page_progress",
        divider_style = "solid",
    },
    reading = {
        name = "Reading (Left chapter · Center progress · Right time · Dots)",
        left = "chapter_title",
        center = "reading_percent",
        right = "clock",
        divider_style = "dots_small",
    },
}

local function getHeaderConfig(ctx)
    local config = ctx.getConfig(ctx.ui)
    return config.custom_header or {}
end

local function setHeaderParam(ctx, name, value)
    local config = ctx.getConfig(ctx.ui)
    config.custom_header = config.custom_header or {}
    config.custom_header[name] = value
    ctx.applyStyle(config)
end

function CustomHeaderSettings.slotItems(ctx, slot_name, slot_title)
    local tr = ctx.tr
    local items = {}
    for _, opt in ipairs(SLOT_ITEMS) do
        local key = opt.key
        table.insert(items, {
            text = tr(opt.text),
            radio = true,
            keep_menu_open = true,
            enabled_func = function()
                return getHeaderConfig(ctx).enabled == true
            end,
            checked_func = function()
                return getHeaderConfig(ctx)[slot_name] == key
            end,
            callback = function(touchmenu_instance)
                local config = ctx.getConfig(ctx.ui)
                config.custom_header = config.custom_header or {}
                config.custom_header[slot_name] = key
                config.custom_header.preset = "custom"
                ctx.applyStyle(config)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        })
    end
    return items
end

function CustomHeaderSettings.dividerItems(ctx)
    local tr = ctx.tr
    local items = {}
    for _, opt in ipairs(DIVIDER_STYLES) do
        local key = opt.key
        table.insert(items, {
            text = tr(opt.text),
            radio = true,
            keep_menu_open = true,
            enabled_func = function()
                return getHeaderConfig(ctx).enabled == true
            end,
            checked_func = function()
                return getHeaderConfig(ctx).divider_style == key
            end,
            callback = function(touchmenu_instance)
                setHeaderParam(ctx, "divider_style", key)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        })
    end
    return items
end

function CustomHeaderSettings.presetItems(ctx)
    local tr = ctx.tr
    local items = {}
    for preset_key, preset_data in pairs(PRESETS) do
        table.insert(items, {
            text = tr(preset_data.name),
            radio = true,
            keep_menu_open = true,
            enabled_func = function()
                return getHeaderConfig(ctx).enabled == true
            end,
            checked_func = function()
                return getHeaderConfig(ctx).preset == preset_key
            end,
            callback = function(touchmenu_instance)
                local config = ctx.getConfig(ctx.ui)
                config.custom_header = config.custom_header or {}
                config.custom_header.preset = preset_key
                config.custom_header.left = preset_data.left
                config.custom_header.center = preset_data.center
                config.custom_header.right = preset_data.right
                config.custom_header.divider_style = preset_data.divider_style
                ctx.applyStyle(config)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        })
    end
    return items
end

function CustomHeaderSettings.items(ctx)
    local tr = ctx.tr
    local T = ctx.T
    local headerOn = function() return getHeaderConfig(ctx).enabled == true end

    local items = {
        {
            text_func = function()
                local status = headerOn() and tr("Enabled") or tr("Disabled")
                return T(tr("%1: %2"), tr("Custom top header"), status)
            end,
            keep_menu_open = true,
            checked_func = headerOn,
            callback = function(touchmenu_instance)
                local config = ctx.getConfig(ctx.ui)
                config.custom_header = config.custom_header or {}
                config.custom_header.enabled = not headerOn()
                ctx.applyStyle(config)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
            separator = true,
        },
        {
            text = tr("Layout presets"),
            enabled_func = headerOn,
            sub_item_table_func = function() return CustomHeaderSettings.presetItems(ctx) end,
        },
        {
            text = tr("Left slot"),
            enabled_func = headerOn,
            sub_item_table_func = function() return CustomHeaderSettings.slotItems(ctx, "left", "Left slot") end,
        },
        {
            text = tr("Center slot"),
            enabled_func = headerOn,
            sub_item_table_func = function() return CustomHeaderSettings.slotItems(ctx, "center", "Center slot") end,
        },
        {
            text = tr("Right slot"),
            enabled_func = headerOn,
            sub_item_table_func = function() return CustomHeaderSettings.slotItems(ctx, "right", "Right slot") end,
            separator = true,
        },
        {
            text = tr("Divider style"),
            enabled_func = headerOn,
            sub_item_table_func = function() return CustomHeaderSettings.dividerItems(ctx) end,
        },
        {
            text_func = function()
                local char = getHeaderConfig(ctx).divider_custom_char or "✦"
                return T(tr("Custom divider symbol: %1"), tostring(char))
            end,
            keep_menu_open = true,
            enabled_func = function()
                return headerOn() and getHeaderConfig(ctx).divider_style == "custom"
            end,
            callback = function(touchmenu_instance)
                local dialog
                dialog = InputDialog:new{
                    title = tr("Custom divider character / symbol"),
                    input = tostring(getHeaderConfig(ctx).divider_custom_char or "✦"),
                    buttons = {{{
                        text = tr("Cancel"),
                        callback = function() UIManager:close(dialog) end,
                    }, {
                        text = tr("Save"),
                        is_enter_default = true,
                        callback = function()
                            local text = dialog:getInputText()
                            if text and text ~= "" then
                                setHeaderParam(ctx, "divider_custom_char", text)
                                if touchmenu_instance then touchmenu_instance:updateItems() end
                            end
                            UIManager:close(dialog)
                        end,
                    }}},
                }
                UIManager:show(dialog)
                dialog:onShowKeyboard()
            end,
        },
        {
            text_func = function()
                local custom_text = getHeaderConfig(ctx).custom_text or ""
                return T(tr("Custom text: %1"), custom_text ~= "" and custom_text or tr("None"))
            end,
            keep_menu_open = true,
            enabled_func = headerOn,
            callback = function(touchmenu_instance)
                local dialog
                dialog = InputDialog:new{
                    title = tr("Custom slot text"),
                    input = tostring(getHeaderConfig(ctx).custom_text or ""),
                    buttons = {{{
                        text = tr("Cancel"),
                        callback = function() UIManager:close(dialog) end,
                    }, {
                        text = tr("Save"),
                        is_enter_default = true,
                        callback = function()
                            local text = dialog:getInputText()
                            setHeaderParam(ctx, "custom_text", text or "")
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                            UIManager:close(dialog)
                        end,
                    }}},
                }
                UIManager:show(dialog)
                dialog:onShowKeyboard()
            end,
            separator = true,
        },
        {
            text_func = function()
                local size = getHeaderConfig(ctx).font_size or 13
                return T(tr("Font size: %1 pt"), tostring(size))
            end,
            keep_menu_open = true,
            enabled_func = headerOn,
            callback = function(touchmenu_instance)
                UIManager:show(SpinWidget:new{
                    title_text = tr("Header font size"),
                    value = getHeaderConfig(ctx).font_size or 13,
                    value_min = 9,
                    value_max = 24,
                    value_step = 1,
                    unit = "pt",
                    default_value = 13,
                    ok_always_enabled = true,
                    callback = function(spin)
                        setHeaderParam(ctx, "font_size", spin.value)
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                })
            end,
        },
        {
            text = tr("Bold text"),
            keep_menu_open = true,
            enabled_func = headerOn,
            checked_func = function() return getHeaderConfig(ctx).font_bold == true end,
            callback = function(touchmenu_instance)
                setHeaderParam(ctx, "font_bold", not getHeaderConfig(ctx).font_bold)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        },
        {
            text = tr("Italic text"),
            keep_menu_open = true,
            enabled_func = headerOn,
            checked_func = function() return getHeaderConfig(ctx).font_italic == true end,
            callback = function(touchmenu_instance)
                setHeaderParam(ctx, "font_italic", not getHeaderConfig(ctx).font_italic)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        },
        {
            text_func = function()
                local offset = getHeaderConfig(ctx).top_offset or 12
                return T(tr("Top margin offset: %1 px"), tostring(offset))
            end,
            keep_menu_open = true,
            enabled_func = headerOn,
            callback = function(touchmenu_instance)
                UIManager:show(SpinWidget:new{
                    title_text = tr("Top margin offset"),
                    value = getHeaderConfig(ctx).top_offset or 12,
                    value_min = 2,
                    value_max = 40,
                    value_step = 1,
                    unit = "px",
                    default_value = 12,
                    ok_always_enabled = true,
                    callback = function(spin)
                        setHeaderParam(ctx, "top_offset", spin.value)
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                })
            end,
        },
        {
            text = tr("Hide on chapter start page"),
            keep_menu_open = true,
            enabled_func = headerOn,
            checked_func = function() return getHeaderConfig(ctx).hide_on_chapter_start == true end,
            callback = function(touchmenu_instance)
                setHeaderParam(ctx, "hide_on_chapter_start", not getHeaderConfig(ctx).hide_on_chapter_start)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
            separator = true,
        },
        {
            text_func = function()
                local sys_on = false
                if ctx.ui and ctx.ui.document and ctx.ui.document.configurable then
                    sys_on = ctx.ui.document.configurable.status_line == 0
                end
                local status = sys_on and tr("Enabled") or tr("Disabled")
                return T(tr("%1: %2"), tr("KOReader native top status bar"), status)
            end,
            keep_menu_open = true,
            checked_func = function()
                if ctx.ui and ctx.ui.document and ctx.ui.document.configurable then
                    return ctx.ui.document.configurable.status_line == 0
                end
                return false
            end,
            callback = function(touchmenu_instance)
                local Event = require("ui/event")
                local cur = 1
                if ctx.ui and ctx.ui.document and ctx.ui.document.configurable then
                    cur = ctx.ui.document.configurable.status_line or 1
                end
                local next_val = (cur == 0) and 1 or 0
                if ctx.ui and ctx.ui.doc_settings then
                    ctx.ui.doc_settings:saveSetting("copt_status_line", next_val)
                end
                if ctx.ui and ctx.ui.document and ctx.ui.document.configurable then
                    ctx.ui.document.configurable.status_line = next_val
                end
                pcall(function() ctx.ui:handleEvent(Event:new("ConfigChange", "status_line", next_val)) end)
                pcall(function() ctx.ui:handleEvent(Event:new("SetStatusLine", next_val)) end)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        },
    }
    return items
end

return CustomHeaderSettings
