-- SPDX-FileCopyrightText: Copyright (C) 2026 THE-XSX
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- Typefolio (文笺) - KOReader plugin
-- Released under the GNU Affero General Public License v3.0 or later.
-- See the LICENSE file in the project root for the full license text.

-- settings/custom_footer.lua
-- Menu for the Typefolio Modern Custom Reading Footer (页脚 / 底部状态栏).
-- Shares every row with the header through settings/status_bar_menu.lua; only the bar
-- key differs, which is why the footer now offers the same presets and dividers.
local item_path = debug.getinfo(1, "S").source:sub(2)
local PLUGIN_ROOT = item_path:match("(.*[/\\]typefolio%.koplugin[/\\])") or item_path:match("(.*[/\\])settings[/\\]") or item_path:match("(.*[/\\])") or "plugins/typefolio.koplugin/"

local StatusBarMenu = dofile(PLUGIN_ROOT .. "settings/status_bar_menu.lua")

local CustomFooterSettings = {}

local BAR = "custom_footer"

function CustomFooterSettings.items(ctx)
    return StatusBarMenu.items(ctx, BAR)
end

function CustomFooterSettings.slotItems(ctx, slot_name)
    return StatusBarMenu.slotItems(ctx, BAR, slot_name)
end

function CustomFooterSettings.dividerItems(ctx)
    return StatusBarMenu.dividerItems(ctx, BAR)
end

function CustomFooterSettings.presetItems(ctx)
    return StatusBarMenu.presetItems(ctx, BAR)
end

return CustomFooterSettings
