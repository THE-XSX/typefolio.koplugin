-- SPDX-FileCopyrightText: Copyright (C) 2026 THE-XSX
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- Typefolio (文笺) - KOReader plugin
-- Released under the GNU Affero General Public License v3.0 or later.
-- See the LICENSE file in the project root for the full license text.

-- painters/footer_painter.lua
-- Typefolio Modern Custom Reading Footer (页脚 / 底部状态栏)
-- Shares all layout and slot resolution with the header through
-- StatusBarHelper:paintBar; only the position differs.
local item_path = debug.getinfo(1, "S").source:sub(2)
local PLUGIN_ROOT = item_path:match("(.*[/\\]typefolio%.koplugin[/\\])") or item_path:match("(.*[/\\])painters[/\\]") or item_path:match("(.*[/\\])") or "plugins/typefolio.koplugin/"

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ModuleLoader = dofile(PLUGIN_ROOT .. "core/module_loader.lua")
local StatusBarHelper = ModuleLoader.load(PLUGIN_ROOT, "painters/status_bar_helper.lua")

local FooterPainter = WidgetContainer:extend{
    enabled = false,
}

function FooterPainter:init()
    self.helper = StatusBarHelper.new()
end

function FooterPainter:setConfig(config)
    self.config = config or {}
    self.footer_config = self.config.custom_footer or {}
    self.enabled = self.footer_config.enabled == true
    self:invalidate("config_apply")
end

function FooterPainter:invalidate(reason)
    if reason == "page_update" or reason == "pos_update" then
        return
    end
    if self.helper then
        self.helper:invalidateTocCache()
    end
end

function FooterPainter:paintTo(bb, x, y)
    if not (self.enabled and self.context) then return end
    local cfg = self.footer_config
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
        position = "bottom",
        config = cfg,
        ui = self.ui,
        book_context = self.context,
        page_num = page_info.number or 1,
        page_count = page_count,
        tr = self.tr,
    })
end

return FooterPainter
