-- SPDX-FileCopyrightText: Copyright (C) 2026 THE-XSX
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- Typefolio (文笺) - KOReader plugin
-- Released under the GNU Affero General Public License v3.0 or later.
-- See the LICENSE file in the project root for the full license text.

-- painters/status_bar_helper.lua
-- Typefolio Shared Status Bar & Header/Footer Helper
-- Owns slot resolution, divider drawing and the whole bar layout so header_painter
-- and footer_painter stay thin wrappers (they used to hold 95% identical bodies,
-- which is how the slot-id vocabularies drifted apart in the first place).
--
-- Blitbuffer note: only paintRect / paintBorder / colorblitFrom* exist. There is no
-- fillRect and no drawRect on a KOReader blitbuffer -- calling them raises, and
-- ReaderView calls paintTo() without pcall, so it takes the whole reader down.
--
-- TextWidget note: paintTo() blits glyph bitmaps and never fills a background, so it
-- can draw straight onto the reader buffer. The old BB8 "mask" dance (alloc + invert +
-- colorblitFromRGB32 per slot) was both broken and ~3 buffer allocs per page turn.

local item_path = debug.getinfo(1, "S").source:sub(2)
local PLUGIN_ROOT = item_path:match("(.*[/\\]typefolio%.koplugin[/\\])")
    or item_path:match("(.*[/\\])painters[/\\]")
    or item_path:match("(.*[/\\])")
    or "plugins/typefolio.koplugin/"

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local TextWidget = require("ui/widget/textwidget")
local Screen = Device.screen
local Config = dofile(PLUGIN_ROOT .. "core/config.lua")

local StatusBarHelper = {}
StatusBarHelper.__index = StatusBarHelper

-- Ids saved before the vocabularies were unified. Config.normalize translates these on
-- the way in, so the painter sees a legacy id only when it is handed a config table that
-- never went through normalize. Read from Config rather than re-listed here: a second
-- copy of an alias table is how the vocabularies drifted in the first place.
local SLOT_ALIASES = Config.STATUS_SLOT_ALIASES
local DIVIDER_ALIASES = Config.STATUS_DIVIDER_ALIASES

function StatusBarHelper.new()
    local self = setmetatable({}, StatusBarHelper)
    self.toc_cache = nil
    return self
end

function StatusBarHelper.safeCall(fn)
    local ok, res = pcall(fn)
    if ok then return res end
    return nil
end

local function safeCall(fn)
    local ok, res = pcall(fn)
    if ok then return res end
    return nil
end

function StatusBarHelper.canonicalSlot(id)
    if type(id) ~= "string" then return "none" end
    return SLOT_ALIASES[id] or id
end

function StatusBarHelper.canonicalDivider(id)
    if type(id) ~= "string" then return "none" end
    return DIVIDER_ALIASES[id] or id
end

function StatusBarHelper.formatClock(is_12h)
    if is_12h then
        local hour = tonumber(os.date("%H")) or 0
        local min_str = os.date("%M")
        local is_pm = hour >= 12
        local h12 = hour % 12
        if h12 == 0 then h12 = 12 end
        local prefix = is_pm and "下午" or "上午"
        return string.format("%s%d:%s", prefix, h12, min_str)
    else
        return os.date("%H:%M")
    end
end

function StatusBarHelper.getBatteryInfo(ui)
    local cap = nil
    local is_charging = false
    local is_charged = false
    -- Match KOReader's ReaderFooter: getPowerDevice() is the public route, while
    -- Device.powerd keeps this compatible with older devices and the test harness.
    local powerd = safeCall(function() return Device:getPowerDevice() end) or Device.powerd
    if powerd then
        cap = safeCall(function() return powerd:getCapacity() end)
        is_charging = safeCall(function() return powerd:isCharging() end) or false
        is_charged = safeCall(function() return powerd:isCharged() end) or false
    end
    if not cap and ui and ui.battery_capacity then
        cap = ui.battery_capacity
    end
    local percent = tonumber(cap) or 100
    percent = math.max(0, math.min(100, percent))
    local symbol = powerd and safeCall(function()
        return powerd:getBatterySymbol(is_charged, is_charging, percent)
    end)
    -- getBatterySymbol is available in current KOReader, but this is also KOReader's
    -- bundled battery-prefix glyph, so older builds still show an icon instead of
    -- silently falling back to a bare percentage.
    if type(symbol) ~= "string" or symbol == "" then symbol = "" end
    return {
        percent = percent,
        is_charging = is_charging,
        is_charged = is_charged,
        symbol = symbol,
        text = string.format("%s%d%%", symbol, percent),
    }
end

-- Chapter tick positions as 0..1 fractions of the book, for the progress-bar divider.
-- ReaderToc:getTocTicksFlattened() already returns a flat, deduplicated, sorted page
-- list and caches it, so this is one native call on a cache miss and zero afterwards.
function StatusBarHelper:getChapterTicks(ui, total_pages)
    if not ui or not total_pages or total_pages <= 0 then return {} end
    if self.toc_cache and self.toc_cache.total_pages == total_pages then
        return self.toc_cache.ticks
    end

    local ticks = {}
    local toc = ui.toc
    if toc then
        local pages = safeCall(function() return toc:getTocTicksFlattened() end)
        if type(pages) == "table" then
            local last_pct = -1
            for _, page in ipairs(pages) do
                if type(page) == "number" and page > 1 and page <= total_pages then
                    local pct = page / total_pages
                    -- Drop ticks closer than half a percent: on a 1000px bar they
                    -- would land on the same column anyway.
                    if pct - last_pct >= 0.005 then
                        ticks[#ticks + 1] = pct
                        last_pct = pct
                    end
                end
            end
        end
    end

    self.toc_cache = {
        total_pages = total_pages,
        ticks = ticks,
    }
    return ticks
end

function StatusBarHelper.invalidateTocCache(self)
    if self then self.toc_cache = nil end
end

-- Pages left in the current chapter. ReaderToc:getChapterPagesLeft returns nil in the
-- last chapter (there is no next chapter to count towards), which is the signal the
-- caller needs to switch to the book-level number.
function StatusBarHelper.getChapterPagesLeft(ui, page_num)
    if not (ui and ui.toc) then return nil end
    local left = safeCall(function() return ui.toc:getChapterPagesLeft(page_num) end)
    if type(left) == "number" and left >= 0 then return left end
    return nil
end

function StatusBarHelper.getBookPagesLeft(ui, page_num, total_pages)
    if ui and ui.document then
        local left = safeCall(function() return ui.document:getTotalPagesLeft(page_num) end)
        if type(left) == "number" and left >= 0 then return left end
    end
    if type(total_pages) == "number" and type(page_num) == "number" and total_pages > page_num then
        return total_pages - page_num
    end
    return nil
end

-- Time estimates come from the statistics plugin, which already knows the reader's
-- real average page time and formats the duration per the user's duration_format.
-- It returns nil when statistics are disabled or no average exists yet.
local function timeForPages(ui, pages)
    if not (ui and ui.statistics and type(pages) == "number" and pages > 0) then return nil end
    local text = safeCall(function() return ui.statistics:getTimeForPages(pages) end)
    if type(text) == "string" and text ~= "" then return text end
    return nil
end

function StatusBarHelper.getChapterRemainingInfo(ui, page_num)
    local pages_left = StatusBarHelper.getChapterPagesLeft(ui, page_num)
    local time_text = timeForPages(ui, pages_left)

    local formatted
    if time_text then
        formatted = string.format("本章还剩 %s", time_text)
    elseif pages_left and pages_left > 0 then
        formatted = string.format("本章还剩 %d 页", pages_left)
    else
        formatted = "本章最后一页"
    end

    return {
        pages_left = pages_left,
        time_text = time_text,
        formatted = formatted,
    }
end

function StatusBarHelper.getBookRemainingInfo(ui, page_num, total_pages)
    local pages_left = StatusBarHelper.getBookPagesLeft(ui, page_num, total_pages)
    local time_text = timeForPages(ui, pages_left)

    local formatted
    if time_text then
        formatted = string.format("预计 %s 后读完", time_text)
    elseif pages_left and pages_left > 0 then
        formatted = string.format("全书还剩 %d 页", pages_left)
    else
        formatted = "即将读完"
    end

    return {
        pages_left = pages_left,
        time_text = time_text,
        formatted = formatted,
    }
end

-- Horizontal page margins, in screen pixels, so the bar can line up with the text
-- block. document.configurable.h_page_margins is {left, right} in unscaled units.
function StatusBarHelper.getEffectiveMargins(ui)
    local default_margin = Screen:scaleBySize(20)
    local left_margin, right_margin = default_margin, default_margin
    local configurable = ui and ui.document and ui.document.configurable
    local h_margins = configurable and configurable.h_page_margins
    if type(h_margins) == "table" then
        if type(h_margins[1]) == "number" then
            left_margin = Screen:scaleBySize(h_margins[1])
        end
        if type(h_margins[2]) == "number" then
            right_margin = Screen:scaleBySize(h_margins[2])
        end
    end
    return left_margin, right_margin
end

local function docTitle(ui, fallback)
    if ui and ui.doc_props and type(ui.doc_props.title) == "string" and ui.doc_props.title ~= "" then
        return ui.doc_props.title
    end
    return fallback
end

-- One resolver per canonical slot id. Config.STATUS_SLOTS is the vocabulary;
-- tests/status_bar_spec.lua fails if an id there has no entry here.
local SLOT_RESOLVERS = {
    none = function() return "" end,

    chapter_title = function(ctx)
        local ui = ctx.ui
        if ui and ui.toc then
            local title = safeCall(function() return ui.toc:getTocTitleByPage(ctx.page_num) end)
            if type(title) == "string" and title ~= "" then return title end
        end
        -- Fall back to the cached BookContext chapter before giving up on a title.
        if ctx.book_context then
            local snapshot = safeCall(function()
                return ctx.book_context:snapshot({ chapter = true })
            end)
            local title = snapshot and snapshot.chapter and snapshot.chapter.title
            if type(title) == "string" and title ~= "" then return title end
        end
        return string.format("第 %d 页", ctx.page_num)
    end,

    book_title = function(ctx) return docTitle(ctx.ui, "书籍正文") end,

    author = function(ctx)
        local ui = ctx.ui
        if ui and ui.doc_props and type(ui.doc_props.authors) == "string" and ui.doc_props.authors ~= "" then
            return ui.doc_props.authors
        end
        return ""
    end,

    clock = function() return StatusBarHelper.formatClock(false) end,

    clock_12h = function() return StatusBarHelper.formatClock(true) end,

    battery = function(ctx) return StatusBarHelper.getBatteryInfo(ctx.ui).text end,

    time_battery = function(ctx)
        return string.format("%s · %s",
            StatusBarHelper.formatClock(false),
            StatusBarHelper.getBatteryInfo(ctx.ui).text)
    end,

    battery_time = function(ctx)
        return string.format("%s  %s",
            StatusBarHelper.getBatteryInfo(ctx.ui).text,
            StatusBarHelper.formatClock(false))
    end,

    reading_percent = function(ctx) return string.format("%d%%", ctx.percent) end,

    page_progress = function(ctx)
        return string.format("%d / %d", ctx.page_num, ctx.total_pages)
    end,

    page_progress_cn = function(ctx)
        return string.format("%d 之 %d", ctx.page_num, ctx.total_pages)
    end,

    progress_combo = function(ctx)
        return string.format("%d%% · %d/%d", ctx.percent, ctx.page_num, ctx.total_pages)
    end,

    progress_combo_cn = function(ctx)
        return string.format("%d%% · %d 之 %d", ctx.percent, ctx.page_num, ctx.total_pages)
    end,

    pages_left_chapter = function(ctx)
        local pages_left = StatusBarHelper.getChapterPagesLeft(ctx.ui, ctx.page_num)
        if pages_left and pages_left > 0 then
            return string.format("本章还剩 %d 页", pages_left)
        end
        return "本章最后一页"
    end,

    time_left_chapter = function(ctx)
        return StatusBarHelper.getChapterRemainingInfo(ctx.ui, ctx.page_num).formatted
    end,

    time_left_book = function(ctx)
        return StatusBarHelper.getBookRemainingInfo(ctx.ui, ctx.page_num, ctx.total_pages).formatted
    end,

    time_left_book_pages = function(ctx)
        local info = StatusBarHelper.getBookRemainingInfo(ctx.ui, ctx.page_num, ctx.total_pages)
        return string.format("%s   %d/%d", info.formatted, ctx.page_num, ctx.total_pages)
    end,

    book_title_page_progress_cn = function(ctx)
        return string.format("%s · %d 之 %d", docTitle(ctx.ui, "正文"), ctx.page_num, ctx.total_pages)
    end,

    custom_text = function(ctx) return ctx.custom_text or "" end,
}

StatusBarHelper.SLOT_RESOLVERS = SLOT_RESOLVERS

function StatusBarHelper.resolveSlotText(slot_type, ctx)
    local id = StatusBarHelper.canonicalSlot(slot_type)
    local resolver = SLOT_RESOLVERS[id]
    if not resolver then return "" end

    local page_num = ctx.page_num or 1
    local total_pages = math.max(1, ctx.total_pages or 1)
    local resolved = {
        ui = ctx.ui,
        page_num = page_num,
        total_pages = total_pages,
        book_context = ctx.book_context,
        custom_text = ctx.custom_text or "",
        percent = math.max(0, math.min(100, math.floor((page_num / total_pages) * 100))),
    }

    local text = resolver(resolved)
    return type(text) == "string" and text or ""
end

-- Builds a TextWidget that truncates natively at max_width (one measure pass in C
-- instead of one TextWidget per popped character). Caller must :free() it.
local function makeTextWidget(text, face, bold, max_w)
    return TextWidget:new{
        text = text,
        face = face,
        bold = bold,
        max_width = max_w,
        truncate_with_ellipsis = true,
    }
end

StatusBarHelper.makeTextWidget = makeTextWidget

function StatusBarHelper.paintText(bb, text, x, y, max_w, align, face, bold)
    if not text or text == "" or not max_w or max_w <= 0 then return 0 end

    local widget = makeTextWidget(text, face, bold, max_w)
    local size = widget:getSize()
    local draw_x = x
    if align == "center" then
        draw_x = x + math.floor((max_w - size.w) / 2)
    elseif align == "right" then
        draw_x = x + max_w - size.w
    end

    -- Straight onto the reader buffer: TextWidget only blits glyph coverage, it does
    -- not paint a background, so nothing behind the text gets erased.
    widget:paintTo(bb, draw_x, y)
    local height = size.h
    widget:free()
    return height
end

local function paintDots(bb, x, y, width, gap, size)
    for px = x, x + width - size, gap do
        bb:paintRect(px, y, size, size, Blitbuffer.COLOR_BLACK)
    end
end

-- One painter per canonical divider id, keyed the same way as Config.STATUS_DIVIDERS.
local DIVIDER_PAINTERS = {
    none = function() end,

    solid = function(bb, o)
        bb:paintRect(o.x, o.y, o.width, o.thickness, Blitbuffer.COLOR_BLACK)
    end,

    dashed = function(bb, o)
        local dash_len = Screen:scaleBySize(6)
        local gap_len = Screen:scaleBySize(4)
        local cur_x = o.x
        local right = o.x + o.width
        while cur_x < right do
            local draw_len = math.min(dash_len, right - cur_x)
            bb:paintRect(cur_x, o.y, draw_len, o.thickness, Blitbuffer.COLOR_BLACK)
            cur_x = cur_x + dash_len + gap_len
        end
    end,

    dots_small = function(bb, o)
        paintDots(bb, o.x, o.y, o.width, Screen:scaleBySize(4), o.thickness)
    end,

    dots_big = function(bb, o)
        local size = math.max(o.thickness, Screen:scaleBySize(2))
        paintDots(bb, o.x, o.y, o.width, Screen:scaleBySize(8), size)
    end,

    vertical_bar = function(bb, o)
        local bar_len = math.max(o.thickness, Screen:scaleBySize(4))
        local gap = Screen:scaleBySize(6)
        for px = o.x, o.x + o.width - o.thickness, gap do
            bb:paintRect(px, o.y, o.thickness, bar_len, Blitbuffer.COLOR_BLACK)
        end
    end,

    slash = function(bb, o)
        local step = math.max(1, o.thickness)
        local gap = Screen:scaleBySize(8)
        for px = o.x, o.x + o.width - 3 * step, gap do
            bb:paintRect(px, o.y + 2 * step, step, step, Blitbuffer.COLOR_BLACK)
            bb:paintRect(px + step, o.y + step, step, step, Blitbuffer.COLOR_BLACK)
            bb:paintRect(px + 2 * step, o.y, step, step, Blitbuffer.COLOR_BLACK)
        end
    end,

    double_slash = function(bb, o)
        local step = math.max(1, o.thickness)
        local gap = Screen:scaleBySize(10)
        for px = o.x, o.x + o.width - 6 * step, gap do
            for pair = 0, 1 do
                local base = px + pair * 3 * step
                bb:paintRect(base, o.y + 2 * step, step, step, Blitbuffer.COLOR_BLACK)
                bb:paintRect(base + step, o.y + step, step, step, Blitbuffer.COLOR_BLACK)
                bb:paintRect(base + 2 * step, o.y, step, step, Blitbuffer.COLOR_BLACK)
            end
        end
    end,

    progress_bar = function(bb, o)
        local bar_h = math.max(1, o.thickness)
        -- Dotted background track.
        paintDots(bb, o.x, o.y, o.width, Screen:scaleBySize(3), 1)

        local pct = math.max(0, math.min(1, o.progress or 0))
        local active_w = math.floor(o.width * pct)
        if active_w > 0 then
            bb:paintRect(o.x, o.y, active_w, bar_h, Blitbuffer.COLOR_BLACK)
        end

        if type(o.chapter_ticks) == "table" and #o.chapter_ticks > 0 then
            local tick_h = bar_h + Screen:scaleBySize(3)
            local tick_y = math.max(0, o.y - 1)
            for _, tick_pct in ipairs(o.chapter_ticks) do
                if tick_pct > 0.01 and tick_pct < 0.99 then
                    local tick_x = o.x + math.floor(o.width * tick_pct)
                    bb:paintRect(tick_x, tick_y, 1, tick_h, Blitbuffer.COLOR_BLACK)
                end
            end
        end
    end,

    custom = function(bb, o)
        local symbol = o.custom_symbol
        if type(symbol) ~= "string" or symbol == "" then return end
        -- 9 raw, because getFace scales it. The repeat count needs the device-pixel
        -- advance instead, hence the separate scaled estimate.
        local face = Font:getFace("cfont", 9)
        if not face then return end
        local advance = math.max(1, Screen:scaleBySize(9))
        -- Over-repeat by one, then let max_width clip: the glyph advance is unknown
        -- here, so the alternative is a measure pass per repetition.
        local repeats = math.max(1, math.floor(o.width / advance) + 1)
        local widget = makeTextWidget(string.rep(symbol .. " ", repeats), face, false, o.width)
        widget:paintTo(bb, o.x, o.y)
        widget:free()
    end,
}

StatusBarHelper.DIVIDER_PAINTERS = DIVIDER_PAINTERS

function StatusBarHelper.paintDivider(bb, divider_type, x, y, width, thickness, progress, custom_symbol, chapter_ticks)
    local id = StatusBarHelper.canonicalDivider(divider_type)
    if id == "none" or not width or width <= 0 then return end
    local painter = DIVIDER_PAINTERS[id]
    if not painter then return end

    painter(bb, {
        x = x,
        y = y,
        width = width,
        thickness = math.max(1, thickness or 1),
        progress = progress,
        custom_symbol = custom_symbol,
        chapter_ticks = chapter_ticks,
    })
end

-- Shared layout for both bars. opts.position is "top" or "bottom"; everything else
-- comes from the normalized custom_header / custom_footer config table.
--
-- Per page turn this costs: 3 TextWidget builds (one per non-empty slot, each
-- truncating natively), 3 paintTo blits, and one divider pass. No intermediate
-- buffers are allocated.
function StatusBarHelper:paintBar(bb, opts)
    local cfg = opts.config or {}
    local ui = opts.ui
    local page_num = opts.page_num or 1
    local page_count = math.max(1, opts.page_count or 1)

    -- Raw point size, not a scaled one: Font:getFace() calls Screen:scaleBySize() on its
    -- size argument itself. Pre-scaling it scaled twice -- ~1.8x each on a 300 DPI panel,
    -- so a configured 12 became roughly 38 device px -- which is why the bar collided with
    -- the body text and why the slot budgets truncated far earlier than the layout meant
    -- them to. KOReader's own footer passes its text_font_size the same way, unscaled.
    local face = Font:getFace("cfont", cfg.font_size or 12)
    if not face then return end
    local bold = cfg.font_bold == true

    local h_margin = Screen:scaleBySize(16)
    if cfg.margin_inset ~= false then
        local left_m, right_m = StatusBarHelper.getEffectiveMargins(ui)
        h_margin = math.max(Screen:scaleBySize(12), math.min(left_m, right_m))
    end

    local screen_w = Screen:getWidth()
    local usable_w = screen_w - 2 * h_margin
    if usable_w <= 0 then return end

    local ctx = {
        ui = ui,
        page_num = page_num,
        total_pages = page_count,
        book_context = opts.book_context,
        custom_text = cfg.custom_text or "",
    }

    local left_slot, center_slot, right_slot = cfg.left, cfg.center, cfg.right
    -- Facing pages: mirror the outer/inner slots on odd pages like a printed book.
    if cfg.facing_pages == true and (page_num % 2 == 1) then
        left_slot, right_slot = right_slot, left_slot
    end

    local left_text = StatusBarHelper.resolveSlotText(left_slot, ctx)
    local center_text = StatusBarHelper.resolveSlotText(center_slot, ctx)
    local right_text = StatusBarHelper.resolveSlotText(right_slot, ctx)

    local gap = Screen:scaleBySize(12)
    local side_max_w, center_max_w
    if center_text ~= "" then
        center_max_w = math.floor(usable_w * 0.44)
        side_max_w = math.floor((usable_w - center_max_w - 2 * gap) / 2)
    else
        side_max_w = math.floor((usable_w - gap) / 2)
    end
    if side_max_w < 1 then side_max_w = 0 end

    -- Text height comes from the widget, not from the font size: a 13pt face is
    -- taller than 13px once ascender and padding are included, and using the font
    -- size put the divider through the descenders.
    local text_h = 0
    local probe = makeTextWidget("Ag", face, bold, usable_w)
    text_h = probe:getSize().h
    probe:free()

    local text_y
    if opts.position == "bottom" then
        local bottom_offset = Screen:scaleBySize(cfg.bottom_offset or 12)
        text_y = Screen:getHeight() - bottom_offset - text_h
    else
        text_y = Screen:scaleBySize(cfg.top_offset or 12)
    end
    if text_y < 0 then text_y = 0 end

    -- Each column gets both its own budget and its own origin, because paintText aligns
    -- within [x, x + max_w]: handing it the right width at the wrong x only moves the
    -- collision. Passing usable_w let a long chapter title grow to the full bar and
    -- centre itself on the bar rather than in its column; passing h_margin as the right
    -- column's origin put the right slot's right edge at h_margin + side_max_w, i.e. in
    -- the left half of the bar, directly on top of the left slot. TextWidget blits only
    -- glyph coverage, so either way the result is superimposed text, not a truncation.
    local left_x = h_margin
    local center_x = h_margin + math.floor((usable_w - (center_max_w or 0)) / 2)
    local right_x = h_margin + usable_w - side_max_w

    StatusBarHelper.paintText(bb, left_text, left_x, text_y, side_max_w, "left", face, bold)
    if center_text ~= "" then
        StatusBarHelper.paintText(bb, center_text, center_x, text_y, center_max_w, "center", face, bold)
    end
    StatusBarHelper.paintText(bb, right_text, right_x, text_y, side_max_w, "right", face, bold)

    local divider_style = StatusBarHelper.canonicalDivider(cfg.divider_style or "none")
    if divider_style ~= "none" then
        local thickness = math.max(1, Screen:scaleBySize(cfg.divider_thickness or 1))
        local divider_y
        local divider_position = cfg.divider_position or "auto"
        if divider_position == "below" then
            divider_y = text_y + text_h + Screen:scaleBySize(
                opts.position == "bottom" and (cfg.padding_top or 6)
                    or (cfg.padding_bottom or 6))
        elseif divider_position == "above" then
            divider_y = text_y - Screen:scaleBySize(
                opts.position == "bottom" and (cfg.padding_top or 6)
                    or (cfg.padding_bottom or 6)) - thickness
        elseif opts.position == "bottom" then
            divider_y = text_y - Screen:scaleBySize(cfg.padding_top or 6) - thickness
        else
            divider_y = text_y + text_h + Screen:scaleBySize(cfg.padding_bottom or 6)
        end
        if divider_y < 0 then divider_y = 0 end

        local chapter_ticks = nil
        if divider_style == "progress_bar" and cfg.chapter_ticks ~= false then
            chapter_ticks = self:getChapterTicks(ui, page_count)
        end

        StatusBarHelper.paintDivider(
            bb,
            divider_style,
            h_margin,
            divider_y,
            usable_w,
            thickness,
            page_num / page_count,
            cfg.divider_custom_char,
            chapter_ticks
        )
    end
end

-- Kept for the spec: the vocabularies the painter answers to must equal the ones
-- Config can persist, or a menu entry silently paints nothing.
function StatusBarHelper.knownSlots()
    return Config.STATUS_SLOTS
end

function StatusBarHelper.knownDividers()
    return Config.STATUS_DIVIDERS
end

return StatusBarHelper
