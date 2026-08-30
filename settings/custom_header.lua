-- SPDX-FileCopyrightText: Copyright (C) 2026 THE-XSX
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- Typefolio (文笺) - KOReader plugin
-- Released under the GNU Affero General Public License v3.0 or later.
-- See the LICENSE file in the project root for the full license text.

-- settings/custom_header.lua
-- Menu for the Typefolio Modern Custom Reading Header (页眉 / 顶部状态栏).
-- All rows, slot ids, divider ids and presets are shared with the footer in
-- settings/status_bar_menu.lua; keeping a second copy here is what let the two menus
-- drift apart from core/config.lua in the first place.
local item_path = debug.getinfo(1, "S").source:sub(2)
local PLUGIN_ROOT = item_path:match("(.*[/\\]typefolio%.koplugin[/\\])") or item_path:match("(.*[/\\])settings[/\\]") or item_path:match("(.*[/\\])") or "plugins/typefolio.koplugin/"

local StatusBarMenu = dofile(PLUGIN_ROOT .. "settings/status_bar_menu.lua")

local CustomHeaderSettings = {}

local BAR = "custom_header"

function CustomHeaderSettings.items(ctx)
    return StatusBarMenu.items(ctx, BAR)
end

function CustomHeaderSettings.slotItems(ctx, slot_name)
    return StatusBarMenu.slotItems(ctx, BAR, slot_name)
end

function CustomHeaderSettings.dividerItems(ctx)
    return StatusBarMenu.dividerItems(ctx, BAR)
end

function CustomHeaderSettings.presetItems(ctx)
    return StatusBarMenu.presetItems(ctx, BAR)
end

return CustomHeaderSettings
