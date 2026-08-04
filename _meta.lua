local item_path = debug.getinfo(1, "S").source:sub(2)
local PLUGIN_ROOT = item_path:match("(.*[/\\])") or "plugins/typefolio.koplugin/"
local I18n = dofile(PLUGIN_ROOT .. "i18n.lua")
local translate = I18n.new(PLUGIN_ROOT, { language_setting = "typefolio_language" })

return {
    name = "typefolio",
    fullname = translate("Type Folio"),
    description = translate("Underline and typesetting tweaks for CRE books, applied through KOReader's Style tweaks mechanism."),
    version = "2.1.0",
}
