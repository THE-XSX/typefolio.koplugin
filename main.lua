-- typefolio.koplugin/main.lua
-- 文笺 / Type Folio: underline and typesetting tweaks for CRE books, applied
-- through KOReader's official Style tweaks mechanism (a generated
-- styletweaks/99_typefolio.css enabled per book via doc_settings).
local item_path = debug.getinfo(1, "S").source:sub(2)
local PLUGIN_ROOT = item_path:match("(.*[/\\])") or "plugins/typefolio.koplugin/"

local CSSTemplates = dofile(PLUGIN_ROOT .. "css_templates.lua")
local Painter = dofile(PLUGIN_ROOT .. "painter.lua")
local I18n = dofile(PLUGIN_ROOT .. "i18n.lua")
local tr = I18n.new(PLUGIN_ROOT, { language_setting = "typefolio_language" })

local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Notification = require("ui/widget/notification")
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = Device.screen
local T = require("ffi/util").template
local io = require("io")

local CONFIG_KEY = "typefolio_config"
local TWEAK_ID = "99_typefolio.css"
-- 用户自定义预设：{ [name] = config snapshot }，存全局（与书本无关）
local CUSTOM_PRESETS_KEY = "typefolio_custom_presets"

-- 渲染方式是全局设置：CSS 文件本就全局共享（见 README 已知限制），
-- 若做成每本书，"这个文件归谁管"会更难说清。
local RENDER_MODE_KEY = "typefolio_render_mode"

local function getRenderMode()
    local mode = G_reader_settings:readSetting(RENDER_MODE_KEY)
    return mode == "paint" and "paint" or "css"
end

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
    config.tweak_params = config.tweak_params or {}
    return config
end

-- 预设是"整份配置"的快照：保存时拷贝快照，应用时用快照替换现场。
-- 名字即键，重命名=搬键；冲突直接在保存/重命名入口拦截。
local function getCustomPresets()
    local t = G_reader_settings:readSetting(CUSTOM_PRESETS_KEY)
    return type(t) == "table" and t or {}
end

local function snapshotConfig(config)
    -- 深拷贝一层半就够：tweaks / tweak_params 是嵌套表，得单独复制
    local snap = {}
    for k, v in pairs(config) do
        if type(v) == "table" then
            snap[k] = {}
            for k2, v2 in pairs(v) do snap[k][k2] = v2 end
        else
            snap[k] = v
        end
    end
    return snap
end

local function saveCustomPreset(name, config)
    local presets = getCustomPresets()
    presets[name] = snapshotConfig(config)
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
        config.underline, config.line_thickness, config.dash_pattern) or ""
end

-- 结构类特效作用于 h1/hr/blockquote/::first-letter，与画上去的下划线互不重叠，
-- 故两种渲染方式下都生成
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

-- ReaderStyleTweak 关书时会用内存态 doc_tweaks 整表覆盖写回 doc_settings，
-- 因此必须同步内存态。这里存 false 而不是 nil：updateCssText 里 nil 表示"未表态"，
-- 会让全局启用的同名 tweak 重新生效；false 才是明确停用（见 readerstyletweak.lua:402-411）。
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

local function applyStyle(self, config)
    local ui = self.ui
    if not ui or not ui.doc_settings then return end
    ui.doc_settings:saveSetting(CONFIG_KEY, config)

    -- 互斥只发生在下划线这一层：绘制模式下不生成下划线 CSS，
    -- 结构类特效两种模式下都照常生成
    local paint_mode = getRenderMode() == "paint"
    local parts = {}
    if not paint_mode then
        local underline = buildUnderlineCss(config)
        if underline ~= "" then table.insert(parts, underline) end
    end
    local tweaks = buildTweakCss(config)
    if tweaks ~= "" then table.insert(parts, tweaks) end
    local css = table.concat(parts, "\n\n")

    setTweakEnabled(ui, css ~= "")

    -- updateCssText(true) 会广播 ApplyStyleSheet 触发整篇重排，代价不低，
    -- 故只在样式表真的变了时才付这个代价（例如绘制模式下调线宽就不该重排）。
    if css ~= self.last_css then
        self.last_css = css
        saveCssToStyleTweaks(css)
        if ui.styletweak then
            ui.styletweak:updateCssText(true)
        end
    end

    if self.painter then
        self.painter.enabled = paint_mode
        self.painter:setConfig(config)
        self.painter:invalidate()
    end
    UIManager:setDirty(ui.view and ui.view.dialog, "partial")
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

function TypeFolio:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

-- 注册进 KOReader 的手势/快捷方式列表（设置 → 手势 → …），这样不必
-- 每次都「点菜单 → 翻到排版页 → 找文笺」
function TypeFolio:onDispatcherRegisterActions()
    Dispatcher:registerAction("typefolio_show", {
        category = "none",
        event = "ShowTypeFolioMenu",
        title = tr("Type Folio"),
        rolling = true,
    })
end

-- 直接把本插件的菜单当成一个独立的单页 TouchMenu 弹出来
function TypeFolio:onShowTypeFolioMenu()
    -- 动作注册在 rolling 分区，正常只在 CRE 书里可选到；但手势可以绑在全局，
    -- 没有打开的书时就没什么可调的
    if not (self.ui and self.ui.doc_settings) then return true end

    local TouchMenu = require("ui/widget/touchmenu")

    -- TouchMenu 要的是"标签页"结构：数组部分是菜单项，icon/title 是这一页的表头
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

-- 绘制后端依赖 CRE 的行框 API，PDF/DjVu 不适用；registerViewModule 没有反注册
-- 接口，故照官方 perceptionexpander 的做法：始终注册，靠 enabled 在 paintTo 里早退
function TypeFolio:onReaderReady()
    if self.ui.paging then return end
    self.painter = Painter:new{}
    self.painter.enabled = getRenderMode() == "paint"
    self.painter:setConfig(getConfig(self.ui))
    self.view:registerViewModule("typefolio_painter", self.painter)
end

-- Painter 在 view_modules 里，收不到事件；本插件在 ReaderUI 的数组里，能收到，
-- 故由这里转发失效通知。惰性重算放在 paintTo，搭上本就要发生的那次重绘。
function TypeFolio:_invalidatePainter()
    if self.painter then self.painter:invalidate() end
end

TypeFolio.onPageUpdate = TypeFolio._invalidatePainter
TypeFolio.onPosUpdate = TypeFolio._invalidatePainter
TypeFolio.onDocumentRerendered = TypeFolio._invalidatePainter
TypeFolio.onDocumentPartiallyRerendered = TypeFolio._invalidatePainter
TypeFolio.onChangeViewMode = TypeFolio._invalidatePainter
TypeFolio.onSetPageMargins = TypeFolio._invalidatePainter
TypeFolio.onSetStatusLine = TypeFolio._invalidatePainter

function TypeFolio:_renderModeItems()
    local options = {
        { key = "css", text = tr("Stylesheet (CSS)") },
        { key = "paint", text = tr("Direct drawing") },
    }
    local items = {}
    for _, option in ipairs(options) do
        table.insert(items, {
            text = option.text,
            keep_menu_open = true,
            radio = true,
            checked_func = function() return getRenderMode() == option.key end,
            callback = function(touchmenu_instance)
                G_reader_settings:saveSetting(RENDER_MODE_KEY, option.key)
                applyStyle(self, getConfig(self.ui))
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        })
    end
    items[#items].separator = true
    -- 万一某本书的 xpointer 形状不符合预期导致漏画，用户可以关掉这层过滤
    table.insert(items, {
        text = tr("Skip headings and blockquotes"),
        keep_menu_open = true,
        enabled_func = function() return getRenderMode() == "paint" end,
        checked_func = function() return getConfig(self.ui).skip_headings ~= false end,
        callback = function(touchmenu_instance)
            local config = getConfig(self.ui)
            config.skip_headings = config.skip_headings == false
            applyStyle(self, config)
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    })
    return items
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
                        applyStyle(self, config)
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
        { key = "para", text = tr("Underline paragraph bottoms"), css_only = true },
        { key = "em_only", text = tr("Underline emphasized words only"), css_only = true },
        { key = "marker", text = tr("Highlighter background") },
    }
    local items = {}
    for _, option in ipairs(options) do
        table.insert(items, {
            text = option.text,
            keep_menu_open = true,
            radio = true,
            -- 段落底线与强调词需要 DOM 结构，绘制路径只拿得到屏幕行框
            enabled_func = function()
                return not (option.css_only and getRenderMode() == "paint")
            end,
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
                applyStyle(self, config)
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
                applyStyle(self, config)
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
                applyStyle(self, config)
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

-- 参数读写：缺省值一律回落到 css_templates 的 tweak_defaults，
-- 这样菜单与模板永远看到同一个默认值
function TypeFolio:_getParam(tweak_key, name)
    local params = getConfig(self.ui).tweak_params[tweak_key]
    local value = params and params[name]
    if value == nil then return CSSTemplates.tweak_defaults[tweak_key][name] end
    return value
end

function TypeFolio:_setParam(tweak_key, name, value)
    local config = getConfig(self.ui)
    config.tweak_params[tweak_key] = config.tweak_params[tweak_key] or {}
    config.tweak_params[tweak_key][name] = value
    applyStyle(self, config)
end

-- 枚举参数的单选项；label_of 把值映射为已翻译的显示文案
function TypeFolio:_paramRadio(tweak_key, name, values, label_of)
    local items = {}
    for _, value in ipairs(values) do
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

-- 数值参数用 SpinWidget；不传 unit/precision 的话默认 "%02d" 会把 1 显示成 01
function TypeFolio:_paramSpin(tweak_key, name, spec)
    return {
        text_func = function()
            local value = self:_getParam(tweak_key, name)
            -- 小数步长会累积浮点误差（1.5+0.1=1.6000000000000001），显示前先定精度
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

-- 特效本身的开关，放在子菜单第一行。墨水屏上外层那个小勾选框不好点，
-- 进来之后有一个整行可点的开关更稳；标题直接写出当前状态，扫一眼即知。
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

function TypeFolio:_tweakSubItems(key)
    local O = CSSTemplates.tweak_options
    local lineStyle = function() return self:_paramRadio(key, "line_style", O.line_style,
        function(v) return tr(LINE_STYLE_LABELS[v]) end) end

    if key == "header_border" then
        return {
            self:_tweakEnableItem(key, "Chapter heading decoration"),
            { text = tr("Border position"),
              enabled_func = function() return getConfig(self.ui).tweaks[key] == true end,
              sub_item_table = self:_paramRadio(key, "border", O.border,
                  function(v) return tr(BORDER_LABELS[v]) end) },
            -- 边框可以设为"无"，此时线样式与粗细就没有意义了，一并灰置
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
        }
    elseif key == "custom_hr_dashed" then
        return {
            self:_tweakEnableItem(key, "Chapter break rules"),
            { text = tr("Line style"),
              enabled_func = function() return getConfig(self.ui).tweaks[key] == true end,
              sub_item_table = lineStyle() },
            self:_paramSpin(key, "thickness",
                { label = "Line thickness: %1", title = "Rule thickness",
                  min = 1, max = 5, unit = "px" }),
            { text = tr("Width"),
              enabled_func = function() return getConfig(self.ui).tweaks[key] == true end,
              sub_item_table = self:_paramRadio(key, "width", O.width,
                  function(v) return v .. "%" end) },
        }
    elseif key == "blockquote_box" then
        return {
            self:_tweakEnableItem(key, "Blockquote decoration"),
            { text = tr("Left bar thickness"),
              enabled_func = function() return getConfig(self.ui).tweaks[key] == true end,
              sub_item_table = self:_paramRadio(key, "bar", O.bar,
                  function(v) return v == 0 and tr("No bar") or (v .. "px") end) },
            { text = tr("Background tint"),
              enabled_func = function() return getConfig(self.ui).tweaks[key] == true end,
              sub_item_table = self:_paramRadio(key, "tint", O.tint,
                  function(v) return tr(TINT_LABELS[v]) end) },
            self:_paramToggle(key, "italic", "Italic text"),
        }
    elseif key == "dialogue_style" then
        local TINT_LEVEL_LABELS = {
            light  = "Light",
            medium = "Medium",
            strong = "Strong",
        }
        return {
            self:_tweakEnableItem(key, "Dialogue highlight"),
            self:_paramToggle(key, "tint", "Background tint"),
            { text = tr("Tint intensity"),
              enabled_func = function()
                  return getConfig(self.ui).tweaks[key] == true
                      and self:_getParam(key, "tint") == true
              end,
              sub_item_table = self:_paramRadio(key, "tint_level", O.tint_level,
                  function(v) return tr(TINT_LEVEL_LABELS[v]) end) },
            self:_paramToggle(key, "bold", "Bold"),
            self:_paramToggle(key, "italic", "Italic"),
        }
    elseif key == "drop_caps" then
        return {
            self:_tweakEnableItem(key, "Newspaper drop caps"),
            self:_paramSpin(key, "scale",
                { label = "Size: %1", title = "Drop cap size",
                  min = 1.5, max = 3.5, step = 0.1, hold_step = 0.5,
                  precision = "%.1f", unit = "em" }),
            self:_paramToggle(key, "bold", "Bold"),
        }
    end
    return nil
end

function TypeFolio:_tweakItems()
    local ui = self.ui
    local options = {
        { key = "dialogue_style", text = "Dialogue highlight" },
        { key = "custom_hr_dashed", text = "Chapter break rules" },
        { key = "blockquote_box", text = "Blockquote decoration" },
        { key = "header_border", text = "Chapter heading decoration" },
        { key = "drop_caps", text = "Newspaper drop caps" },
        { key = "pure_black", text = "Force pure black text" },
    }
    local items = {}
    for _, option in ipairs(options) do
        local key = option.key
        local sub_items = self:_tweakSubItems(key)
        local toggle = function(touchmenu_instance)
            local config = getConfig(ui)
            config.tweaks[key] = not config.tweaks[key]
            applyStyle(self, config)
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end
        local item = {
            text = tr(option.text),
            keep_menu_open = true,
            checked_func = function() return getConfig(ui).tweaks[key] == true end,
        }
        if sub_items then
            -- 点最左侧勾选区=开关，点其余区域=进子菜单（见 touchmenu.lua:861-865、178-185）
            item.checkmark_callback = toggle
            item.sub_item_table = sub_items
        else
            item.callback = toggle
        end
        table.insert(items, item)
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
                -- 预设只决定"开哪些特效"，用户已调好的参数保留
                local config = {
                    underline = preset.underline,
                    line_thickness = "1.5px",
                    dash_pattern = preset.dash_pattern or "normal",
                    tweaks = {},
                    tweak_params = getConfig(ui).tweak_params,
                    skip_headings = getConfig(ui).skip_headings,
                }
                for tweak, enabled in pairs(preset.tweaks) do
                    config.tweaks[tweak] = enabled
                end
                applyStyle(self, config)
                notify(T(tr("Applied preset: %1"), tr(preset.name)))
            end,
        })
    end
    table.insert(items, {
        text = tr("Restore default typesetting"),
        keep_menu_open = true,
        callback = function()
            applyStyle(self, {
                underline = "none",
                line_thickness = "1.5px",
                dash_pattern = "normal",
                tweaks = {},
                tweak_params = {},
            })
            notify(tr("All typesetting tweaks reset"))
        end,
    })
    -- 用户自定义预设子菜单：把"现在的样子"存为 named snapshot，
    -- 之后任何书点名字即可整体套用
    table.insert(items, {
        text = tr("Custom presets"),
        sub_item_table_func = function() return self:_customPresetItems() end,
    })
    return items
end

function TypeFolio:_customPresetItems()
    local presets = getCustomPresets()
    local names = {}
    for name in pairs(presets) do table.insert(names, name) end
    table.sort(names)
    local items = {}
    table.insert(items, {
        text = tr("＋ Save current as new preset"),
        keep_menu_open = false,
        callback = function()
            local dialog
            dialog = InputDialog:new{
                title = tr("Preset name"),
                input = T(tr("My preset %1"), tostring(#names + 1)),
                input_hint = tr("e.g. Night serif body"),
                buttons = {{{
                    text = tr("Cancel"),
                    callback = function() UIManager:close(dialog) end,
                }, {
                    text = tr("Save"),
                    is_enter_default = true,
                    callback = function()
                        local name = dialog:getInputText()
                        if not name or name == "" then return end
                        if presets[name] then
                            notify(tr("Name already in use"))
                            return
                        end
                        saveCustomPreset(name, getConfig(self.ui))
                        UIManager:close(dialog)
                        notify(T(tr("Saved preset: %1"), name))
                    end,
                }}},
            }
            UIManager:show(dialog)
            dialog:onShowKeyboard()
        end,
    })
    if #names == 0 then
        table.insert(items, { text = tr("(No custom presets yet)"), enabled = false })
        return items
    end
    for _, name in ipairs(names) do
        table.insert(items, {
            text = name,
            sub_item_table_func = function() return self:_customPresetEntryItems(name) end,
        })
    end
    return items
end

function TypeFolio:_customPresetEntryItems(name)
    return {
        {
            text = tr("Apply this preset"),
            callback = function()
                local preset = getCustomPresets()[name]
                if preset then
                    applyStyle(self, snapshotConfig(preset))
                    notify(T(tr("Applied preset: %1"), name))
                end
            end,
        },
        {
            text = tr("Rename…"),
            callback = function()
                local dialog
                dialog = InputDialog:new{
                    title = tr("Rename preset"),
                    input = name,
                    buttons = {{{
                        text = tr("Cancel"),
                        callback = function() UIManager:close(dialog) end,
                    }, {
                        text = tr("Save"),
                        is_enter_default = true,
                        callback = function()
                            local new_name = dialog:getInputText()
                            if not new_name or new_name == "" or new_name == name then
                                UIManager:close(dialog)
                                return
                            end
                            if renameCustomPreset(name, new_name) then
                                UIManager:close(dialog)
                                notify(T(tr("Renamed to: %1"), new_name))
                            else
                                notify(tr("Name already in use"))
                            end
                        end,
                    }}},
                }
                UIManager:show(dialog)
                dialog:onShowKeyboard()
            end,
        },
        {
            text = T(tr("Delete \"%1\""), name),
            callback = function()
                deleteCustomPreset(name)
                notify(T(tr("Deleted preset: %1"), name))
            end,
        },
    }
end

function TypeFolio:_helpSubItems()
    return {
        {
            text = tr("Overview & Rendering"),
            callback = function()
                local help_lines = {
                    tr("HELP_TITLE"),
                    "",
                    tr("HELP_RENDERING"),
                }
                showInfo(table.concat(help_lines, "\n"))
            end,
        },
        {
            text = tr("Calibre regex guide"),
            callback = function()
                local help_lines = {
                    tr("HELP_CALIBRE_REGEX_TITLE"),
                    "",
                    tr("HELP_DIALOGUE"),
                    "",
                    tr("HELP_CALIBRE_DIALOGUE"),
                    "",
                    tr("HELP_CALIBRE_TITLE"),
                    "",
                    tr("HELP_CALIBRE_HR"),
                    "",
                    tr("HELP_CALIBRE_QUOTE"),
                    "",
                    tr("HELP_CALIBRE_DROPCAP"),
                }
                showInfo(table.concat(help_lines, "\n"))
            end,
        },
        {
            text = tr("Gestures & Presets"),
            callback = function()
                local help_lines = {
                    tr("HELP_GESTURE"),
                    "",
                    tr("HELP_PRESETS"),
                }
                showInfo(table.concat(help_lines, "\n"))
            end,
        },
    }
end

function TypeFolio:menuItems()
    local items = {}
    -- 头部一行说明入口：点进去展开分类子菜单，避免单页弹窗文字过长
    table.insert(items, {
        text = tr("Help / user guide"),
        sub_item_table_func = function() return self:_helpSubItems() end,
        separator = true,
    })
    table.insert(items, {
        text = tr("Underline rendering"),
        sub_item_table = self:_renderModeItems(),
        separator = true,
    })
    for _, item in ipairs(self:_underlineItems()) do table.insert(items, item) end
    table.insert(items, { text = tr("Stroke style"), sub_item_table = self:_strokeItems() })
    table.insert(items, {
        text = tr("Line thickness"),
        sub_item_table = self:_thicknessItems(),
        separator = true,
    })
    -- 结构类特效与预设在两种渲染方式下都可用：它们作用于 h1/hr/blockquote，
    -- 与画上去的下划线不重叠
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
