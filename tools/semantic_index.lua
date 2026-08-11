local SemanticIndex = {}
SemanticIndex.__index = SemanticIndex

local HEADING_TAGS = { h1 = true, h2 = true, h3 = true, h4 = true, h5 = true, h6 = true }
local SEMANTIC_TAGS = { blockquote = true, hr = true, q = true }
for tag in pairs(HEADING_TAGS) do SEMANTIC_TAGS[tag] = true end

local function decodeEntities(value)
    local text = value or ""
    text = text:gsub("&#x(%x+);", function(hex)
        local code = tonumber(hex, 16)
        if not code then return "" end
        if code < 0x80 then
            return string.char(code)
        elseif code < 0x800 then
            return string.char(0xC0 + math.floor(code / 0x40), 0x80 + (code % 0x40))
        elseif code < 0x10000 then
            return string.char(
                0xE0 + math.floor(code / 0x1000),
                0x80 + math.floor((code % 0x1000) / 0x40),
                0x80 + (code % 0x40))
        end
        return ""
    end)
    text = text:gsub("&#(%d+);", function(dec)
        local code = tonumber(dec, 10)
        if not code then return "" end
        if code < 0x80 then
            return string.char(code)
        elseif code < 0x800 then
            return string.char(0xC0 + math.floor(code / 0x40), 0x80 + (code % 0x40))
        elseif code < 0x10000 then
            return string.char(
                0xE0 + math.floor(code / 0x1000),
                0x80 + math.floor((code % 0x1000) / 0x40),
                0x80 + (code % 0x40))
        end
        return ""
    end)
    return (text:gsub("&quot;", '"'):gsub("&apos;", "'")
        :gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&"))
end

local function attributesFromHTML(html, preferred_tag)
    if type(html) ~= "string" then return nil, nil, {} end
    local tag, attributes
    local semantic_tag, semantic_attributes
    for candidate, candidate_attributes in html:gmatch("<%s*([%w:_-]+)([^>]*)>") do
        candidate = candidate:lower()
        if SEMANTIC_TAGS[candidate] then
            semantic_tag, semantic_attributes = candidate, candidate_attributes
            break
        end
    end
    if preferred_tag then
        for candidate, candidate_attributes in html:gmatch("<%s*([%w:_-]+)([^>]*)>") do
            if candidate:lower() == preferred_tag then
                tag, attributes = preferred_tag, candidate_attributes
                break
            end
        end
    end
    if semantic_tag and not SEMANTIC_TAGS[preferred_tag] then
        tag, attributes = semantic_tag, semantic_attributes
    end
    if not tag then tag, attributes = html:match("<%s*([%w:_-]+)(.-)>") end
    if not tag then return nil, nil, {} end
    tag = tag:lower()
    local id = attributes:match('[%s]id%s*=%s*"([^"]+)"')
        or attributes:match("[%s]id%s*=%s*[']([^']+)[']")
    local class = attributes:match('[%s]class%s*=%s*"([^"]+)"')
        or attributes:match("[%s]class%s*=%s*[']([^']+)[']")
    local classes = {}
    for name in decodeEntities(class):gmatch("[^%s]+") do table.insert(classes, name) end
    return tag, decodeEntities(id), classes
end

local function tagFromXPointer(xpointer)
    if type(xpointer) ~= "string" then return nil end
    local tag
    for part in xpointer:gmatch("/([%w:_-]+)") do
        local candidate = part:lower()
        if candidate ~= "text" and candidate ~= "text()" and candidate ~= "docfragment" then
            tag = candidate
        end
    end
    return tag
end

local function semanticKind(tag, classes)
    if HEADING_TAGS[tag] then return "heading" end
    if tag == "blockquote" or tag == "q" then return "blockquote" end
    if tag == "hr" then return "scene_break" end
    for _, name in ipairs(classes or {}) do
        local lower = name:lower()
        if lower:find("scene", 1, true) or lower:find("break", 1, true)
                or lower:find("separator", 1, true) then
            return "scene_break"
        end
    end
    return "body"
end

local function textFromHTML(html)
    if type(html) ~= "string" or html == "" then return "" end
    -- Drop script/style bodies, then all tags, then collapse whitespace.
    local stripped = html:gsub("<%s*[sS][cC][rR][iI][pP][tT].-<%s*/%s*[sS][cC][rR][iI][pP][tT]%s*>", " ")
        :gsub("<%s*[sS][tT][yY][lL][eE].-<%s*/%s*[sS][tT][yY][lL][eE]%s*>", " ")
        :gsub("<[^>]*>", "")
    stripped = decodeEntities(stripped):gsub("&nbsp;", " ")
    -- 0x1001 HTML includes soft hyphens where creengine may break; they are not
    -- part of the visible utterance and must not shift quote offsets.
    stripped = stripped:gsub("\194\173", "") -- U+00AD as UTF-8
        :gsub("\239\187\191", "") -- UTF-8 BOM
    return (stripped:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function normalizeSample(sample, index)
    local xpointer_tag = tagFromXPointer(sample.xpointer)
    local html_tag, id, classes = attributesFromHTML(sample.html, xpointer_tag)
    local tag = xpointer_tag or html_tag or "unknown"
    return {
        index = index,
        box = sample.box,
        xpointer = sample.xpointer,
        pos0 = sample.pos0,
        tag = tag,
        id = id,
        classes = classes,
        kind = semanticKind(tag, classes),
        html = sample.html,
        text = textFromHTML(sample.html),
        screen_text = sample.screen_text,
        html_available = type(sample.html) == "string" and sample.html ~= "",
    }
end

local function distanceTo(box, point)
    if not box then return math.huge end
    local cx, cy = box.x + box.w / 2, box.y + box.h / 2
    local dx, dy = cx - point.x, cy - point.y
    return dx * dx + dy * dy
end

function SemanticIndex.new(opts)
    return setmetatable({ context = assert(opts.context), cache = nil }, SemanticIndex)
end

function SemanticIndex:invalidate()
    self.cache = nil
end

function SemanticIndex:inspect(request)
    request = request or {}
    if not self.cache then
        local source = self.context:snapshot({
            chapter = true,
            line_mode = "all",
            semantics = true,
            toc = true,
        })
        local nodes = {}
        for index, sample in ipairs(source.semantics or {}) do
            table.insert(nodes, normalizeSample(sample, index))
        end
        self.cache = {
            page = source.page,
            chapter = source.chapter,
            toc = source.toc or { count = 0, empty_titles = 0 },
            nodes = nodes,
            capabilities = source.capabilities or {},
        }
    end

    local snapshot = self.cache
    local target = request.target
    if target and #snapshot.nodes > 0 then
        local best, best_distance
        for _, node in ipairs(snapshot.nodes) do
            local distance = distanceTo(node.box, target)
            if not best_distance or distance < best_distance then
                best, best_distance = node, distance
            end
        end
        local result = {}
        for key, value in pairs(snapshot) do result[key] = value end
        result.target = best
        return result
    end
    return snapshot
end

SemanticIndex.attributesFromHTML = attributesFromHTML
SemanticIndex.tagFromXPointer = tagFromXPointer
SemanticIndex.semanticKind = semanticKind

return SemanticIndex
