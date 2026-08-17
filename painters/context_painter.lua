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

function ContextPainter:invalidate(reason)
    if self.context then self.context:invalidate(reason or "context_painter") end
end

local function scaledOptions(options)
    local copy = {}
    for key, value in pairs(options or {}) do copy[key] = value end
    copy.thickness = math.max(1, Screen:scaleBySize(tonumber(copy.thickness) or 1))
    return copy
end

local Font = require("ui/font")
local TextWidget = require("ui/widget/textwidget")

local function measured(perf, name, fn)
    if perf then return perf:measure(name, fn) end
    return fn()
end

local function paintRects(bb, rects, perf)
    if not rects or #rects == 0 then return end
    local color = Blitbuffer.COLOR_BLACK
    local paint_count, darken_count = 0, 0
    for _, rect in ipairs(rects) do
        if rect.tint then
            -- Blend black at low opacity so the glyphs stay readable.
            bb:darkenRect(rect.x, rect.y, rect.w, rect.h, rect.tint)
            darken_count = darken_count + 1
        else
            bb:paintRect(rect.x, rect.y, rect.w, rect.h, color)
            paint_count = paint_count + 1
        end
    end
    if perf then
        perf:mark("paint.blit.paintRect", paint_count)
        perf:mark("paint.blit.darkenRect", darken_count)
    end
end

local function paintTexts(bb, texts, perf)
    if not texts or #texts == 0 then return end
    for _, item in ipairs(texts) do
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
    if perf then perf:mark("paint.text_widgets", #texts) end
end

function ContextPainter:paintTo(bb, x, y)
    if not (self.enabled and self.context) then return end
    local perf_started = self.perf and self.perf:start()
    if self.perf then self.perf:mark("paint.context_painter.frames") end
    local chapter_options = self.awareness.chapter or {}
    local chapter_enabled = (chapter_options.start and chapter_options.start.enabled == true)
        or (chapter_options["end"] and chapter_options["end"].enabled == true)

    if chapter_enabled then
        local snapshot = self.context:snapshot({ chapter = true })
        if snapshot.chapter and (snapshot.chapter.is_start or snapshot.chapter.is_end) then
            snapshot.lines = self.context:snapshot({ line_mode = "all" }).lines
            local rects, texts = measured(self.perf, "phase.layout.chapter", function()
                return MarkLayout.chapter(snapshot, {
                    start = scaledOptions(chapter_options.start),
                    ["end"] = scaledOptions(chapter_options["end"]),
                })
            end)
            paintRects(bb, rects, self.perf)
            paintTexts(bb, texts, self.perf)
        end
    end

    local need_semantic = (self.semantic_drawing.enabled or self.dialogue_painter.enabled or self.emphasis_painter.enabled)
        and self.semantic_index ~= nil

    if need_semantic then
        local needs_structure = self.semantic_drawing.enabled or self.emphasis_painter.enabled
        local profile = self.dialogue_painter.enabled
            and (needs_structure and "full" or "dialogue") or "structure"
        local semantic_snapshot = self.semantic_index:inspect({ profile = profile })

        if self.semantic_drawing.enabled then
            local report
            if self.semantic_drawing.diagnostics then
                report = measured(self.perf, "phase.health_check.paint", function()
                    return HealthCheck.run(semantic_snapshot, self.config, nil, self.perf)
                end)
            end
            local rects = measured(self.perf, "phase.layout.semantic", function()
                return SemanticLayout.build(
                    semantic_snapshot, scaledOptions(self.semantic_drawing), report)
            end)
            paintRects(bb, rects, self.perf)
        end

        if self.dialogue_painter.enabled then
            local options = scaledOptions(self.dialogue_painter)
            local context = self.context
            if context and type(context.boxesForRange) == "function" then
                options.quote_boxes = function(node, range, text, text_origin)
                    return context:boxesForRange(node.pos0 or node.xpointer,
                        range.first, range.last, text, text_origin)
                end
            end
            local rects = measured(self.perf, "phase.layout.dialogue", function()
                return DialogueLayout.build(semantic_snapshot, options)
            end)
            paintRects(bb, rects, self.perf)
        end

        if self.emphasis_painter.enabled then
            local rects = measured(self.perf, "phase.layout.emphasis", function()
                return EmphasisLayout.build(
                    semantic_snapshot, scaledOptions(self.emphasis_painter))
            end)
            paintRects(bb, rects, self.perf)
        end
    end
    if self.perf then self.perf:finish("phase.context_painter.paint", perf_started) end
end

return ContextPainter
