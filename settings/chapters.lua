-- settings/chapters.lua
-- Chapter-related settings: title decoration, page breaks, boundary markers
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")

local ChapterSettings = {}

local function getChapterBoundary(ctx, boundary, name)
    return ctx.getConfig(ctx.ui).awareness.chapter[boundary][name]
end

local function setChapterBoundary(ctx, boundary, name, value)
    local config = ctx.getConfig(ctx.ui)
    config.awareness.chapter[boundary][name] = value
    ctx.applyStyle(config)
end

function ChapterSettings.boundaryStyleItems(ctx, boundary)
    local tr = ctx.tr
    local items = {}
    local options = {
        { key = "single", text = tr("Single rule") },
        { key = "double", text = tr("Double rule") },
        { key = "wave", text = tr("Wave line") },
        { key = "dots", text = tr("Thick dots") },
        { key = "heart", text = tr("Heart symbol") },
        { key = "custom", text = tr("Custom character") },
    }
    for _, option in ipairs(options) do
        local value, label = option.key, option.text
        table.insert(items, {
            text = label,
            radio = true,
            keep_menu_open = true,
            enabled_func = function()
                return getChapterBoundary(ctx, boundary, "enabled") == true
            end,
            checked_func = function()
                return getChapterBoundary(ctx, boundary, "style") == value
            end,
            callback = function(touchmenu_instance)
                setChapterBoundary(ctx, boundary, "style", value)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        })
    end
    return items
end

function ChapterSettings.boundaryItems(ctx, boundary, title)
    local tr = ctx.tr
    local T = ctx.T
    return {
        {
            text_func = function()
                local status = getChapterBoundary(ctx, boundary, "enabled")
                    and tr("Enabled") or tr("Disabled")
                return T(tr("%1: %2"), tr(title), status)
            end,
            keep_menu_open = true,
            checked_func = function()
                return getChapterBoundary(ctx, boundary, "enabled") == true
            end,
            callback = function(touchmenu_instance)
                setChapterBoundary(ctx, boundary, "enabled",
                    not getChapterBoundary(ctx, boundary, "enabled"))
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
            separator = true,
        },
        {
            text = tr("Decoration style"),
            enabled_func = function()
                return getChapterBoundary(ctx, boundary, "enabled") == true
            end,
            sub_item_table = ChapterSettings.boundaryStyleItems(ctx, boundary),
        },
        {
            text_func = function()
                local char = getChapterBoundary(ctx, boundary, "char") or "★"
                return T(tr("Custom character: %1"), tostring(char))
            end,
            keep_menu_open = true,
            enabled_func = function()
                return getChapterBoundary(ctx, boundary, "enabled") == true
            end,
            callback = function(touchmenu_instance)
                local InputDialog = require("ui/widget/inputdialog")
                local dialog
                dialog = InputDialog:new{
                    title = tr("Custom decoration character / symbol"),
                    input = tostring(getChapterBoundary(ctx, boundary, "char") or "★"),
                    buttons = {{{
                        text = tr("Cancel"),
                        callback = function() UIManager:close(dialog) end,
                    }, {
                        text = tr("Save"),
                        is_enter_default = true,
                        callback = function()
                            local text = dialog:getInputText()
                            if text and text ~= "" then
                                setChapterBoundary(ctx, boundary, "char", text)
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
                local count = getChapterBoundary(ctx, boundary, "count") or 5
                return T(tr("Decoration count: %1"), tostring(count))
            end,
            keep_menu_open = true,
            enabled_func = function()
                return getChapterBoundary(ctx, boundary, "enabled") == true
            end,
            callback = function(touchmenu_instance)
                UIManager:show(SpinWidget:new{
                    title_text = tr("Decoration count"),
                    value = tonumber(getChapterBoundary(ctx, boundary, "count")) or 5,
                    value_min = 1,
                    value_max = 20,
                    value_step = 1,
                    value_hold_step = 2,
                    default_value = 5,
                    ok_always_enabled = true,
                    callback = function(spin)
                        setChapterBoundary(ctx, boundary, "count", spin.value)
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                })
            end,
        },
        {
            text_func = function()
                return T(tr("Thickness: %1"),
                    tostring(getChapterBoundary(ctx, boundary, "thickness")))
            end,
            keep_menu_open = true,
            enabled_func = function()
                return getChapterBoundary(ctx, boundary, "enabled") == true
            end,
            callback = function(touchmenu_instance)
                UIManager:show(SpinWidget:new{
                    title_text = T(tr("%1 thickness"), tr(title)),
                    value = getChapterBoundary(ctx, boundary, "thickness"),
                    value_min = 1,
                    value_max = 5,
                    value_step = 1,
                    value_hold_step = 1,
                    default_value = 1,
                    ok_always_enabled = true,
                    callback = function(spin)
                        setChapterBoundary(ctx, boundary, "thickness", spin.value)
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                })
            end,
        },
    }
end

function ChapterSettings.boundaryMenuItem(ctx, boundary, title)
    local tr = ctx.tr
    return {
        text = tr(title),
        keep_menu_open = true,
        checked_func = function()
            return getChapterBoundary(ctx, boundary, "enabled") == true
        end,
        checkmark_callback = function(touchmenu_instance)
            setChapterBoundary(ctx, boundary, "enabled",
                not getChapterBoundary(ctx, boundary, "enabled"))
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
        sub_item_table_func = function()
            return ChapterSettings.boundaryItems(ctx, boundary, title)
        end,
    }
end

function ChapterSettings.items(ctx)
    local heading_items = ctx.tweakItems({
        { key = "header_border", text = "Chapter title" },
        { key = "chapter_pagebreak", text = "Chapter page break" },
    })
    return {
        heading_items[1],
        heading_items[2],
        ChapterSettings.boundaryMenuItem(ctx, "start", "Chapter start"),
        ChapterSettings.boundaryMenuItem(ctx, "end", "Chapter end"),
    }
end

return ChapterSettings
