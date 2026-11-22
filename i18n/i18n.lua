-- SPDX-FileCopyrightText: Copyright (C) 2026 THE-XSX
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- Typefolio (文笺) - KOReader plugin
-- Released under the GNU Affero General Public License v3.0 or later.
-- See the LICENSE file in the project root for the full license text.

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
    local registry = dofile(plugin_root .. "i18n/locale_registry.lua").new(plugin_root)
    return setmetatable({
        registry = registry,
        language_setting = options.language_setting or "typefolio_language",
        _fallback = registry:get("en"),
        _cached_selected = false,
        _cached_global = false,
        _cached_lang = nil,
        _cached_locale = nil,
    }, {
        __index = Translator,
        __call = function(self, text) return self:translate(text) end,
    })
end

function Translator:invalidateCache()
    self._cached_selected = false
    self._cached_global = false
    self._cached_lang = nil
    self._cached_locale = nil
end

function Translator:language()
    local selected = readSetting(self.language_setting)
    local global_lang = readSetting("language")
    if self._cached_lang ~= nil
            and self._cached_selected == selected
            and self._cached_global == global_lang then
        return self._cached_lang
    end
    local resolved
    if selected and selected ~= "system" and self.registry:get(selected) then
        resolved = selected
    else
        resolved = self.registry:resolve(global_lang or gettextLanguage() or os.getenv("LANG"))
    end
    self._cached_selected = selected
    self._cached_global = global_lang
    self._cached_lang = resolved
    self._cached_locale = self.registry:get(resolved)
    return resolved
end

function Translator:translate(text)
    if type(text) ~= "string" then return text end
    self:language()
    local locale = self._cached_locale
    local fallback = self._fallback
    return (locale and locale.strings[text]) or (fallback and fallback.strings[text]) or gettext(text)
end

function Translator:format(text, ...)
    return string.format(self:translate(text), ...)
end

function Translator:locales()
    return self.registry:list()
end

return I18n
