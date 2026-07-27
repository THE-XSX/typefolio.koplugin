local gettext = require("gettext")

local I18n = {}
local Translator = {}
Translator.__index = Translator

local function readSetting(key)
    local settings = rawget(_G, "G_reader_settings")
    if not settings or type(settings.readSetting) ~= "function" then return nil end
    local ok, value = pcall(settings.readSetting, settings, key)
    return ok and value or nil
end

local function gettextLanguage()
    if type(gettext) ~= "table" then return nil end
    for _, method in ipairs({ "getCurrentLanguage", "getLanguage" }) do
        if type(gettext[method]) == "function" then
            local ok, language = pcall(gettext[method], gettext)
            if ok and language then return language end
        end
    end
    return gettext.current_language or gettext.current_lang
end

function I18n.new(plugin_root, options)
    options = options or {}
    local registry = dofile(plugin_root .. "locale_registry.lua").new(plugin_root)
    return setmetatable({
        registry = registry,
        language_setting = options.language_setting or "book_receipt_language",
    }, {
        __index = Translator,
        __call = function(self, text) return self:translate(text) end,
    })
end

function Translator:language()
    local selected = readSetting(self.language_setting)
    if selected and selected ~= "system" and self.registry:get(selected) then
        return selected
    end
    return self.registry:resolve(readSetting("language") or gettextLanguage() or os.getenv("LANG"))
end

function Translator:translate(text)
    if type(text) ~= "string" then return text end
    local locale = self.registry:get(self:language())
    local fallback = self.registry:get("en")
    return (locale and locale.strings[text]) or fallback.strings[text] or gettext(text)
end

function Translator:format(text, ...)
    return string.format(self:translate(text), ...)
end

function Translator:locales()
    return self.registry:list()
end

return I18n
