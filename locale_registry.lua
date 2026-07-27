local Registry = {}
Registry.__index = Registry

local LOCALE_FILES = {
    "en",
    "zh_CN",
}

local function normalizeCode(code)
    if type(code) ~= "string" then return nil end
    code = code:gsub("%..*$", ""):gsub("-", "_"):lower()
    return code ~= "" and code or nil
end

function Registry.new(plugin_root)
    local interface = dofile(plugin_root .. "locale_interface.lua")
    local self = setmetatable({
        ordered = {},
        by_id = {},
        aliases = {},
    }, Registry)

    for _, filename in ipairs(LOCALE_FILES) do
        local source = "locales/" .. filename .. ".lua"
        local locale = interface.validate(dofile(plugin_root .. source), source)
        if self.by_id[locale.id] then
            error("Duplicate locale id: " .. locale.id)
        end
        self.by_id[locale.id] = locale
        table.insert(self.ordered, locale)
        self.aliases[normalizeCode(locale.id)] = locale.id
        for _, alias in ipairs(locale.aliases or {}) do
            self.aliases[normalizeCode(alias)] = locale.id
        end
    end
    assert(self.by_id.en, "The English fallback locale is required")
    return self
end

function Registry:list()
    return self.ordered
end

function Registry:get(id)
    return self.by_id[id]
end

function Registry:resolve(code)
    return self.aliases[normalizeCode(code)] or "en"
end

return Registry
