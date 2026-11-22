-- SPDX-FileCopyrightText: Copyright (C) 2026 THE-XSX
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- Typefolio (文笺) - KOReader plugin
-- Released under the GNU Affero General Public License v3.0 or later.
-- See the LICENSE file in the project root for the full license text.

local item_path = debug.getinfo(1, "S").source:sub(2)
local PLUGIN_ROOT = item_path:match("(.*[/\\]typefolio%.koplugin[/\\])") or item_path:match("(.*[/\\])") or "plugins/typefolio.koplugin/"
local SETTINGS_ROOT = PLUGIN_ROOT .. "settings/"
local HelpSettings = dofile(SETTINGS_ROOT .. "help.lua")
local TextMarksSettings = dofile(SETTINGS_ROOT .. "text_marks.lua")
local ChapterSettings = dofile(SETTINGS_ROOT .. "chapters.lua")
local TextStylingSettings = dofile(SETTINGS_ROOT .. "text_styling.lua")
local CustomHeaderSettings = dofile(SETTINGS_ROOT .. "custom_header.lua")
local CustomFooterSettings = dofile(SETTINGS_ROOT .. "custom_footer.lua")
local StatusBarMenu = dofile(SETTINGS_ROOT .. "status_bar_menu.lua")
local PresetsSettings = dofile(SETTINGS_ROOT .. "presets.lua")

local Settings = {
    Help = HelpSettings,
    TextMarks = TextMarksSettings,
    Chapters = ChapterSettings,
    TextStyling = TextStylingSettings,
    CustomHeader = CustomHeaderSettings,
    CustomFooter = CustomFooterSettings,
    Presets = PresetsSettings,
}

function Settings.menuItems(ctx)
    local tr = ctx.tr
    local items = {}

    -- 1. Presets (排版预设: 快速应用方案/保存预设)
    table.insert(items, {
        text = tr("Presets"),
        sub_item_table_func = function() return PresetsSettings.items(ctx) end,
        separator = true,
    })

    -- 2. Text & chapters (正文与章节: 对话、章节、划线、着重号、引用、下沉、加粗)
    table.insert(items, {
        text = tr("Text & chapters"),
        sub_item_table_func = function() return TextStylingSettings.items(ctx) end,
        separator = true,
    })

    -- 3. Header & footer (页眉与页脚: 预设、顶部页眉、底部页脚、禁用系统状态栏)
    table.insert(items, {
        text = tr("Header & footer"),
        sub_item_table_func = function() return StatusBarMenu.combinedItems(ctx) end,
        separator = true,
    })

    -- 4. Help / user guide (使用指南: 移至底部)
    table.insert(items, {
        text = tr("Help / user guide"),
        sub_item_table_func = function() return HelpSettings.subItems(ctx) end,
        separator = true,
    })

    -- 5. Preview page after each change (每次设置后实时预览)
    table.insert(items, {
        text_func = function()
            return ctx.T(tr("%1: %2"), tr("Preview page after each change"),
                ctx.previewOnChangeEnabled() and tr("Enabled") or tr("Disabled"))
        end,
        help_text = tr("After each change the menu steps aside so the page is visible. Tap anywhere to bring it back to the same screen you were on."),
        keep_menu_open = true,
        checked_func = function() return ctx.previewOnChangeEnabled() end,
        callback = function(touchmenu_instance)
            ctx.setPreviewOnChangeEnabled(not ctx.previewOnChangeEnabled())
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    })

    return items
end

return Settings
