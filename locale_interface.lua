local Interface = {
    VERSION = 1,
}

local function fail(source, message)
    error(string.format("Invalid locale %s: %s", source, message))
end

function Interface.validate(locale, source)
    if type(locale) ~= "table" then fail(source, "module must return a table") end
    if locale.interface_version ~= Interface.VERSION then
        fail(source, "unsupported interface_version")
    end
    if type(locale.id) ~= "string" or not locale.id:match("^[a-z][A-Za-z0-9_]*$") then
        fail(source, "id must be ASCII and start with a lowercase letter")
    end
    if type(locale.label) ~= "string" or locale.label == "" then
        fail(source, "label must be a non-empty native display name")
    end
    if locale.aliases ~= nil and type(locale.aliases) ~= "table" then
        fail(source, "aliases must be a table")
    end
    for _, alias in ipairs(locale.aliases or {}) do
        if type(alias) ~= "string" or alias == "" then
            fail(source, "aliases must contain non-empty strings")
        end
    end
    if type(locale.strings) ~= "table" then
        fail(source, "strings must be a table")
    end
    for key, value in pairs(locale.strings) do
        if type(key) ~= "string" or type(value) ~= "string" then
            fail(source, "strings must contain string keys and values")
        end
    end
    return locale
end

return Interface
