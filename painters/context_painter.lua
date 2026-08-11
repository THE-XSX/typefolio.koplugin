local item_path = debug.getinfo(1, "S").source:sub(2)
local PLUGIN_ROOT = item_path:match("(.*[/\\]typefolio%.koplugin[/\\])") or item_path:match("(.*[/\\])") or "plugins/typefolio.koplugin/"
local MarkLayout = dofile(PLUGIN_ROOT .. "painters/mark_layout.lua")
local HealthCheck = dofile(PLUGIN_ROOT .. "tools/health_check.lua")
local SemanticLayout = dofile(PLUGIN_ROOT .. "painters/semantic_layout.lua")
local DialogueLayout = dofile(PLUGIN_ROOT .. "painters/dialogue_layout.lua")
local EmphasisLayout = dofile(PLUGIN_ROOT .. "painters/emphasis_layout.lua")

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = Device.screen

local ContextPainter = WidgetContainer:extend{
    enabled = false,
}

function ContextPainter:setConfig(config)
    self.awareness = config.awareness or {}
    self.semantic_drawing = config.semantic_drawing or {}
    self.dialogue_painter = config.dialogue_painter or {}
    self.emphasis_painter = config.emphasis_painter or {}
    self.config = config
    local chapter = self.awareness.chapter or {}
    self.enabled = chapter.start and chapter.start.enabled == true
        or chapter["end"] and chapter["end"].enabled == true
        or self.semantic_drawing.enabled == true
        or self.dialogue_painter.enabled == true
        or self.emphasis_painter.enabled == true
end

function ContextPainter:invalidate()
    if self.context then self.context:invalidate() end
end

local function scaledOptions(options)
    local copy = {}
    for key, value in pairs(options or {}) do copy[key] = value end
    copy.thickness = math.max(1, Screen:scaleBySize(tonumber(copy.thickness) or 1))
    return copy
end

local Font = require("ui/font")
local TextWidget = require("ui/widget/textwidget")

local function paintRects(bb, rects)
    for _, rect in ipairs(rects) do
        if rect.tint then
            -- Blend black at low opacity so the glyphs stay readable.
            bb:darkenRect(rect.x, rect.y, rect.w, rect.h, rect.tint)
        else
            bb:paintRect(rect.x, rect.y, rect.w, rect.h, Blitbuffer.COLOR_BLACK)
        end
    end
end

local function paintTexts(bb, texts)
    for _, item in ipairs(texts or {}) do
        local face = Font:getFace("cfont", item.font_size or 16)
        if face then
            local tb = TextWidget:new{
                text = item.text,
                face = face,
                fgcolor = Blitbuffer.COLOR_BLACK,
                bgcolor = Blitbuffer.COLOR_WHITE,
            }
            local size = tb:getSize()
            local x = math.floor(item.center - size.w / 2)
            local y = math.floor(item.y - size.h / 2)

            local mask = Blitbuffer.new(size.w, size.h, Blitbuffer.TYPE_BB8)
            mask:fill(Blitbuffer.COLOR_WHITE)
            tb:paintTo(mask, 0, 0)
            mask:invertRect(0, 0, size.w, size.h)
            bb:colorblitFromRGB32(mask, math.max(0, x), math.max(0, y), 0, 0, size.w, size.h, Blitbuffer.COLOR_BLACK)
            mask:free()
        end
    end
end

function ContextPainter:paintTo(bb, x, y)
    if not (self.enabled and self.context) then return end
    local chapter_options = self.awareness.chapter or {}
    local snapshot = self.context:snapshot({
        chapter = chapter_options.start and chapter_options.start.enabled == true
            or chapter_options["end"] and chapter_options["end"].enabled == true,
    })

    if snapshot.chapter
            and (snapshot.chapter.is_start or snapshot.chapter.is_end) then
        snapshot.lines = self.context:snapshot({ line_mode = "all" }).lines
        local rects, texts = MarkLayout.chapter(snapshot, {
            start = scaledOptions(chapter_options.start),
            ["end"] = scaledOptions(chapter_options["end"]),
        })
        paintRects(bb, rects)
        paintTexts(bb, texts)
    end
    if self.semantic_drawing.enabled and self.semantic_index then
        local semantic_snapshot = self.semantic_index:inspect()
        local report
        if self.semantic_drawing.diagnostics then
            report = HealthCheck.run(semantic_snapshot, self.config)
        end
        paintRects(bb, SemanticLayout.build(
            semantic_snapshot, scaledOptions(self.semantic_drawing), report))
    end
    if self.dialogue_painter.enabled and self.semantic_index then
        local semantic_snapshot = self.semantic_index:inspect()
        local options = scaledOptions(self.dialogue_painter)
        -- Lets the layout ask for the screen boxes of one quoted run. Costs a
        -- single engine call per quote (a page holds a handful) and only runs
        -- while this painter is enabled.
        local context = self.context
        if context and type(context.boxesForRange) == "function" then
            options.quote_boxes = function(node, range, text)
                -- node.xpointer is the nearest-word position (mid-line); the
                -- line-start pos0 is the correct base for the range offsets.
                return context:boxesForRange(node.pos0 or node.xpointer, range.first, range.last, text)
            end
        end
        paintRects(bb, DialogueLayout.build(semantic_snapshot, options))
    end
    if self.emphasis_painter.enabled and self.semantic_index then
        local semantic_snapshot = self.semantic_index:inspect()
        paintRects(bb, EmphasisLayout.build(
            semantic_snapshot, scaledOptions(self.emphasis_painter)))
    end
end

return ContextPainter
