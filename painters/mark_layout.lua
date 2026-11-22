-- SPDX-FileCopyrightText: Copyright (C) 2026 THE-XSX
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- Typefolio (文笺) - KOReader plugin
-- Released under the GNU Affero General Public License v3.0 or later.
-- See the LICENSE file in the project root for the full license text.

local MarkLayout = {}

local function addRect(rects, x, y, w, h, screen)
    x, y = math.floor(x), math.floor(y)
    w, h = math.max(1, math.floor(w)), math.max(1, math.floor(h))
    local x0, y0 = math.max(0, x), math.max(0, y)
    local x1, y1 = math.min(screen.w, x + w), math.min(screen.h, y + h)
    if x1 > x0 and y1 > y0 then
        table.insert(rects, { x = x0, y = y0, w = x1 - x0, h = y1 - y0 })
    end
end

local function lineExtents(lines, screen)
    if not lines or #lines == 0 then
        return screen.w * 0.2, screen.w * 0.8, screen.h * 0.1, screen.h * 0.9
    end
    local left, right, top, bottom = screen.w, 0, screen.h, 0
    for _, box in ipairs(lines) do
        left = math.min(left, box.x)
        right = math.max(right, box.x + box.w)
        top = math.min(top, box.y)
        bottom = math.max(bottom, box.y + box.h)
    end
    return left, right, top, bottom
end

-- Compute raw point size for Font:getFace (which applies Screen:scaleBySize internally).
-- Uses unscaled raw_thickness when supplied by ContextPainter so 300 DPI screens do not
-- double-scale chapter text symbols.
local function textPointSize(opts)
    local raw = tonumber(opts.raw_thickness) or tonumber(opts.thickness) or 1
    return math.max(12, math.min(36, math.floor(raw * 6 + 6)))
end

local function chapterDecoration(rects, texts, center, width, y, opts, screen, anchor, edge_y)
    local style = opts.style or "single"
    local thickness = tonumber(opts.thickness) or 1
    local count = math.max(1, math.min(20, tonumber(opts.count) or 5))
    local char = opts.char or "★"
    local font_size = textPointSize(opts)

    if style == "single" then
        local x = center - width / 2
        addRect(rects, x, y, width, thickness, screen)
    elseif style == "double" then
        local x = center - width / 2
        addRect(rects, x, y, width, thickness, screen)
        addRect(rects, x, y + thickness * 2, width, thickness, screen)
    elseif style == "dots" then
        local dot = math.max(thickness * 3, 5)
        local gap = dot * 2.2
        local total_w = count * dot + (count - 1) * (gap - dot)
        local start_x = center - total_w / 2
        for i = 0, count - 1 do
            addRect(rects, start_x + i * gap, y, dot, dot, screen)
        end
    elseif style == "wave" then
        local wave_str = string.rep("〰 ", count):gsub("%s+$", "")
        table.insert(texts, {
            center = center, y = y, edge_y = edge_y, anchor = anchor,
            text = wave_str, font_size = font_size,
        })
    elseif style == "heart" then
        local heart_str = string.rep("♥ ", count):gsub("%s+$", "")
        table.insert(texts, {
            center = center, y = y, edge_y = edge_y, anchor = anchor,
            text = heart_str, font_size = font_size,
        })
    elseif style == "custom" then
        local custom_str = string.rep(char .. " ", count):gsub("%s+$", "")
        table.insert(texts, {
            center = center, y = y, edge_y = edge_y, anchor = anchor,
            text = custom_str, font_size = font_size,
        })
    else
        local x = center - width / 2
        addRect(rects, x, y, width, thickness, screen)
    end
end

function MarkLayout.chapter(snapshot, options)
    local chapter = snapshot.chapter or {}
    local screen = snapshot.page.viewport
    local rects = {}
    local texts = {}
    if not (chapter.is_start or chapter.is_end) then return rects, texts end
    local left, right, top, bottom = lineExtents(snapshot.lines, screen)
    local width = math.max(24, screen.w * 0.35)
    local center = screen.w / 2
    local start_options = options.start or {}
    if chapter.is_start and start_options.enabled then
        local thickness = start_options.thickness or 1
        local style = start_options.style or "single"
        local is_text = style == "wave" or style == "heart" or style == "custom"
        local font_size = textPointSize(start_options)
        local gap = is_text and math.max(6, thickness * 4) or math.max(4, thickness * 3)
        local y, edge_y
        if is_text then
            edge_y = math.max(0, top - gap)
            y = math.max(font_size / 2, edge_y - font_size / 2)
        else
            y = math.max(0, top - gap - (style == "double" and thickness * 3 or thickness))
        end
        chapterDecoration(rects, texts, center, width, y, start_options, screen,
            is_text and "above" or nil, edge_y)
    end
    local end_options = options["end"] or {}
    if chapter.is_end and end_options.enabled then
        local thickness = end_options.thickness or 1
        local style = end_options.style or "single"
        local is_text = style == "wave" or style == "heart" or style == "custom"
        local font_size = textPointSize(end_options)
        local gap = is_text and math.max(6, thickness * 4) or math.max(4, thickness * 3)
        local y, edge_y
        if is_text then
            edge_y = math.min(screen.h, bottom + gap)
            y = math.min(screen.h - font_size / 2, edge_y + font_size / 2)
        else
            y = math.min(screen.h - thickness * 3, bottom + gap)
        end
        chapterDecoration(rects, texts, center, width, y, end_options, screen,
            is_text and "below" or nil, edge_y)
    end
    return rects, texts
end

return MarkLayout
