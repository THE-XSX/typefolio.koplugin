-- settings/help.lua
-- TypeFolio user guide and help submenu builder
local HelpSettings = {}

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
                local help_lines = {
                    tr("HELP_CALIBRE_REGEX_TITLE"),
                    "",
                    tr("HELP_CALIBRE_UNDERLINE"),
                    "",
                    tr("HELP_CALIBRE_DIALOGUE"),
                    "",
                    tr("HELP_CALIBRE_TITLE"),
                    "",
                    tr("HELP_CALIBRE_QUOTE"),
                    "",
                    tr("HELP_CALIBRE_DROPCAP"),
                }
                showInfo(table.concat(help_lines, "\n"))
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
