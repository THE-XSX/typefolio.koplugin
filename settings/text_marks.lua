-- settings/text_marks.lua
-- Text marks settings: underlines, strokes, thickness, and render policy
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")

local TextMarksSettings = {}

function TextMarksSettings.renderModeItems(ctx)
    local tr = ctx.tr
    local getRenderPolicy = ctx.getRenderPolicy
    local RENDER_POLICY_KEY = ctx.RENDER_POLICY_KEY
    local getConfig = ctx.getConfig
    local applyStyle = ctx.applyStyle
    local ui = ctx.ui

    local options = {
        { key = "auto", text = tr("Automatic") },
        { key = "css", text = tr("CSS compatibility mode") },
        { key = "paint", text = tr("Prefer direct drawing") },
    }
    local items = {}
    for _, option in ipairs(options) do
        table.insert(items, {
            text = option.text,
            keep_menu_open = true,
            radio = true,
            checked_func = function() return getRenderPolicy() == option.key end,
            callback = function(touchmenu_instance)
                G_reader_settings:saveSetting(RENDER_POLICY_KEY, option.key)
                applyStyle(getConfig(ui))
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        })
    end
    items[#items].separator = true

    table.insert(items, {
        text = tr("Skip headings and centered text"),
        keep_menu_open = true,
        enabled_func = function() return getRenderPolicy() ~= "css" end,
        checked_func = function() return getConfig(ui).skip_headings ~= false end,
        callback = function(touchmenu_instance)
            local config = getConfig(ui)
            config.skip_headings = config.skip_headings == false
            applyStyle(config)
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    })

    table.insert(items, {
        text = tr("Skip blockquotes"),
        keep_menu_open = true,
        enabled_func = function() return getRenderPolicy() ~= "css" end,
        checked_func = function() return getConfig(ui).skip_blockquotes ~= false end,
        callback = function(touchmenu_instance)
            local config = getConfig(ui)
            config.skip_blockquotes = config.skip_blockquotes == false
            applyStyle(config)
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    })
    return items
end

function TextMarksSettings.thicknessDialog(ctx, touchmenu_instance)
    local tr = ctx.tr
    local T = ctx.T
    local getConfig = ctx.getConfig
    local applyStyle = ctx.applyStyle
    local notify = ctx.notify
    local ui = ctx.ui

    local config = getConfig(ui)
    local dialog
    dialog = InputDialog:new{
        title = tr("Enter line thickness in px (e.g. 1.5)"),
        input = config.line_thickness:gsub("px", ""),
        input_type = "number",
        buttons = {{
            {
                text = tr("Cancel"),
                id = "close",
                callback = function() UIManager:close(dialog) end,
            },
            {
                text = tr("Set"),
                is_enter_default = true,
                callback = function()
                    local raw = (dialog:getInputText() or ""):gsub("%s+", ""):gsub("[pP][xX]$", "")
                    local num = tonumber(raw)
                    if not num or num <= 0 then
                        notify(tr("Enter a positive number (e.g. 1.5)"))
                        return
                    end
                    if num > 20 then num = 20 end
                    local value = (num == math.floor(num))
                        and (string.format("%d", num) .. "px")
                        or (string.format("%.2f", num):gsub("0+$", ""):gsub("%.$", "") .. "px")
                    config.line_thickness = value
                    applyStyle(config)
                    notify(T(tr("Thickness set to %1"), value))
                    UIManager:close(dialog)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function TextMarksSettings.underlineItems(ctx)
    local tr = ctx.tr
    local getConfig = ctx.getConfig
    local applyStyle = ctx.applyStyle
    local ui = ctx.ui

    local options = {
        { key = "none", text = tr("None") },
        { key = "all_lines", text = tr("Underline every line") },
        { key = "para", text = tr("Underline paragraph bottoms") },
        { key = "em_only", text = tr("Underline emphasized words only") },
        { key = "marker", text = tr("Highlighter background") },
    }
    local items = {}
    for _, option in ipairs(options) do
        table.insert(items, {
            text = option.text,
            keep_menu_open = true,
            radio = true,
            checked_func = function()
                return getConfig(ui).underline == option.key
            end,
            callback = function(touchmenu_instance)
                local config = getConfig(ui)
                config.underline = option.key
                applyStyle(config)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        })
    end
    items[#items].separator = true
    return items
end

function TextMarksSettings.strokeItems(ctx)
    local tr = ctx.tr
    local getConfig = ctx.getConfig
    local applyStyle = ctx.applyStyle
    local ui = ctx.ui

    local options = {
        { key = "solid", text = tr("Smooth solid") },
        { key = "normal", text = tr("Standard dashes") },
        { key = "dense", text = tr("Dense dots") },
        { key = "thick", text = tr("Thick solid") },
    }
    local items = {}
    for _, option in ipairs(options) do
        table.insert(items, {
            text = option.text,
            keep_menu_open = true,
            radio = true,
            checked_func = function() return getConfig(ui).dash_pattern == option.key end,
            callback = function(touchmenu_instance)
                local config = getConfig(ui)
                config.dash_pattern = option.key
                applyStyle(config)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        })
    end
    return items
end

function TextMarksSettings.thicknessItems(ctx)
    local tr = ctx.tr
    local getConfig = ctx.getConfig
    local applyStyle = ctx.applyStyle
    local ui = ctx.ui

    local items = {}
    for _, preset in ipairs({
        { value = "1.0px", text = tr("1.0px") },
        { value = "1.5px", text = tr("1.5px") },
        { value = "2.0px", text = tr("2.0px") },
    }) do
        table.insert(items, {
            text = preset.text,
            keep_menu_open = true,
            radio = true,
            checked_func = function() return getConfig(ui).line_thickness == preset.value end,
            callback = function(touchmenu_instance)
                local config = getConfig(ui)
                config.line_thickness = preset.value
                applyStyle(config)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        })
    end
    table.insert(items, {
        text = tr("Custom thickness…"),
        keep_menu_open = true,
        callback = function(touchmenu_instance) TextMarksSettings.thicknessDialog(ctx, touchmenu_instance) end,
    })
    return items
end

function TextMarksSettings.items(ctx)
    local tr = ctx.tr
    return {
        { text = tr("Mark type"), sub_item_table = TextMarksSettings.underlineItems(ctx) },
        { text = tr("Stroke style"), sub_item_table = TextMarksSettings.strokeItems(ctx) },
        { text = tr("Line thickness"), sub_item_table = TextMarksSettings.thicknessItems(ctx) },
        { text = tr("Rendering"), sub_item_table = TextMarksSettings.renderModeItems(ctx) },
    }
end

return TextMarksSettings
