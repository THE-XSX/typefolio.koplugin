-- SPDX-FileCopyrightText: Copyright (C) 2026 THE-XSX
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- Typefolio (文笺) - KOReader plugin
-- Released under the GNU Affero General Public License v3.0 or later.
-- See the LICENSE file in the project root for the full license text.

-- settings/help.lua
-- TypeFolio user guide and help submenu builder
local HelpSettings = {}

-- The Calibre regex guide, as lines. Exported because the health report shows the same
-- guide at the bottom of its own text viewer; it used to carry a second, hand-typed copy
-- of these regexes, and the copy had been abbreviated into something that silently
-- matches nothing when pasted into Calibre.
HelpSettings.CALIBRE_REGEX_KEYS = {
    "HELP_CALIBRE_UNDERLINE",
    "HELP_CALIBRE_DIALOGUE",
    "HELP_CALIBRE_TITLE",
    "HELP_CALIBRE_QUOTE",
    "HELP_CALIBRE_DROPCAP",
}

function HelpSettings.calibreRegexLines(tr, with_title)
    local lines = {}
    if with_title then
        table.insert(lines, tr("HELP_CALIBRE_REGEX_TITLE"))
    end
    for _, key in ipairs(HelpSettings.CALIBRE_REGEX_KEYS) do
        if #lines > 0 then table.insert(lines, "") end
        table.insert(lines, tr(key))
    end
    return lines
end

function HelpSettings.subItems(ctx)
    local tr = ctx.tr
    local showInfo = ctx.showInfo

    return {
        {
            text = tr("Overview & Rendering"),
            keep_menu_open = true,
            callback = function()
                local help_lines = {
                    tr("HELP_TITLE"),
                    "",
                    tr("HELP_HEALTH_CHECK"),
                    "",
                    tr("HELP_RENDERING"),
                    "",
                    tr("HELP_PAINT_LIMITS"),
                    "",
                    tr("HELP_SKIP_HEADINGS"),
                    "",
                    tr("HELP_DIALOGUE"),
                    "",
                    tr("HELP_BODY_TYPE"),
                    "",
                    tr("HELP_CHAPTER_PAGEBREAK"),
                    "",
                    tr("HELP_PURE_BLACK"),
                }
                showInfo(table.concat(help_lines, "\n"))
            end,
        },
        {
            text = tr("Calibre regex guide"),
            keep_menu_open = true,
            callback = function()
                showInfo(table.concat(
                    HelpSettings.calibreRegexLines(tr, true), "\n"))
            end,
        },
        {
            text = tr("Gestures & Presets"),
            keep_menu_open = true,
            callback = function()
                local help_lines = {
                    tr("HELP_GESTURE"),
                    "",
                    tr("HELP_PRESETS"),
                }
                showInfo(table.concat(help_lines, "\n"))
            end,
        },
    }
end

return HelpSettings
