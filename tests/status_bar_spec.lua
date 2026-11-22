-- SPDX-FileCopyrightText: Copyright (C) 2026 THE-XSX
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- Typefolio (文笺) - KOReader plugin
-- Released under the GNU Affero General Public License v3.0 or later.
-- See the LICENSE file in the project root for the full license text.

-- The status bars, driven against a blitbuffer that refuses to invent methods.
--
-- Why this spec exists: the header and footer painters called bb:fillRect(), which is not
-- a KOReader blitbuffer method. ReaderView calls paintTo() without pcall, so enabling
-- either bar took the whole reader down on the next page turn -- and nothing in the suite
-- noticed, because no test had ever painted a bar. A stub that silently accepts every
-- method name would not have noticed either, so the fake buffer here is built from the
-- method set of the real ffi/blitbuffer.lua and raises on anything else.
--
-- Three kinds of check, cheapest first:
--   1. Vocabulary parity. Config.STATUS_* is the single source of truth; the painter's
--      resolver/painter tables and both menus' label tables must cover it exactly.
--   2. A static sweep of every painter for blitbuffer calls that do not exist. This is
--      the one that catches a fillRect anywhere in the tree, not just on a path a test
--      happens to walk.
--   3. Actually painting: every slot id, every divider id, both bars, at the edges of
--      every numeric range, asserting the bar stays on screen and frees its widgets.
--
-- Run from the plugin root:
--   python3 runlua.py <plugin_dir> tests/status_bar_spec.lua --lua 51

local function pluginRoot()
    local here = debug.getinfo(1, "S").source:sub(2)
    local root = here:match("^(.*[/\\])tests[/\\][^/\\]*$")
    if root and root:find("typefolio%.koplugin") then return root end
    return "../typefolio.koplugin/"
end
local ROOT = pluginRoot()

local checks, failures = 0, 0
local function check(label, ok)
    checks = checks + 1
    if ok then
        print("ok " .. label)
    else
        failures = failures + 1
        print("FAIL " .. label)
    end
end

-- ---------------------------------------------------------------- the real method set
--
-- Scraped from ffi/blitbuffer.lua when a KOReader tree is reachable: on the device the
-- plugin sits at koreader/plugins/<name>.koplugin/, and this repo keeps a Kobo build
-- beside the plugins. Falling back to a pinned list keeps the spec runnable anywhere,
-- with the version it was pinned from named so a future reader can re-derive it.
local PINNED_BB_METHODS = [[
addblitFrom adjustSaturation alphablitFrom blendRectRGB32 blitDefault blitFrom
checkCoordinates colorblitFrom colorblitFromRGB32 copy darkenRect ditheralphablitFrom
ditherblitFrom ditherpmulalphablitFrom fill free getAllocated getBoundedRect
getBufferData getHeight getInverse getPhysicalCoordinates getPhysicalRect getPixel
getPixelP getRotation getType getWidth hatchRect invert invertRect invertblitFrom
isRGB lightenRect multiplyRectRGB paintBorder paintBorderRGB32 paintCircle
paintInnerBorder paintRect paintRectRGB32 paintRoundedCorner paintRoundedRect
paintRoundedRectRGB32 pmulalphablitFrom progressBar rotate rotateAbsolute rotatedCopy
scale setAllocated setInverse setPixel setPixelAdd setPixelBlend setPixelClamped
setPixelColorize setPixelColorizeRGB32 setPixelInverted setPixelMultiply
setPixelPmulBlend setRotation setType viewport writeBMP writeJPG writePNGFromBGR
writeToFile
]]

-- Whole file or nil. Some of the invariants here are about the source itself -- a method
-- name, a bound written as a literal -- and cannot be reached through the module's API.
local function readFile(path)
    local fh = io.open(path, "r")
    if not fh then return nil end
    local source = fh:read("*a")
    fh:close()
    return source
end

local function scrapeBlitbufferMethods()
    local candidates = {
        ROOT .. "../../ffi/blitbuffer.lua",                              -- on the device
        ROOT .. "../koreader-kobo-v2026.07/koreader/ffi/blitbuffer.lua", -- this repo
    }
    for _, path in ipairs(candidates) do
        local fh = io.open(path, "r")
        if fh then
            local source = fh:read("*a")
            fh:close()
            local names, count = {}, 0
            for name in source:gmatch("\nfunction BB_mt%.__index:([%w_]+)") do
                names[name] = true
                count = count + 1
            end
            if count > 20 then return names, path, count end
        end
    end
    local names, count = {}, 0
    for name in PINNED_BB_METHODS:gmatch("[%w_]+") do
        names[name] = true
        count = count + 1
    end
    return names, "pinned list (KOReader Kobo v2026.07)", count
end

local BB_METHODS, BB_SOURCE, BB_COUNT = scrapeBlitbufferMethods()
print(string.format("-- blitbuffer method set: %d names from %s", BB_COUNT, BB_SOURCE))
check("the blitbuffer method set was found", BB_COUNT > 20)
-- The two that started this: neither has ever existed, and both were being called.
check("fillRect is not a blitbuffer method", BB_METHODS.fillRect == nil)
check("drawRect is not a blitbuffer method", BB_METHODS.drawRect == nil)
check("paintRect is a blitbuffer method", BB_METHODS.paintRect == true)

-- --------------------------------------------------------- 2. static sweep of painters
--
-- Every call on a buffer-shaped receiver in the plugin, checked against the set above.
-- The receiver names are a convention, not a type: `bb` (and anything ending in _bb) is
-- the buffer handed to paintTo, `mask` is an intermediate buffer. A new name for a buffer
-- local would slip past this, which is what the paint-time checks below are for.
local RECEIVERS = { "[%w_]*bb", "mask" }
local SOURCES = {
    "painters/status_bar_helper.lua", "painters/header_painter.lua",
    "painters/footer_painter.lua", "painters/context_painter.lua",
    "painters/painter.lua", "painters/mark_layout.lua",
    "painters/semantic_layout.lua", "painters/dialogue_layout.lua",
    "painters/emphasis_layout.lua",
}
local swept, bad_calls = 0, {}
for _, relative in ipairs(SOURCES) do
    local fh = io.open(ROOT .. relative, "r")
    if fh then
        local source = fh:read("*a")
        fh:close()
        for _, receiver in ipairs(RECEIVERS) do
            for name, method in source:gmatch("([%w_]*)%f[%w_]" .. receiver .. "%s*:%s*([%w_]+)%s*%(") do
                swept = swept + 1
                if not BB_METHODS[method] then
                    table.insert(bad_calls, string.format("%s calls %s()", relative, method))
                end
            end
        end
    end
end
check(string.format("the sweep found buffer calls to check (%d)", swept), swept > 0)
check("no painter calls a blitbuffer method that does not exist"
    .. (#bad_calls > 0 and ": " .. table.concat(bad_calls, ", ") or ""),
    #bad_calls == 0)

-- ------------------------------------------------------------------ KOReader stand-ins
local paint_log, widget_log

local strict_bb_mt = {
    __index = function(_, key)
        error(string.format("blitbuffer has no method or field %q", tostring(key)), 2)
    end,
}

local function newBB(w, h)
    local bb = {
        w = w, h = h,
        getWidth = function(self) return self.w end,
        getHeight = function(self) return self.h end,
        free = function() end,
        fill = function() end,
        invertRect = function() end,
    }
    local function record(kind)
        return function(_, x, y, rw, rh)
            table.insert(paint_log, { kind = kind, x = x, y = y, w = rw, h = rh })
        end
    end
    bb.paintRect = record("paintRect")
    bb.darkenRect = record("darkenRect")
    bb.colorblitFromRGB32 = function(_, _, x, y, _, _, rw, rh)
        table.insert(paint_log, { kind = "colorblit", x = x, y = y, w = rw, h = rh })
    end
    return setmetatable(bb, strict_bb_mt)
end

local SCREEN_W, SCREEN_H = 1072, 1448

package.preload["ffi/blitbuffer"] = function()
    return {
        COLOR_BLACK = "black",
        COLOR_WHITE = "white",
        TYPE_BB8 = 1,
        new = function(w, h) return newBB(w, h) end,
    }
end

package.preload["device"] = function()
    return {
        screen = {
            getWidth = function() return SCREEN_W end,
            getHeight = function() return SCREEN_H end,
            -- The real one scales by DPI; 1:1 keeps the arithmetic checkable by hand.
            scaleBySize = function(_, size) return math.floor(size or 0) end,
        },
        powerd = {
            getCapacity = function() return 62 end,
            isCharging = function() return false end,
            isCharged = function() return false end,
            getBatterySymbol = function(_, _, _, capacity)
                return capacity >= 50 and "BATTERY_ICON" or "LOW_BATTERY_ICON"
            end,
        },
    }
end

package.preload["ui/font"] = function()
    return { getFace = function(_, name, size) return { name = name, size = size } end }
end

-- Enough of a TextWidget to measure and blit: a fixed advance per UTF-8 character, and
-- max_width truncation, because the layout depends on getSize() and on the widget
-- respecting the width it was given.
package.preload["ui/widget/textwidget"] = function()
    local TextWidget = {}
    function TextWidget:new(o)
        o = o or {}
        local advance = math.max(1, math.floor((o.size or (o.face and o.face.size) or 12) * 0.9))
        local chars = 0
        for _ in tostring(o.text or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
            chars = chars + 1
        end
        local width = chars * advance
        if o.max_width and width > o.max_width then width = o.max_width end
        o.freed = false
        o.getSize = function() return { w = width, h = advance + 4 } end
        o.paintTo = function(self, bb, x, y)
            local size = self.getSize()
            table.insert(paint_log, { kind = "text", x = x, y = y, w = size.w, h = size.h,
                text = tostring(o.text or "") })
            -- The real TextWidget blits glyph coverage; touching the buffer here proves
            -- the painter handed over something buffer-shaped.
            bb:getWidth()
        end
        o.free = function(self) self.freed = true end
        table.insert(widget_log, o)
        return o
    end
    return TextWidget
end

package.preload["ui/widget/container/widgetcontainer"] = function()
    local Widget = {}
    function Widget:extend(subclass)
        subclass = subclass or {}
        subclass.__index = subclass
        return setmetatable(subclass, { __index = self })
    end
    function Widget:new(instance)
        instance = self:extend(instance)
        if instance.init then instance:init() end
        return instance
    end
    return Widget
end

package.preload["ui/event"] = function() return { new = function() return {} end } end
package.preload["ui/uimanager"] = function()
    return { show = function() end, close = function() end, setDirty = function() end }
end
package.preload["ui/widget/inputdialog"] = function() return { new = function() return {} end } end
package.preload["ui/widget/spinwidget"] = function() return { new = function() return {} end } end

local Config = dofile(ROOT .. "core/config.lua")
local StatusBarHelper = dofile(ROOT .. "painters/status_bar_helper.lua")
local StatusBarMenu = dofile(ROOT .. "settings/status_bar_menu.lua")
local HeaderPainter = dofile(ROOT .. "painters/header_painter.lua")
local FooterPainter = dofile(ROOT .. "painters/footer_painter.lua")

-- ------------------------------------------------------------- 1. vocabulary parity
local function setOf(list)
    local set = {}
    for _, id in ipairs(list) do set[id] = true end
    return set
end

local function coversExactly(label, list, keyed, exceptions)
    local set = setOf(list)
    local missing, extra = {}, {}
    for _, id in ipairs(list) do
        if keyed[id] == nil and not (exceptions and exceptions[id]) then
            table.insert(missing, id)
        end
    end
    for id in pairs(keyed) do
        if not set[id] then table.insert(extra, id) end
    end
    table.sort(missing)
    table.sort(extra)
    check(label .. " covers every id"
        .. (#missing > 0 and " (missing: " .. table.concat(missing, ", ") .. ")" or ""),
        #missing == 0)
    check(label .. " has no id of its own"
        .. (#extra > 0 and " (extra: " .. table.concat(extra, ", ") .. ")" or ""),
        #extra == 0)
end

coversExactly("the painter's slot resolvers", Config.STATUS_SLOTS, StatusBarHelper.SLOT_RESOLVERS)
coversExactly("the menu's slot labels", Config.STATUS_SLOTS, StatusBarMenu.labelledSlots())
coversExactly("the painter's divider painters", Config.STATUS_DIVIDERS, StatusBarHelper.DIVIDER_PAINTERS)
coversExactly("the menu's divider labels", Config.STATUS_DIVIDERS, StatusBarMenu.labelledDividers())
-- "custom" is the sentinel for "the reader edited the slots by hand", so it is a valid
-- persisted value with no menu row of its own.
coversExactly("the menu's presets", Config.STATUS_PRESETS, StatusBarMenu.labelledPresets(),
    { custom = true })

-- Compared element by element, not by identity: every module dofile()s core/config.lua
-- for itself, so each one holds its own copy of these lists.
local function sameList(a, b)
    if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

check("knownSlots is the Config vocabulary",
    sameList(StatusBarHelper.knownSlots(), Config.STATUS_SLOTS))
check("knownDividers is the Config vocabulary",
    sameList(StatusBarHelper.knownDividers(), Config.STATUS_DIVIDERS))

-- A preset that names a slot the painter cannot draw is a blank bar with no error.
local slot_set = setOf(Config.STATUS_SLOTS)
local divider_set = setOf(Config.STATUS_DIVIDERS)
local preset_ids = {}
for id in pairs(StatusBarMenu.labelledPresets()) do table.insert(preset_ids, id) end
table.sort(preset_ids)
for _, id in ipairs(preset_ids) do
    local preset = StatusBarMenu.labelledPresets()[id]
    check(id .. ": has a name", type(preset.name) == "string" and preset.name ~= "")
    for _, half_name in ipairs({ "header", "footer" }) do
        local half = preset[half_name]
        check(string.format("%s: describes the %s", id, half_name), type(half) == "table")
        if type(half) == "table" then
            for _, slot in ipairs({ "left", "center", "right" }) do
                check(string.format("%s.%s.%s = %s is a real slot", id, half_name, slot,
                    tostring(half[slot])), slot_set[half[slot]] == true)
            end
            check(string.format("%s.%s.divider_style = %s is a real divider", id, half_name,
                tostring(half.divider_style)), divider_set[half.divider_style] == true)
        end
    end
end

-- Keep the built-in menu intentional: layouts that merely have similar names may
-- still differ in enabled state, slots, divider style, or divider placement. Only an
-- exact match of both halves is a duplicate and should be removed rather than exposed
-- as two choices.
do
    local signatures = {}
    local duplicate_count = 0
    local function halfSignature(half)
        return table.concat({
            tostring(half.enabled), half.left, half.center, half.right,
            half.divider_style, half.divider_position or "auto",
        }, "\31")
    end
    for _, id in ipairs(preset_ids) do
        local preset = StatusBarMenu.labelledPresets()[id]
        local signature = halfSignature(preset.header) .. "\30" .. halfSignature(preset.footer)
        if signatures[signature] then duplicate_count = duplicate_count + 1 end
        signatures[signature] = id
    end
    check("built-in presets contain no exact duplicate layouts", duplicate_count == 0)
end

-- A status-bar preset is one object with two halves. Applying it from the combined menu
-- must write the same preset id to both bars and honour each half's enabled state.
for _, id in ipairs(preset_ids) do
    local config = Config.defaults()
    local applied
    local ctx = {
        ui = {},
        getConfig = function() return Config.clone(config) end,
        applyStyle = function(next_config) applied = Config.normalize(next_config) end,
    }
    StatusBarMenu.applyPreset(ctx, "custom_header", id)
    local preset = StatusBarMenu.labelledPresets()[id]
    check(id .. ": preset id is synchronized",
        applied.custom_header.preset == id and applied.custom_footer.preset == id)
    check(id .. ": header half is applied",
        applied.custom_header.enabled == preset.header.enabled
            and applied.custom_header.left == preset.header.left
            and applied.custom_header.center == preset.header.center
            and applied.custom_header.right == preset.header.right
            and applied.custom_header.divider_style == preset.header.divider_style)
    check(id .. ": footer half is applied",
        applied.custom_footer.enabled == preset.footer.enabled
            and applied.custom_footer.left == preset.footer.left
            and applied.custom_footer.center == preset.footer.center
            and applied.custom_footer.right == preset.footer.right
            and applied.custom_footer.divider_style == preset.footer.divider_style)
    check(id .. ": shipped header has no divider",
        preset.header.divider_style == "none")
end

do
    local combined = StatusBarMenu.combinedItems({ tr = function(s) return s end })
    check("header and footer share one top-level submenu", #combined == 4)
    check("the shared submenu lists presets once", combined[1].text == "Layout presets")
    check("the shared submenu keeps a header detail menu", combined[2].text == "Custom top header")
    check("the shared submenu keeps a footer detail menu", combined[3].text == "Custom bottom footer")
    check("the shared submenu has disable system bars toggle",
        type(combined[4].text_func) == "function" and combined[4].help_text ~= nil)
end

do
    local kobo = StatusBarMenu.labelledPresets().classic_folio
    check("Kobo Native uses a centered chapter header",
        kobo.name == "Kobo Native (Centered chapter · Book and page · Progress bar)"
            and kobo.header.center == "chapter_title"
            and kobo.header.left == "none"
            and kobo.header.right == "none")
    check("Kobo Native uses centered book/page footer with progress bar",
        kobo.footer.center == "book_title_page_progress_cn"
            and kobo.footer.left == "none"
            and kobo.footer.right == "none"
            and kobo.footer.divider_style == "progress_bar"
            and kobo.footer.divider_position == "below")
end

do
    local kindle = StatusBarMenu.labelledPresets().wechat_duokan
    check("Kindle Native uses centered 12h time",
        kindle.name == "Kindle Native (Centered 12h time · Chapter time · Percent)"
            and kindle.header.center == "clock_12h"
            and kindle.header.left == "none"
            and kindle.header.right == "none")
    check("Kindle Native uses chapter time and percent footer",
        kindle.footer.left == "time_left_chapter"
            and kindle.footer.right == "reading_percent"
            and kindle.footer.center == "none")
end

do
    local presets = StatusBarMenu.labelledPresets()
    local ireader = presets.ireader
    check("iReader mirrors book/chapter header and three-part footer",
        ireader.header.left == "book_title"
            and ireader.header.right == "chapter_title"
            and ireader.header.divider_style == "none"
            and ireader.footer.left == "clock"
            and ireader.footer.center == "time_left_book"
            and ireader.footer.right == "page_progress")

    local hanvon = presets.hanvon
    check("Hanvon uses battery before time and pages on the right",
        hanvon.header.left == "chapter_title"
            and hanvon.footer.left == "battery_time"
            and hanvon.footer.right == "page_progress")

    local boox = presets.boox
    check("BOOX combines book/chapter/time status and bottom percent",
        boox.header.left == "book_title"
            and boox.header.center == "chapter_title"
            and boox.header.right == "time_battery"
            and boox.footer.left == "chapter_title"
            and boox.footer.right == "reading_percent")

    local weread = presets.wechat_reading
    check("WeRead keeps only chapter and bottom-right pages",
        weread.header.left == "chapter_title"
            and weread.header.center == "none"
            and weread.header.right == "none"
            and weread.footer.left == "none"
            and weread.footer.center == "none"
            and weread.footer.right == "page_progress")
end

-- Ids saved by older builds. Two halves to this, and the first half was missing: the
-- painter's alias tables only fire for a config that never went through normalize, and
-- every config that reaches a painter has (getConfig normalizes, engine:apply
-- normalizes). So an old saved setting was not translated -- it failed the oneOf() check
-- in normalize and came back as the *default*, silently discarding the layout the reader
-- had chosen. normalize has to translate first, and the painter keeps the tables as the
-- fallback for a hand-built config.
for _, pair in ipairs({
    { "chapter", "chapter_title" }, { "clock_battery", "time_battery" },
    { "progress_percent", "reading_percent" }, { "pages_left_in_chapter", "pages_left_chapter" },
}) do
    check("legacy slot id " .. pair[1] .. " maps to " .. pair[2],
        StatusBarHelper.canonicalSlot(pair[1]) == pair[2]
            and StatusBarHelper.SLOT_RESOLVERS[pair[2]] ~= nil)
    for _, bar in ipairs({ "custom_header", "custom_footer" }) do
        for _, place in ipairs({ "left", "center", "right" }) do
    local normalized = Config.normalize{ [bar] = { [place] = pair[1] } }
            check(string.format("normalize keeps a saved %s.%s = %s as %s", bar, place,
                pair[1], pair[2]), normalized[bar][place] == pair[2])
        end
    end
end

for _, position in ipairs({ "auto", "above", "below" }) do
    for _, bar in ipairs({ "custom_header", "custom_footer" }) do
        check(bar .. " accepts divider position " .. position,
            Config.normalize{ [bar] = { divider_position = position } }[bar].divider_position
                == position)
    end
end
check("unknown divider position falls back to auto",
    Config.normalize{ custom_footer = { divider_position = "sideways" } }
        .custom_footer.divider_position == "auto")
for _, pair in ipairs({
    { "bars", "solid" }, { "slashes", "dashed" }, { "double_slashes", "dashed" },
    { "dots_big", "dots_small" }, { "vertical_bar", "solid" }, { "slash", "dashed" },
}) do
    check("legacy divider id " .. pair[1] .. " maps to " .. pair[2],
        StatusBarHelper.canonicalDivider(pair[1]) == pair[2]
            and StatusBarHelper.DIVIDER_PAINTERS[pair[2]] ~= nil)
    for _, bar in ipairs({ "custom_header", "custom_footer" }) do
        local normalized = Config.normalize{ [bar] = { divider_style = pair[1] } }
        check(string.format("normalize keeps a saved %s.divider_style = %s as %s", bar,
            pair[1], pair[2]), normalized[bar].divider_style == pair[2])
    end
end
-- The alias tables are one table, read from Config by the painter. Element-wise, because
-- the spec dofile()s Config separately from the painter.
check("the painter did not keep its own copy of the slot aliases",
    StatusBarHelper.canonicalSlot("chapter") == Config.STATUS_SLOT_ALIASES.chapter)
check("the painter did not keep its own copy of the divider aliases",
    StatusBarHelper.canonicalDivider("bars") == Config.STATUS_DIVIDER_ALIASES.bars)
-- An id that is not an alias and not current still has to fall back, not leak through.
check("an unknown saved slot id falls back to the default",
    Config.normalize{ custom_header = { left = "no_such_slot" } }.custom_header.left
        == "chapter_title")
check("an unknown saved divider id falls back to the default",
    Config.normalize{ custom_footer = { divider_style = "no_such_divider" } }
        .custom_footer.divider_style == "none")
check("an unknown slot id resolves to empty text rather than raising",
    StatusBarHelper.resolveSlotText("no_such_slot", { page_num = 1, total_pages = 10 }) == "")

-- Divider thickness: one bound, and the spin row must not offer a value normalize will
-- not keep. It offered 4; normalize took 1..3 and replaced anything else with the
-- *default*, so the thickest divider in the menu produced the thinnest on screen.
local THICK_MAX = Config.STATUS_DIVIDER_THICKNESS_MAX
check("there is a divider thickness bound to derive from", type(THICK_MAX) == "number")
for _, bar in ipairs({ "custom_header", "custom_footer" }) do
    for value = 1, THICK_MAX do
        check(string.format("%s keeps divider thickness %d", bar, value),
            Config.normalize{ [bar] = { divider_thickness = value } }[bar].divider_thickness
                == value)
    end
    -- Clamped, not reset: someone who already picked 4 from the old spin row should get
    -- the thickest rule that exists, not the thinnest.
    check(string.format("%s clamps divider thickness %d to %d", bar, THICK_MAX + 1, THICK_MAX),
        Config.normalize{ [bar] = { divider_thickness = THICK_MAX + 1 } }[bar].divider_thickness
            == THICK_MAX)
    check(string.format("%s rejects a fractional divider thickness", bar),
        Config.normalize{ [bar] = { divider_thickness = 1.5 } }[bar].divider_thickness == 1)
end
do
    -- Source-level, because a spin row's bound is captured in a closure and cannot be
    -- read back off the menu item. The literal is what drifted; assert it is gone -- not
    -- just the one that caused "pick the thickest divider, get the thinnest", but every
    -- bare upper bound, since each is a second copy of a number normalize enforces and
    -- resets against. The lower bounds stay literal: they are all 0 or 1 and normalize
    -- has no constant for them.
    local menu_src = readFile(ROOT .. "settings/status_bar_menu.lua") or ""
    check("the divider thickness spin row derives its bound from Config",
        menu_src:find("max = Config.STATUS_DIVIDER_THICKNESS_MAX", 1, true) ~= nil)
    check("no bare divider thickness literal is left in the menu",
        menu_src:find("max = 4", 1, true) == nil)
    local literals = {}
    for value in menu_src:gmatch("max = (%d+)") do table.insert(literals, value) end
    check("every spin row upper bound comes from Config, not a literal ("
        .. table.concat(literals, ", ") .. ")", #literals == 0)
    -- And the constants the rows now read really are the ones normalize enforces.
    for _, bar in ipairs({ "custom_header", "custom_footer" }) do
        local offset_key = bar == "custom_header" and "top_offset" or "bottom_offset"
        local padding_key = bar == "custom_header" and "padding_bottom" or "padding_top"
        check(string.format("%s accepts %s at STATUS_OFFSET_MAX", bar, offset_key),
            Config.normalize{ [bar] = { [offset_key] = Config.STATUS_OFFSET_MAX } }[bar][offset_key]
                == Config.STATUS_OFFSET_MAX)
        check(string.format("%s accepts %s at STATUS_PADDING_MAX", bar, padding_key),
            Config.normalize{ [bar] = { [padding_key] = Config.STATUS_PADDING_MAX } }[bar][padding_key]
                == Config.STATUS_PADDING_MAX)
    end
end

-- ------------------------------------------------------------------- 3. painting
local function fakeUI()
    return {
        document = {
            configurable = { h_page_margins = { 20, 20 } },
            getPageCount = function() return 319 end,
            getTotalPagesLeft = function(_, page) return 319 - page end,
        },
        doc_props = { title = "浮生六记 · 卷一 闲情记趣", authors = "沈复" },
        toc = {
            getTocTitleByPage = function(_, page) return "第 " .. tostring(page) .. " 章" end,
            getChapterPagesLeft = function() return 7 end,
            getTocTicksFlattened = function() return { 1, 30, 31, 120, 260, 400 } end,
        },
        statistics = { getTimeForPages = function() return "9分" end },
    }
end

local function fakeContext(is_start)
    return {
        snapshot = function()
            return {
                chapter = { title = "第一章 记趣", is_start = is_start == true },
                page = { number = 42 },
            }
        end,
    }
end

-- One painted bar: returns what landed on the buffer, or the error if it raised.
local function paintBar(position, overrides)
    paint_log, widget_log = {}, {}
    local bar = position == "top" and "custom_header" or "custom_footer"
    local config = Config.normalize{ [bar] = overrides }
    local helper = StatusBarHelper.new()
    local bb = newBB(SCREEN_W, SCREEN_H)
    local ok, err = pcall(function()
        helper:paintBar(bb, {
            position = position,
            config = config[bar],
            ui = fakeUI(),
            book_context = fakeContext(),
            page_num = 42,
            page_count = 319,
        })
    end)
    return ok, err, paint_log, widget_log
end

local function allFreed(widgets)
    for _, widget in ipairs(widgets) do
        if not widget.freed then return false end
    end
    return #widgets > 0
end

local function insideScreen(log)
    for _, op in ipairs(log) do
        local x, y = op.x or 0, op.y or 0
        local w, h = op.w or 0, op.h or 0
        if x < 0 or y < 0 or x + w > SCREEN_W or y + h > SCREEN_H then
            return false, string.format("%s at %d,%d %dx%d", op.kind, x, y, w, h)
        end
    end
    return true
end

-- Every slot in every position: the slot that raises is the one nobody ever painted.
for _, position in ipairs({ "top", "bottom" }) do
    for _, slot in ipairs(Config.STATUS_SLOTS) do
        for _, place in ipairs({ "left", "center", "right" }) do
            local ok, err, log, widgets = paintBar(position, {
                enabled = true, [place] = slot, custom_text = "自定义",
                divider_style = "solid",
            })
            check(string.format("%s bar paints %s in the %s slot (%s)", position, slot, place,
                tostring(err)), ok)
            if ok then
                local fits, offender = insideScreen(log)
                check(string.format("%s bar keeps %s/%s on screen (%s)", position, slot, place,
                    tostring(offender)), fits)
                check(string.format("%s bar frees its widgets after %s/%s", position, slot, place),
                    allFreed(widgets))
            end
        end
    end
end

-- Kobo's native progress track sits below its centered footer text. Bottom dividers
-- default above the text, so this checks the preset-specific geometry rather than only
-- checking that the configuration flag survived normalization.
do
    local kobo = StatusBarMenu.labelledPresets().classic_folio
    local overrides = Config.clone(kobo.footer)
    overrides.chapter_ticks = false
    local ok, err, log = paintBar("bottom", overrides)
    local text_bottom, divider_top = 0, SCREEN_H
    for _, op in ipairs(log) do
        if op.kind == "text" then
            text_bottom = math.max(text_bottom, op.y + op.h)
        else
            divider_top = math.min(divider_top, op.y)
        end
    end
    check("Kobo Native footer paints with its progress track below the text ("
        .. tostring(err) .. ")", ok and divider_top >= text_bottom)
end

-- Every slot resolves to a string, and every slot that promises content produces some.
local ctx = { ui = fakeUI(), page_num = 42, total_pages = 319, custom_text = "自定义",
    book_context = fakeContext() }
do
    local battery = StatusBarHelper.getBatteryInfo(ctx.ui)
    check("battery output reuses KOReader's dynamic icon",
        battery.symbol == "BATTERY_ICON" and battery.text == "BATTERY_ICON62%")
    check("battery slot includes the KOReader icon",
        StatusBarHelper.resolveSlotText("battery", ctx) == "BATTERY_ICON62%")
    check("battery/time combination includes the KOReader icon",
        StatusBarHelper.resolveSlotText("battery_time", ctx):find("BATTERY_ICON62%", 1, true)
            ~= nil)
end
for _, slot in ipairs(Config.STATUS_SLOTS) do
    local text = StatusBarHelper.resolveSlotText(slot, ctx)
    check(slot .. " resolves to a string", type(text) == "string")
    if slot ~= "none" then
        check(slot .. " resolves to something to show (" .. tostring(text) .. ")", text ~= "")
    end
end

-- Every divider, including the ones that paint by repeating a glyph.
for _, position in ipairs({ "top", "bottom" }) do
    for _, divider in ipairs(Config.STATUS_DIVIDERS) do
        for thickness = 1, 3 do
            local ok, err, log, widgets = paintBar(position, {
                enabled = true, left = "chapter_title", right = "reading_percent",
                divider_style = divider, divider_thickness = thickness,
                divider_custom_char = "✦", chapter_ticks = true,
            })
            check(string.format("%s bar paints the %s divider at %dpx (%s)", position, divider,
                thickness, tostring(err)), ok)
            if ok then
                local fits, offender = insideScreen(log)
                check(string.format("%s bar keeps the %s divider on screen (%s)", position,
                    divider, tostring(offender)), fits)
                check(string.format("%s bar frees its widgets with the %s divider", position,
                    divider), allFreed(widgets))
                if divider ~= "none" then
                    -- A divider that draws nothing is a menu row with no effect.
                    local marks = 0
                    for _, op in ipairs(log) do
                        if op.kind ~= "text" or op.text == "✦ " or (op.text or ""):find("✦") then
                            marks = marks + 1
                        end
                    end
                    check(string.format("%s bar's %s divider marks the buffer", position,
                        divider), marks > 0)
                end
            end
        end
    end
end

-- The numeric edges, where an off-by-one puts the bar off the screen or under the text.
local EDGES = {
    { label = "smallest font", font_size = Config.STATUS_FONT_MIN },
    { label = "largest font", font_size = Config.STATUS_FONT_MAX },
    { label = "no offset", top_offset = 0, bottom_offset = 0 },
    { label = "largest offset", top_offset = 60, bottom_offset = 60 },
    { label = "no gap", padding_top = 0, padding_bottom = 0 },
    { label = "largest gap", padding_top = 30, padding_bottom = 30 },
    { label = "no margin inset", margin_inset = false },
    { label = "facing pages", facing_pages = true },
}
for _, position in ipairs({ "top", "bottom" }) do
    for _, edge in ipairs(EDGES) do
        local overrides = { enabled = true, left = "chapter_title", center = "book_title",
            right = "time_battery", divider_style = "progress_bar" }
        for key, value in pairs(edge) do
            if key ~= "label" then overrides[key] = value end
        end
        local ok, err, log = paintBar(position, overrides)
        check(string.format("%s bar paints with the %s (%s)", position, edge.label,
            tostring(err)), ok)
        if ok then
            local fits, offender = insideScreen(log)
            check(string.format("%s bar stays on screen with the %s (%s)", position, edge.label,
                tostring(offender)), fits)
        end
    end
end

-- A one-page book: page_num / page_count is 1, and every "pages left" answer is zero.
local ok_single, err_single = paintBar("bottom", {
    enabled = true, left = "pages_left_chapter", center = "page_progress",
    right = "time_left_book", divider_style = "progress_bar",
})
check("the bottom bar paints a single-page book (" .. tostring(err_single) .. ")", ok_single)

-- Three columns, and they have to stay three. The center slot was painted with the whole
-- usable width instead of its own 44% budget, and centered inside that width -- so a long
-- chapter title grew to the full bar and its left edge landed exactly on the left slot's.
-- TextWidget blits only glyph coverage, so nothing erases anything: the two strings come
-- out superimposed. The shipped `classic` preset (book title | chapter title | pages) hits
-- this with any long chapter title, which on Chinese web fiction is most of them.
do
    -- Long enough to exceed the whole bar, which is the point: the widget truncates to
    -- whatever max_width it was handed, so a center slot given usable_w comes back the
    -- full width of the bar with its left edge on the left slot's.
    local LONG = "第一百二十三章 " .. ("又是很长的章节标题"):rep(12)
    for _, position in ipairs({ "top", "bottom" }) do
        local _, err, log = paintBar(position, {
            enabled = true, left = "book_title", center = "custom_text", right = "page_progress",
            custom_text = LONG, divider_style = "none",
        })
        local texts = {}
        for _, op in ipairs(log) do
            if op.kind == "text" then table.insert(texts, op) end
        end
        check(string.format("%s bar paints all three slots with a long center (%s)", position,
            tostring(err)), #texts == 3)
        table.sort(texts, function(a, b) return a.x < b.x end)
        local overlap
        for i = 1, #texts - 1 do
            if texts[i].x + texts[i].w > texts[i + 1].x then
                overlap = string.format("%q ends at %d, %q starts at %d", texts[i].text,
                    texts[i].x + texts[i].w, texts[i + 1].text, texts[i + 1].x)
            end
        end
        check(string.format("%s bar's slots do not overlap (%s)", position,
            tostring(overlap)), overlap == nil)
        -- And the center column is still centered on the bar, not on its own budget:
        -- clamping the width without moving the origin would just shift the collision.
        local center_op
        for _, op in ipairs(texts) do
            if op.text == LONG then center_op = op end
        end
        if center_op then
            local off = math.abs((center_op.x + center_op.w / 2) - SCREEN_W / 2)
            check(string.format("%s bar's center column is centered on the screen (off by %d)",
                position, off), off <= 2)
        end
    end
end

-- ------------------------------------------------- the painters ReaderView actually calls
local function paintPainter(painter_module, bar, overrides, context)
    paint_log, widget_log = {}, {}
    local painter = painter_module:new{ ui = fakeUI() }
    painter.context = context or fakeContext()
    painter:setConfig(Config.normalize{ [bar] = overrides })
    local bb = newBB(SCREEN_W, SCREEN_H)
    local ok, err = pcall(function() painter:paintTo(bb, 0, 0) end)
    return ok, err, paint_log
end

for _, entry in ipairs({
    { module = HeaderPainter, bar = "custom_header", label = "header painter" },
    { module = FooterPainter, bar = "custom_footer", label = "footer painter" },
}) do
    local ok, err, log = paintPainter(entry.module, entry.bar, {
        enabled = true, left = "chapter_title", center = "none", right = "time_battery",
        divider_style = "solid",
    })
    check(entry.label .. " paints when enabled (" .. tostring(err) .. ")", ok)
    check(entry.label .. " actually drew something", #log > 0)

    local off_ok, off_err, off_log = paintPainter(entry.module, entry.bar, { enabled = false })
    check(entry.label .. " draws nothing when disabled (" .. tostring(off_err) .. ")",
        off_ok and #off_log == 0)

    -- hide_on_chapter_start is the one config key the painters read for themselves.
    local hidden_ok, hidden_err, hidden_log = paintPainter(entry.module, entry.bar, {
        enabled = true, left = "chapter_title", hide_on_chapter_start = true,
    }, fakeContext(true))
    check(entry.label .. " hides on a chapter start when asked (" .. tostring(hidden_err) .. ")",
        hidden_ok and #hidden_log == 0)

    local shown_ok, shown_err, shown_log = paintPainter(entry.module, entry.bar, {
        enabled = true, left = "chapter_title", hide_on_chapter_start = false,
    }, fakeContext(true))
    check(entry.label .. " draws on a chapter start when not asked to hide ("
        .. tostring(shown_err) .. ")", shown_ok and #shown_log > 0)
end

-- The cost claim in the header of status_bar_helper.lua: three text blits and one divider
-- pass per page turn, no intermediate buffers. Worth pinning, because the version this
-- replaced allocated a buffer per slot.
local _, _, cost_log = paintBar("top", {
    enabled = true, left = "chapter_title", center = "book_title", right = "time_battery",
    divider_style = "solid",
})
local text_ops, blit_ops = 0, 0
for _, op in ipairs(cost_log) do
    if op.kind == "text" then text_ops = text_ops + 1
    elseif op.kind == "colorblit" then blit_ops = blit_ops + 1 end
end
check(string.format("a full bar costs 3 text blits, not more (%d)", text_ops), text_ops == 3)
check("a full bar allocates no intermediate buffer", blit_ops == 0)

-- ------------------------------------------------------- the three column origins
--
-- paintText aligns within [x, x + max_w], so a column handed the right width at the wrong
-- origin still lands in the wrong third of the bar. The right slot was drawn from
-- h_margin, which put its right edge at h_margin + side_max_w -- the middle of the bar --
-- and stacked it straight onto the left slot, which is the same defect the center column
-- had one line above it. The numbers here are exact rather than approximate because
-- paintText right-aligns flush against its column's end, so the two side insets are the
-- two margins.
do
    local LONG_LEFT = ("很长的书名"):rep(10)
    local RIGHT_SLOT = "reading_percent"
    local right_text = StatusBarHelper.resolveSlotText(RIGHT_SLOT, ctx)
    check("the right slot's text is distinguishable from the left slot's",
        right_text ~= "" and right_text ~= LONG_LEFT)

    for _, position in ipairs({ "top", "bottom" }) do
        for _, center in ipairs({ "none", "chapter_title" }) do
            local _, err, log = paintBar(position, {
                enabled = true, left = "custom_text", center = center, right = RIGHT_SLOT,
                custom_text = LONG_LEFT, divider_style = "none",
            })
            local left_op, right_op
            for _, op in ipairs(log) do
                if op.kind == "text" then
                    if op.text == LONG_LEFT then left_op = op
                    elseif op.text == right_text then right_op = op end
                end
            end
            local label = string.format("%s bar (center=%s)", position, center)
            check(string.format("%s: both side slots are painted (%s)", label, tostring(err)),
                left_op ~= nil and right_op ~= nil)
            if left_op and right_op then
                local left_inset = left_op.x
                local right_inset = SCREEN_W - (right_op.x + right_op.w)
                check(string.format("%s: the right slot is inset from the right edge as far as"
                    .. " the left slot is from the left (%d vs %d)", label, left_inset,
                    right_inset), left_inset == right_inset)
                check(string.format("%s: the right slot is in the right half of the bar (x=%d)",
                    label, right_op.x), right_op.x > SCREEN_W / 2)
                -- The collision itself: the left slot is long enough to fill its column,
                -- so if the right column starts inside it the two overlap.
                check(string.format("%s: a column-filling left slot does not reach the right"
                    .. " slot (ends %d, right starts %d)", label, left_op.x + left_op.w,
                    right_op.x), left_op.x + left_op.w <= right_op.x)
            end
        end
    end
end

-- --------------------------------------------------------- point sizes reach Font raw
--
-- Font:getFace() runs Screen:scaleBySize() on the size it is handed (KOReader's
-- frontend/ui/font.lua), so a caller that pre-scales scales twice -- about 1.8x each on a
-- 300 DPI panel, turning a configured 12 into roughly 38 device px. That is why the bar
-- ran into the body text and why the slot budgets truncated far earlier than the layout
-- intended. KOReader tags the raw literals it passes with "unscaled_size_check"; this is
-- the same rule. Checked at the source because the harness stubs scaleBySize 1:1 and
-- therefore cannot see a double scale at all.
do
    for _, rel in ipairs({
        "painters/status_bar_helper.lua",
        "painters/header_painter.lua",
        "painters/footer_painter.lua",
        "painters/context_painter.lua",
    }) do
        local src = readFile(ROOT .. rel) or ""
        check(rel .. " is readable", src ~= "")
        local scaled = {}
        -- Stops at the first ")" on the line, which is inside a scaleBySize call when
        -- there is one and after the size argument when there is not.
        for args in src:gmatch("getFace%(([^)\n]*)") do
            if args:find("scaleBySize", 1, true) then table.insert(scaled, args) end
        end
        check(string.format("%s hands Font:getFace raw point sizes (%s)", rel,
            table.concat(scaled, " | ")), #scaled == 0)
    end
end

print(string.format("status_bar_spec: %s (%d checks, %d failures)",
    failures == 0 and "ok" or "FAILED", checks, failures))
if failures > 0 then error("status_bar_spec failed", 0) end
