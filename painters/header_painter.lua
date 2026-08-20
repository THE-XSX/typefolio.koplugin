-- painters/header_painter.lua
-- Typefolio Modern Custom Reading Header (页眉 / 顶部状态栏)
local item_path = debug.getinfo(1, "S").source:sub(2)
local PLUGIN_ROOT = item_path:match("(.*[/\\]typefolio%.koplugin[/\\])") or item_path:match("(.*[/\\])painters[/\\]") or item_path:match("(.*[/\\])") or "plugins/typefolio.koplugin/"

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local TextWidget = require("ui/widget/textwidget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = Device.screen

local HeaderPainter = WidgetContainer:extend{
    enabled = false,
}

function HeaderPainter:setConfig(config)
    self.config = config or {}
    self.header_config = self.config.custom_header or {}
    self.enabled = self.header_config.enabled == true
    self:invalidate()
end

function HeaderPainter:invalidate(reason)
    self.cache = nil
end

local function safeCall(fn)
    local ok, res = pcall(fn)
    if ok then return res end
    return nil
end

local function truncateText(text, max_w, face, bold, italic)
    if not text or text == "" then return "" end
    local tb = TextWidget:new{
        text = text,
        face = face,
        bold = bold,
        italic = italic,
    }
    local size = tb:getSize()
    if size.w <= max_w then return text end

    local current = text
    while #current > 1 do
        -- Truncate by UTF-8 character or single byte safely
        local byte_len = #current
        local step = 1
        if byte_len >= 3 and current:byte(byte_len - 2) >= 224 then
            step = 3
        elseif byte_len >= 2 and current:byte(byte_len - 1) >= 192 then
            step = 2
        end
        current = current:sub(1, math.max(0, byte_len - step))
        if current == "" then break end

        local candidate = current .. "…"
        tb = TextWidget:new{
            text = candidate,
            face = face,
            bold = bold,
            italic = italic,
        }
        if tb:getSize().w <= max_w then
            return candidate
        end
    end
    return ""
end

function HeaderPainter:_getItemText(slot_type, page_num, page_count, chapter, doc_props)
    if slot_type == "none" or not slot_type then
        return ""
    elseif slot_type == "chapter_title" then
        return chapter and chapter.title ~= "" and chapter.title or (doc_props and (doc_props.display_title or doc_props.title) or "")
    elseif slot_type == "book_title" then
        return doc_props and (doc_props.display_title or doc_props.title) or ""
    elseif slot_type == "author" then
        return doc_props and (doc_props.authors or doc_props.author) or ""
    elseif slot_type == "clock" then
        return os.date("%H:%M")
    elseif slot_type == "battery" then
        local pct = safeCall(function() return Device:getBatteryPercentage() end)
        return pct and (pct .. "%") or (Device:hasBattery() and "100%" or "")
    elseif slot_type == "time_battery" then
        local time_str = os.date("%H:%M")
        local pct = safeCall(function() return Device:getBatteryPercentage() end)
        if pct then
            return time_str .. " · " .. pct .. "%"
        end
        return time_str
    elseif slot_type == "reading_percent" then
        if page_count and page_count > 0 then
            return math.floor(math.min(100, math.max(0, (page_num / page_count) * 100))) .. "%"
        end
        return ""
    elseif slot_type == "page_progress" then
        if page_count and page_count > 0 then
            return string.format("%d / %d", page_num, page_count)
        end
        return tostring(page_num)
    elseif slot_type == "progress_combo" then
        if page_count and page_count > 0 then
            local pct = math.floor(math.min(100, math.max(0, (page_num / page_count) * 100)))
            return string.format("%d%% · %d/%d", pct, page_num, page_count)
        end
        return tostring(page_num)
    elseif slot_type == "pages_left_chapter" then
        local left = nil
        if self.context and self.ui and self.ui.toc then
            local next_chapter_page = safeCall(function() return self.ui.toc:getNextChapterPage(page_num) end)
            if next_chapter_page and next_chapter_page > page_num then
                left = next_chapter_page - page_num
            end
        end
        if left then
            return left .. " pages left"
        end
        return ""
    elseif slot_type == "custom_text" then
        return self.header_config.custom_text or ""
    end
    return ""
end

function HeaderPainter:_paintTextAt(bb, text, x, y, face, bold, italic)
    if not text or text == "" then return 0, 0 end
    local tb = TextWidget:new{
        text = text,
        face = face,
        bold = bold,
        italic = italic,
        fgcolor = Blitbuffer.COLOR_BLACK,
        bgcolor = Blitbuffer.COLOR_WHITE,
    }
    local size = tb:getSize()
    local mask = Blitbuffer.new(size.w, size.h, Blitbuffer.TYPE_BB8)
    mask:fill(Blitbuffer.COLOR_WHITE)
    tb:paintTo(mask, 0, 0)
    mask:invertRect(0, 0, size.w, size.h)
    bb:colorblitFromRGB32(mask, math.max(0, math.floor(x)), math.max(0, math.floor(y)), 0, 0, size.w, size.h, Blitbuffer.COLOR_BLACK)
    mask:free()
    return size.w, size.h
end

function HeaderPainter:_paintDivider(bb, style, thickness, custom_char, x0, x1, y, font_face)
    local width = x1 - x0
    if width <= 0 or style == "none" then return end

    if style == "solid" or style == "thin" then
        bb:paintRect(x0, y, width, thickness, Blitbuffer.COLOR_BLACK)
    elseif style == "dashed" then
        local dash = Screen:scaleBySize(6)
        local gap = Screen:scaleBySize(4)
        local stride = dash + gap
        for offset = 0, width - 1, stride do
            local w = (offset + dash <= width) and dash or (width - offset)
            bb:paintRect(x0 + offset, y, w, thickness, Blitbuffer.COLOR_BLACK)
        end
    elseif style == "dots_small" then
        local dot_size = math.max(1, Screen:scaleBySize(2))
        local gap = Screen:scaleBySize(5)
        local stride = dot_size + gap
        for offset = 0, width - 1, stride do
            bb:paintRect(x0 + offset, y, dot_size, dot_size, Blitbuffer.COLOR_BLACK)
        end
    elseif style == "dots_big" then
        local dot_size = math.max(2, Screen:scaleBySize(3.5))
        local gap = Screen:scaleBySize(7)
        local stride = dot_size + gap
        for offset = 0, width - 1, stride do
            bb:paintRect(x0 + offset, y, dot_size, dot_size, Blitbuffer.COLOR_BLACK)
        end
    elseif style == "vertical_bar" then
        local bar_h = math.max(4, Screen:scaleBySize(6))
        local bar_w = math.max(1, thickness)
        local gap = Screen:scaleBySize(8)
        local stride = bar_w + gap
        local y_bar = math.floor(y - bar_h / 2)
        for offset = 0, width - 1, stride do
            bb:paintRect(x0 + offset, y_bar, bar_w, bar_h, Blitbuffer.COLOR_BLACK)
        end
    elseif style == "slash" or style == "double_slash" or style == "custom" then
        local pattern_str
        if style == "slash" then
            pattern_str = "/  "
        elseif style == "double_slash" then
            pattern_str = "//  "
        else
            pattern_str = (custom_char or "✦") .. " "
        end
        local sample_tb = TextWidget:new{ text = pattern_str, face = font_face }
        local sample_size = sample_tb:getSize()
        if sample_size.w > 0 then
            local count = math.floor(width / sample_size.w)
            local line_text = string.rep(pattern_str, math.max(1, count))
            local tb = TextWidget:new{
                text = line_text,
                face = font_face,
                fgcolor = Blitbuffer.COLOR_BLACK,
                bgcolor = Blitbuffer.COLOR_WHITE,
            }
            local sz = tb:getSize()
            local mask = Blitbuffer.new(sz.w, sz.h, Blitbuffer.TYPE_BB8)
            mask:fill(Blitbuffer.COLOR_WHITE)
            tb:paintTo(mask, 0, 0)
            mask:invertRect(0, 0, sz.w, sz.h)
            bb:colorblitFromRGB32(mask, x0, math.floor(y - sz.h / 2), 0, 0, math.min(width, sz.w), sz.h, Blitbuffer.COLOR_BLACK)
            mask:free()
        end
    end
end

function HeaderPainter:paintTo(bb, x, y)
    if not (self.enabled and self.context) then return end
    local cfg = self.header_config
    if not cfg or cfg.enabled ~= true then return end

    local snapshot = self.context:snapshot({ chapter = true })
    local chapter = snapshot.chapter or {}
    if cfg.hide_on_chapter_start and chapter.is_start then
        return
    end

    local page_info = self.context:_page()
    local page_num = page_info and page_info.number or 1
    local page_count = self.ui and self.ui.document and safeCall(function() return self.ui.document:getPageCount() end) or 1
    local doc_props = self.ui and self.ui.doc_props

    local screen_w = Screen:getWidth()
    local h_margin = math.max(12, Screen:scaleBySize(16))
    if self.ui and self.ui.document and self.ui.document.configurable then
        local doc_h_margin = self.ui.document.configurable.h_page_margins
        if type(doc_h_margin) == "table" and doc_h_margin[1] then
            h_margin = math.max(10, doc_h_margin[1])
        elseif type(doc_h_margin) == "number" and doc_h_margin > 0 then
            h_margin = math.max(10, doc_h_margin)
        end
    end

    local font_size = math.max(9, Screen:scaleBySize(cfg.font_size or 13))
    local face = Font:getFace("cfont", font_size)
    if not face then return end

    local bold = cfg.font_bold == true
    local italic = cfg.font_italic == true

    local left_text = self:_getItemText(cfg.left, page_num, page_count, chapter, doc_props)
    local center_text = self:_getItemText(cfg.center, page_num, page_count, chapter, doc_props)
    local right_text = self:_getItemText(cfg.right, page_num, page_count, chapter, doc_props)

    local usable_w = screen_w - 2 * h_margin
    local gap = Screen:scaleBySize(12)

    -- Truncate text dynamically if slots overflow
    if center_text ~= "" then
        local center_max_w = math.floor(usable_w * 0.4)
        center_text = truncateText(center_text, center_max_w, face, bold, italic)
        local center_tb = TextWidget:new{ text = center_text, face = face, bold = bold, italic = italic }
        local center_w = center_tb:getSize().w

        local side_max_w = math.floor((usable_w - center_w - 2 * gap) / 2)
        left_text = truncateText(left_text, side_max_w, face, bold, italic)
        right_text = truncateText(right_text, side_max_w, face, bold, italic)
    else
        local side_max_w = math.floor((usable_w - gap) / 2)
        left_text = truncateText(left_text, side_max_w, face, bold, italic)
        right_text = truncateText(right_text, side_max_w, face, bold, italic)
    end

    local top_y = Screen:scaleBySize(cfg.top_offset or 12)
    local max_h = font_size

    -- Paint left slot
    if left_text ~= "" then
        local _, h = self:_paintTextAt(bb, left_text, h_margin, top_y, face, bold, italic)
        max_h = math.max(max_h, h)
    end

    -- Paint center slot
    if center_text ~= "" then
        local center_tb = TextWidget:new{ text = center_text, face = face, bold = bold, italic = italic }
        local center_w = center_tb:getSize().w
        local center_x = math.floor((screen_w - center_w) / 2)
        local _, h = self:_paintTextAt(bb, center_text, center_x, top_y, face, bold, italic)
        max_h = math.max(max_h, h)
    end

    -- Paint right slot
    if right_text ~= "" then
        local right_tb = TextWidget:new{ text = right_text, face = face, bold = bold, italic = italic }
        local right_w = right_tb:getSize().w
        local right_x = screen_w - h_margin - right_w
        local _, h = self:_paintTextAt(bb, right_text, right_x, top_y, face, bold, italic)
        max_h = math.max(max_h, h)
    end

    -- Paint divider
    local divider_style = cfg.divider_style or "solid"
    if divider_style ~= "none" then
        local pad = Screen:scaleBySize(cfg.padding_bottom or 6)
        local divider_y = top_y + max_h + pad
        local thickness = math.max(1, Screen:scaleBySize(cfg.divider_thickness or 1))
        local divider_face = Font:getFace("cfont", math.max(8, math.floor(font_size * 0.85))) or face
        self:_paintDivider(bb, divider_style, thickness, cfg.divider_custom_char, h_margin, screen_w - h_margin, divider_y, divider_face)
    end
end

return HeaderPainter
