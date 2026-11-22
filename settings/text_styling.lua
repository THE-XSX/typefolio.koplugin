-- SPDX-FileCopyrightText: Copyright (C) 2026 THE-XSX
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- Typefolio (文笺) - KOReader plugin
-- Released under the GNU Affero General Public License v3.0 or later.
-- See the LICENSE file in the project root for the full license text.

-- settings/text_styling.lua
-- Text styling settings: dialogue, chapters, ruled lines, emphasis dots,
-- blockquote, drop caps, body bold, pure black text
local item_path = debug.getinfo(1, "S").source:sub(2)
local PLUGIN_ROOT = item_path:match("(.*[/\\]typefolio%.koplugin[/\\])") or item_path:match("(.*[/\\])") or "plugins/typefolio.koplugin/"
local SETTINGS_ROOT = PLUGIN_ROOT .. "settings/"
local TextMarksSettings = dofile(SETTINGS_ROOT .. "text_marks.lua")
local ChapterSettings = dofile(SETTINGS_ROOT .. "chapters.lua")
local ModuleLoader = dofile(PLUGIN_ROOT .. "core/module_loader.lua")
local TweakMenus = ModuleLoader.load(PLUGIN_ROOT, "settings/tweak_menus.lua")

local TextStylingSettings = {}

local function getEmphasisPainter(ctx, name)
    return ctx.getConfig(ctx.ui).emphasis_painter[name]
end

local function setEmphasisPainter(ctx, name, value)
    local config = ctx.getConfig(ctx.ui)
    config.emphasis_painter[name] = value
    ctx.applyStyle(config)
end

function TextStylingSettings.items(ctx)
    local tr = ctx.tr
    local items = {}

    -- 1. Dialogue styling & font switching
    local dlg_items = ctx.tweakItems({
        { key = "dialogue_style", text = "Dialogue" },
    })
    if dlg_items[1] then table.insert(items, dlg_items[1]) end

    -- 2. Chapters (title styling, breaks, boundary rules)
    table.insert(items, {
        text = tr("Chapters"),
        sub_item_table_func = function() return ChapterSettings.items(ctx) end,
        separator = true,
    })

    -- 3. Ruled lines (underlines)
    table.insert(items, {
        text = tr("Ruled lines / Underlines"),
        sub_item_table_func = function() return TextMarksSettings.items(ctx) end,
    })

    -- 4. Emphasis dots painter (着重号)
    table.insert(items, {
        text = tr("Emphasis dots painter"),
        keep_menu_open = true,
        checked_func = function() return getEmphasisPainter(ctx, "enabled") == true end,
        checkmark_callback = function(touchmenu_instance)
            setEmphasisPainter(ctx, "enabled", not getEmphasisPainter(ctx, "enabled"))
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
        sub_item_table_func = function() return TweakMenus.emphasisItems(ctx) end,
    })

    -- 5. Blockquote
    local bq_items = ctx.tweakItems({
        { key = "blockquote_box", text = "Blockquote" },
    })
    if bq_items[1] then table.insert(items, bq_items[1]) end

    -- 6. Drop caps
    local dc_items = ctx.tweakItems({
        { key = "drop_caps", text = "Drop caps" },
    })
    if dc_items[1] then
        dc_items[1].separator = true
        table.insert(items, dc_items[1])
    end

    -- 7. Body enhancements (bold, pure black text)
    local body_items = ctx.tweakItems({
        { key = "body_bold", text = "Body bold" },
        { key = "pure_black", text = "Pure black text" },
    })
    for _, item in ipairs(body_items) do
        table.insert(items, item)
    end

    return items
end

return TextStylingSettings
