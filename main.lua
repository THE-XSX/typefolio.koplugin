-- typefolio.koplugin/main.lua
-- 文笺 / Type Folio: underline and typesetting tweaks for CRE books, applied
-- through KOReader's official Style tweaks mechanism (a generated
-- styletweaks/99_typefolio.css enabled per book via doc_settings).
local item_path = debug.getinfo(1, "S").source:sub(2)
local PLUGIN_ROOT = item_path:match("(.*[/\\])") or "plugins/typefolio.koplugin/"

local CSSTemplates = dofile(PLUGIN_ROOT .. "css_templates.lua")
local I18n = dofile(PLUGIN_ROOT .. "i18n.lua")
local tr = I18n.new(PLUGIN_ROOT, { language_setting = "typefolio_language" })

local DataStorage = require("datastorage")
local InputDialog = require("ui/widget/inputdialog")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local T = require("ffi/util").template
local io = require("io")

local CONFIG_KEY = "typefolio_config"
local TWEAK_ID = "99_typefolio.css"

-- KOReader 只扫描 DataStorage:getDataDir()/styletweaks/ 这一个用户 CSS 目录
-- （见 frontend/apps/reader/modules/readerstyletweak.lua），写到其它位置的
-- 文件永远不会被 Style tweaks 机制装载；该目录由 KOReader 启动时自动创建。
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
    config = config or {
        underline = "none",
        line_thickness = "1.5px",
        dash_pattern = "normal",
        tweaks = {},
    }
    config.line_thickness = config.line_thickness or "1.5px"
    config.dash_pattern = config.dash_pattern or "normal"
    config.tweaks = config.tweaks or {}
    return config
end

local function buildCss(config)
    if not config then return "" end
    local parts = {}
    if config.underline and config.underline ~= "none" then
        local css = CSSTemplates.getUnderlineCss(
            config.underline, config.line_thickness, config.dash_pattern)
        if css and css ~= "" then table.insert(parts, css) end
    end
    for key, enabled in pairs(config.tweaks or {}) do
        if enabled and CSSTemplates.layout_tweaks[key] then
            table.insert(parts, CSSTemplates.layout_tweaks[key])
        end
    end
    return table.concat(parts, "\n\n")
end

local function forceReloadKOReaderStyleTweaks(ui)
    if not ui then return end

    -- ReaderStyleTweak 关书时会用内存态 doc_tweaks 整表覆盖写回 doc_settings，
    -- 因此必须同步内存态；updateCssText(true) 会广播 ApplyStyleSheet 即时生效
    -- （本次会话新建的 CSS 文件要重开书才会被注册，属官方扫描时机限制）。
    if ui.styletweak then
        ui.styletweak.doc_tweaks[TWEAK_ID] = true
        ui.styletweak:updateCssText(true)
    end

    if ui.doc_settings then
        local tweaks = ui.doc_settings:readSetting("style_tweaks") or {}
        tweaks[TWEAK_ID] = true
        ui.doc_settings:saveSetting("style_tweaks", tweaks)
    end

    UIManager:setDirty(nil, "full")
end

local function applyStyle(ui, config)
    if not ui or not ui.doc_settings then return end
    ui.doc_settings:saveSetting(CONFIG_KEY, config)
    saveCssToStyleTweaks(buildCss(config))
    forceReloadKOReaderStyleTweaks(ui)
end

local function notify(text)
    UIManager:show(Notification:new{ text = text })
end

local TypeFolio = WidgetContainer:extend{
    name = "typefolio",
    is_doc_only = true,
}

function TypeFolio:init()
    self.ui.menu:registerToMainMenu(self)
end

function TypeFolio:_thicknessDialog()
    local ui = self.ui
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
                    local value = (dialog:getInputText() or ""):gsub("%s+", "")
                    if value ~= "" then
                        if not value:find("px") then value = value .. "px" end
                        config.line_thickness = value
                        applyStyle(ui, config)
                        notify(T(tr("Thickness set to %1"), value))
                    end
                    UIManager:close(dialog)
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function TypeFolio:_underlineItems()
    local ui = self.ui
    local options = {
        { key = "none", text = tr("None (book default)") },
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
                local underline = getConfig(ui).underline
                if option.key == "all_lines" then
                    return underline == "all_lines" or underline == "all_lines_dashed_compat"
                        or underline == "all_lines_dashed" or underline == "all_lines_solid"
                        or underline == "all_lines_dotted" or underline == "thick_lines"
                elseif option.key == "para" then
                    return underline == "para" or underline == "para_dashed"
                        or underline == "para_dotted"
                end
                return underline == option.key
            end,
            callback = function()
                local config = getConfig(ui)
                config.underline = option.key
                applyStyle(ui, config)
            end,
        })
    end
    items[#items].separator = true
    return items
end

function TypeFolio:_strokeItems()
    local ui = self.ui
    local options = {
        { key = "solid", text = tr("Smooth solid (────)") },
        { key = "normal", text = tr("Standard dashes (-- --)") },
        { key = "dense", text = tr("Dense dots (····)") },
        { key = "thick", text = tr("Thick solid (━━━━)") },
    }
    local items = {}
    for _, option in ipairs(options) do
        table.insert(items, {
            text = option.text,
            keep_menu_open = true,
            radio = true,
            checked_func = function() return getConfig(ui).dash_pattern == option.key end,
            callback = function()
                local config = getConfig(ui)
                config.dash_pattern = option.key
                applyStyle(ui, config)
            end,
        })
    end
    return items
end

function TypeFolio:_thicknessItems()
    local ui = self.ui
    local items = {}
    for _, preset in ipairs({
        { value = "1.0px", text = tr("1.0px (hairline)") },
        { value = "1.5px", text = tr("1.5px (default)") },
        { value = "2.0px", text = tr("2.0px (bold)") },
    }) do
        table.insert(items, {
            text = preset.text,
            keep_menu_open = true,
            radio = true,
            checked_func = function() return getConfig(ui).line_thickness == preset.value end,
            callback = function()
                local config = getConfig(ui)
                config.line_thickness = preset.value
                applyStyle(ui, config)
            end,
        })
    end
    table.insert(items, {
        text = tr("Custom thickness…"),
        keep_menu_open = true,
        callback = function() self:_thicknessDialog() end,
    })
    return items
end

function TypeFolio:_tweakItems()
    local ui = self.ui
    local options = {
        { key = "custom_hr_dashed", text = tr("Long dashed rules at breaks (------------)") },
        { key = "blockquote_box", text = tr("Blockquote borders and tint") },
        { key = "header_border", text = tr("Centered headers with rules") },
        { key = "drop_caps", text = tr("Newspaper drop caps") },
        { key = "pure_black", text = tr("Force pure black text") },
    }
    local items = {}
    for _, option in ipairs(options) do
        table.insert(items, {
            text = option.text,
            keep_menu_open = true,
            checked_func = function()
                return getConfig(ui).tweaks[option.key] == true
            end,
            callback = function()
                local config = getConfig(ui)
                config.tweaks[option.key] = not config.tweaks[option.key]
                applyStyle(ui, config)
            end,
        })
    end
    items[#items].separator = true
    return items
end

function TypeFolio:_presetItems()
    local ui = self.ui
    local keys = {}
    for key in pairs(CSSTemplates.presets) do table.insert(keys, key) end
    table.sort(keys)
    local items = {}
    for _, key in ipairs(keys) do
        local preset = CSSTemplates.presets[key]
        table.insert(items, {
            text = T(tr("Preset: %1"), tr(preset.name)),
            keep_menu_open = true,
            callback = function()
                local config = {
                    underline = preset.underline,
                    line_thickness = "1.5px",
                    dash_pattern = preset.dash_pattern or "normal",
                    tweaks = {},
                }
                for tweak, enabled in pairs(preset.tweaks) do
                    config.tweaks[tweak] = enabled
                end
                applyStyle(ui, config)
                notify(T(tr("Applied preset: %1"), tr(preset.name)))
            end,
        })
    end
    table.insert(items, {
        text = tr("Restore default typesetting"),
        keep_menu_open = true,
        callback = function()
            applyStyle(ui, {
                underline = "none",
                line_thickness = "1.5px",
                dash_pattern = "normal",
                tweaks = {},
            })
            notify(tr("All typesetting tweaks reset"))
        end,
    })
    return items
end

function TypeFolio:menuItems()
    local items = {}
    for _, item in ipairs(self:_underlineItems()) do table.insert(items, item) end
    table.insert(items, { text = tr("Stroke style"), sub_item_table = self:_strokeItems() })
    table.insert(items, {
        text = tr("Line thickness"),
        sub_item_table = self:_thicknessItems(),
        separator = true,
    })
    for _, item in ipairs(self:_tweakItems()) do table.insert(items, item) end
    for _, item in ipairs(self:_presetItems()) do table.insert(items, item) end
    return items
end

function TypeFolio:addToMainMenu(menu_items)
    menu_items.typefolio = {
        sorting_hint = "typeset",
        text = tr("Type Folio"),
        sub_item_table_func = function() return self:menuItems() end,
    }
end

return TypeFolio
