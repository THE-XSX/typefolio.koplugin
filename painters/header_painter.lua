-- SPDX-FileCopyrightText: Copyright (C) 2026 THE-XSX
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- Typefolio (文笺) - KOReader plugin
-- Released under the GNU Affero General Public License v3.0 or later.
-- See the LICENSE file in the project root for the full license text.

-- painters/header_painter.lua
-- Typefolio Modern Custom Reading Header (页眉 / 顶部状态栏)
-- Layout and slot resolution live in painters/status_bar_helper.lua; this file only
-- decides whether to draw and where the page number comes from. The header and the
-- footer used to carry duplicate copies of the layout code, which is how their
-- slot vocabularies drifted out of sync with core/config.lua.
local item_path = debug.getinfo(1, "S").source:sub(2)
local PLUGIN_ROOT = item_path:match("(.*[/\\]typefolio%.koplugin[/\\])") or item_path:match("(.*[/\\])painters[/\\]") or item_path:match("(.*[/\\])") or "plugins/typefolio.koplugin/"

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ModuleLoader = dofile(PLUGIN_ROOT .. "core/module_loader.lua")
local StatusBarHelper = ModuleLoader.load(PLUGIN_ROOT, "painters/status_bar_helper.lua")

local HeaderPainter = WidgetContainer:extend{
    enabled = false,
}

function HeaderPainter:init()
    self.helper = StatusBarHelper.new()
end

function HeaderPainter:setConfig(config)
    self.config = config or {}
    self.header_config = self.config.custom_header or {}
    self.enabled = self.header_config.enabled == true
    self:invalidate("config_apply")
end

function HeaderPainter:invalidate(reason)
    if reason == "page_update" or reason == "pos_update" then
        return
    end
    if self.helper then
        self.helper:invalidateTocCache()
    end
end

function HeaderPainter:paintTo(bb, x, y)
    if not (self.enabled and self.context) then return end
    local cfg = self.header_config
    if not cfg or cfg.enabled ~= true then return end

    if not self.helper then
        self.helper = StatusBarHelper.new()
    end

    local snapshot = self.context:snapshot({ chapter = true })
    local chapter = snapshot.chapter or {}
    if cfg.hide_on_chapter_start and chapter.is_start then
        return
    end

    local page_info = snapshot.page or {}
    local page_count = page_info.page_count
    if not page_count and self.ui and self.ui.document then
        page_count = StatusBarHelper.safeCall(function()
            return self.ui.document:getPageCount()
        end)
    end
    page_count = page_count or 1

    self.helper:paintBar(bb, {
        position = "top",
        config = cfg,
        ui = self.ui,
        book_context = self.context,
        page_num = page_info.number or 1,
        page_count = page_count,
        tr = self.tr,
    })
end

return HeaderPainter
