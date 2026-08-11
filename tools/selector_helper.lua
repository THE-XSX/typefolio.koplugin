local SelectorHelper = {}

local function cssEscape(value)
    if type(value) ~= "string" then return nil end
    local escaped = value:gsub("([^%w_-])", "\\%1")
    local first = escaped:sub(1, 1)
    if first:match("%d") then
        escaped = string.format("\\%x ", first:byte()) .. escaped:sub(2)
    end
    return escaped
end

local function usefulClass(classes)
    for _, name in ipairs(classes or {}) do
        if name:match("^[%a_][%w_-]*$") then return name end
    end
end

function SelectorHelper.suggest(snapshot)
    local node = snapshot and snapshot.target
    if not node then
        return { available = false, reason = "No semantic node is available near that screen position." }
    end

    local selector, confidence, source
    if node.id and node.id ~= "" then
        selector, confidence, source = "#" .. cssEscape(node.id), "high", "id"
    else
        local class = usefulClass(node.classes)
        if class then
            selector = (node.tag ~= "unknown" and node.tag or "") .. "." .. cssEscape(class)
            confidence, source = "medium", "class"
        elseif node.tag ~= "unknown" then
            selector, confidence, source = node.tag, "low", "tag"
        else
            selector, confidence, source = "body *", "low", "fallback"
        end
    end
    return {
        available = true,
        selector = selector,
        confidence = confidence,
        source = source,
        tag = node.tag,
        kind = node.kind,
        xpointer = node.xpointer,
        snippet = selector .. " {\n    /* Add Type Folio CSS here. */\n}",
    }
end

return SelectorHelper
