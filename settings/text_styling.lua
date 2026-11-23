-- SPDX-FileCopyrightText: Copyright (C) 2026 THE-XSX
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- Typefolio (文笺) - KOReader plugin
-- Released under the GNU Affero General Public License v3.0 or later.
-- See the LICENSE file in the project root for the full license text.

-- settings/text_styling.lua
-- Body & chapters settings: ruled lines/underlines, dialogue, chapters,
-- blockquote, drop caps.
local item_path = debug.getinfo(1, "S").source:sub(2)
local SETTINGS_ROOT = item_path:match("(.*[/\\])") or ""
local TextMarksSettings = dofile(SETTINGS_ROOT .. "text_marks.lua")
local ChapterSettings = dofile(SETTINGS_ROOT .. "chapters.lua")
local TweakMenus = dofile(SETTINGS_ROOT .. "tweak_menus.lua")

local TextStylingSettings = {}

local function readConfig(ctx)
    if ctx.getReadonlyConfig then
        return ctx.getReadonlyConfig(ctx.ui)
    end
    return ctx.getConfig(ctx.ui)
end

function TextStylingSettings.items(ctx)
    local tr = ctx.tr
    local dialogue_item = ctx.tweakItems({
        { key = "dialogue_style", text = "Dialogue" },
    })[1]
    local rest_items = ctx.tweakItems({
        { key = "paragraph_spacing", text = "Paragraph spacing" },
        { key = "blockquote_box", text = "Blockquote" },
        { key = "drop_caps", text = "Drop caps" },
    })

    local items = {
        {
            text = tr("Ruled lines & underlines"),
            sub_item_table_func = function() return TextMarksSettings.items(ctx) end,
        },
        dialogue_item,
        {
            text = tr("Chapters"),
            sub_item_table_func = function() return ChapterSettings.items(ctx) end,
            separator = true,
        },
    }
    for _, item in ipairs(rest_items) do
        table.insert(items, item)
    end
    return items
end

return TextStylingSettings
