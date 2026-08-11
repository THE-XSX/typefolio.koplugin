local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = Device.screen

local MARKER_DARKEN = 0.12

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
}

function Painter:setConfig(config)
    local underline = config.underline or "none"
    self.underline = UNDERLINE_ALIASES[underline] or underline
    self.dash_pattern = config.dash_pattern or "normal"
    self.line_thickness = tonumber((tostring(config.line_thickness or "1.5px"):gsub("px", ""))) or 1.5
    self.skip_headings = config.skip_headings ~= false
    self.skip_blockquotes = config.skip_blockquotes ~= false
end

function Painter:invalidate()
    if self.context then self.context:invalidate() end
end

function Painter:getLineBoxes()
    if not self.context then return {} end
    local should_skip = self.skip_headings or self.skip_blockquotes
    return self.context:snapshot({
        line_mode = should_skip and "body" or "all",
        skip_headings = self.skip_headings,
        skip_blockquotes = self.skip_blockquotes,
    }).lines or {}
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

    -- CRE line boxes use screen coordinates, matching ReaderView highlights.
    for _, box in ipairs(self:getLineBoxes()) do
        if self.underline == "marker" then
            bb:darkenRect(box.x, box.y, box.w, box.h, MARKER_DARKEN)
        else
            self:paintLine(bb, box, thickness)
        end
    end
end

return Painter
