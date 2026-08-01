-- painter.lua
-- 直接绘制后端：把下划线/荧光笔画到帧缓冲上，不经过 CSS。
-- 由 ReaderView:registerViewModule 注册，paintTo 在正文与高亮之后被调用。
-- 注意 view_modules 是独立的哈希表，不在 WidgetContainer:propagateEvent 遍历的
-- 数组里，所以本模块收不到事件——失效由 main.lua 里的 TypeFolio 转发。

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Geom = require("ui/geometry")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = Device.screen

local MARKER_DARKEN = 0.12

-- 旧版本与预设会写入 all_lines_dashed_compat 等别名，css_templates 也做同样的归一化
local UNDERLINE_ALIASES = {
    all_lines_dashed_compat = "all_lines",
    all_lines_dashed = "all_lines",
    all_lines_solid = "all_lines",
    all_lines_dotted = "all_lines",
    thick_lines = "all_lines",
    para_dashed = "para",
    para_dotted = "para",
}

local Painter = WidgetContainer:extend{
    enabled = false,
    underline = "none",
    dash_pattern = "normal",
    line_thickness = 1.5,
    boxes = nil,
}

function Painter:setConfig(config)
    local underline = config.underline or "none"
    self.underline = UNDERLINE_ALIASES[underline] or underline
    self.dash_pattern = config.dash_pattern or "normal"
    self.line_thickness = tonumber((tostring(config.line_thickness or "1.5px"):gsub("px", ""))) or 1.5
    self.skip_headings = config.skip_headings ~= false
end

function Painter:invalidate()
    self.boxes = nil
end

-- 视口顶端的 xpointer 在 page / scroll 两种模式下都正确；双页模式一屏跨两个内部页。
-- 下界多取一页：scroll 模式下视口顶端位于页中，取到下一页起点会短一截；
-- 多取的部分反正会被裁掉，取少了却会漏画。
local function visibleRangeXPointers(document)
    local xp0 = document:getXPointer()
    if not xp0 then return nil end
    local page_step = math.max(document:getVisiblePageNumberCount() or 1, 1)
    local last_page = document:getPageCount()
    local next_page = document:getCurrentPage() + page_step + 1
    if next_page > last_page then return xp0, nil end
    return xp0, document:getPageXPointer(next_page)
end

-- 正文行高的众数。标题行字号大、行框更高，用它当筛子就能把探测次数从
-- 每行一次降到每页几次。
local function modalHeight(boxes)
    local counts, best, best_count = {}, nil, 0
    for _, box in ipairs(boxes) do
        local h = math.floor(box.h)
        counts[h] = (counts[h] or 0) + 1
        if counts[h] > best_count then best, best_count = h, counts[h] end
    end
    return best
end

-- xpointer 字符串里带标签名，形如 /body/DocFragment/body/div/p[12]/sup[3]/a[3].0
-- （见 readerlink.lua:1148）。getNearestWordFromPosition 是 cache_by_tag，
-- 不会作废页面位图，可以安全地按页调用。
local function isSkippableLine(document, box)
    local nearest = document:getNearestWordFromPosition(
        { x = box.x + 2, y = box.y + math.floor(box.h / 2) })
    local xp = nearest and nearest.pos0
    if not xp then return false end
    return xp:find("/h%d") ~= nil or xp:find("/blockquote") ~= nil
end

function Painter:getLineBoxes()
    if self.boxes then return self.boxes end

    local document = self.ui and self.ui.document
    if not document then return {} end

    local screen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    local raw
    local xp0, xp1 = visibleRangeXPointers(document)
    if xp0 and xp1 then
        raw = document:getScreenBoxesFromPositions(xp0, xp1, true)
    end
    if not raw or #raw == 0 then
        -- 末页取不到下界，或该书的 xpointer 路径失效：退回全屏取词，代价是一次整页重绘
        local text = document:getTextFromPositions(
            { x = 0, y = 0 }, { x = screen.w, y = screen.h }, true)
        raw = text and text.sboxes or {}
    end

    -- getPageXPointer 可能落在块起点而非页内首个文字节点，取回的框会越过页顶/页底，
    -- 故一律按可见区域裁剪，不假设 crengine 已经裁好
    local boxes = {}
    for _, box in ipairs(raw) do
        if box.h and box.h > 0 and box.w and box.w > 0 then
            local clipped = box:intersect(screen)
            if clipped and clipped.w > 0 and clipped.h > 0 then
                table.insert(boxes, clipped)
            end
        end
    end

    if self.skip_headings and #boxes > 0 then
        local modal = modalHeight(boxes)
        local kept = {}
        for _, box in ipairs(boxes) do
            -- 高度接近众数的直接判为正文，不探测；只有异常行才付一次查询
            local is_body = modal and math.abs(box.h - modal) <= modal * 0.1
            if is_body or not isSkippableLine(document, box) then
                table.insert(kept, box)
            end
        end
        boxes = kept
    end

    self.boxes = boxes
    return boxes
end

function Painter:paintLine(bb, box, thickness)
    local y = box.y + box.h - thickness
    if self.dash_pattern == "normal" or self.dash_pattern == "dense" then
        local dash = self.dash_pattern == "dense" and Screen:scaleBySize(2) or Screen:scaleBySize(6)
        local gap = self.dash_pattern == "dense" and Screen:scaleBySize(2) or Screen:scaleBySize(4)
        local stride = dash + gap
        for offset = 0, box.w - 1, stride do
            bb:paintRect(box.x + offset, y, math.min(dash, box.w - offset),
                thickness, Blitbuffer.COLOR_BLACK)
        end
    else
        bb:paintRect(box.x, y, box.w, thickness, Blitbuffer.COLOR_BLACK)
    end
end

function Painter:paintTo(bb, x, y)
    if not self.enabled then return end
    if self.underline ~= "all_lines" and self.underline ~= "marker" then return end

    local thickness = math.max(1, Screen:scaleBySize(
        self.dash_pattern == "thick" and math.max(self.line_thickness, 2.5) or self.line_thickness))

    -- CRE 的行框已是屏幕坐标，与 ReaderView:drawHighlightRect 一样忽略传入的 x/y
    for _, box in ipairs(self:getLineBoxes()) do
        if self.underline == "marker" then
            bb:darkenRect(box.x, box.y, box.w, box.h, MARKER_DARKEN)
        else
            self:paintLine(bb, box, thickness)
        end
    end
end

return Painter
