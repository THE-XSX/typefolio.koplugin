-- SPDX-FileCopyrightText: Copyright (C) 2026 THE-XSX
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- Typefolio (文笺) - KOReader plugin
-- Released under the GNU Affero General Public License v3.0 or later.
-- See the LICENSE file in the project root for the full license text.

-- Where a paragraph's characters actually live in the DOM.
--
-- A crengine xpointer addresses a *text node*, not a paragraph: the number after the dot
-- counts characters inside one text node. Quote and emphasis detection, on the other hand,
-- run over the whole paragraph, because an utterance may wrap across screen lines. The two
-- agree only for a paragraph made of a single text node -- and inline markup splits it:
-- <span class="dialogue"> from a Calibre edition, <em>, <b>, a footnote link, even the
-- <span class="calibreN"> wrappers Calibre sprinkles over converted books. Splice a
-- paragraph-wide offset onto the first node's pointer and it either addresses nothing (the
-- engine returns no geometry, and the painter used to tint the whole line instead --
-- reported from the device on 2026-08-22) or, when a later node happens to be long enough,
-- it addresses the wrong words and the mark lands somewhere else entirely.
--
-- So this module answers "which text node holds paragraph character N, and what is its
-- offset inside that node" from markup the plugin already has, without asking the engine to
-- walk anything: one string scan per paragraph, no native calls.
--
-- It also owns the HTML-to-text normalization the offsets are measured against, because
-- the segment lengths and `node.text` have to agree byte for byte; semantic_index reuses
-- these rather than keeping a second copy that can drift.
local TextNodes = {}

-- Elements with no closing tag. They still occupy a child slot -- <br> shifts the element
-- index of its siblings -- but contribute no characters.
local VOID_TAGS = {
    br = true, img = true, hr = true, area = true, base = true, col = true, embed = true,
    input = true, link = true, meta = true, param = true, source = true, track = true,
    wbr = true,
}

-- Content that is in the DOM but never rendered. Its text node still counts towards the
-- text() index of later siblings, so it is recorded with zero length rather than dropped.
local SKIP_CONTENT = { script = true, style = true }

-- Inline elements, i.e. the ones that split a paragraph into several text nodes without
-- starting a new block. Only used to walk *up* from a pointer to the block it sits in; a tag
-- missing from this list costs a cache entry, never a wrong mark.
local INLINE_TAGS = {
    span = true, em = true, i = true, b = true, strong = true, a = true, u = true, s = true,
    strike = true, small = true, big = true, sub = true, sup = true, code = true, tt = true,
    font = true, cite = true, q = true, abbr = true, acronym = true, mark = true, ruby = true,
    rt = true, rb = true, rp = true, samp = true, kbd = true, var = true, del = true,
    ins = true, nobr = true, bdi = true, bdo = true, label = true, time = true,
}

-- The block element a pointer sits in: its trailing character offset, its text node and any
-- inline wrappers stripped off.
--
-- This is the right key for anything counted "per paragraph". Stopping at the text node --
-- which is all `xpointer:match("^(.*)%.%d+$")` does -- makes one paragraph split by inline
-- markup look like three, and it then pays for three HTML reads, three resolver passes and
-- three tint passes over the same pixels.
--
-- Returns the block's path, the pointer's own path relative to it ("span[1]/text()"), and
-- the block's tag; nil for anything that is not a path.
function TextNodes.blockPath(xpointer)
    if type(xpointer) ~= "string" then return nil end
    local path = xpointer:match("^(.*)%.%d+$") or xpointer
    local relative = {}
    local head, step = path:match("^(.*)/([^/]+)$")
    while step do
        local name = step:match("^([%w:_-]+)")
        if step:find("^text%(%)") or (name and INLINE_TAGS[name:lower()]) then
            table.insert(relative, 1, step)
            path = head
            head, step = path:match("^(.*)/([^/]+)$")
        else
            break
        end
    end
    if not step then return nil end
    return path, table.concat(relative, "/"), (step:match("^([%w:_-]+)") or ""):lower()
end

local function codepoint(code)
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
end

function TextNodes.decodeEntities(value)
    if type(value) ~= "string" or value == "" or not value:find("&", 1, true) then
        return value or ""
    end
    local text = value
    if text:find("&#x", 1, true) then
        text = text:gsub("&#x(%x+);", function(hex) return codepoint(tonumber(hex, 16)) end)
    end
    if text:find("&#", 1, true) then
        text = text:gsub("&#(%d+);", function(dec) return codepoint(tonumber(dec, 10)) end)
    end
    return (text:gsub("&quot;", '"'):gsub("&apos;", "'")
        :gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&"))
end

-- Number of UTF-8 codepoints in the first `bytes` bytes of `text`. Offsets in an xpointer
-- count characters, but Lua patterns hand back byte positions, so every range has to be
-- converted before it can be spliced into a pointer.
function TextNodes.charCount(text, bytes)
    if type(text) ~= "string" then return 0 end
    local count = 0
    local i = 1
    while i <= bytes and i <= #text do
        local byte = text:byte(i)
        -- Continuation bytes are 10xxxxxx; only count lead bytes.
        if byte < 0x80 or byte >= 0xC0 then count = count + 1 end
        i = i + 1
    end
    return count
end

-- Byte offset of the `count`-th character (0-based), i.e. the inverse of charCount.
function TextNodes.byteAt(text, count)
    if type(text) ~= "string" then return nil end
    local seen = 0
    local i = 1
    while i <= #text do
        local byte = text:byte(i)
        if byte < 0x80 or byte >= 0xC0 then
            if seen == count then return i end
            seen = seen + 1
        end
        i = i + 1
    end
    if seen == count then return #text + 1 end
    return nil
end

-- Everything the plain-text conversion does except the whitespace collapse and the trim,
-- which have to see the neighbouring nodes and so are applied while walking.
local function normalizePiece(raw)
    local piece = TextNodes.decodeEntities(raw)
    if piece:find("&nbsp;", 1, true) then piece = piece:gsub("&nbsp;", " ") end
    -- 0x1001 HTML includes soft hyphens where crengine may break; they are not part of the
    -- visible text and must not shift offsets.
    if piece:find("\194\173", 1, true) then piece = piece:gsub("\194\173", "") end
    if piece:find("\239\187\191", 1, true) then piece = piece:gsub("\239\187\191", "") end
    return (piece:gsub("%s+", " "))
end

-- Plain text of an HTML fragment: tags out, entities decoded, whitespace collapsed, ends
-- trimmed. This is the string every offset in this plugin is measured against.
function TextNodes.normalize(html)
    if type(html) ~= "string" or html == "" then return "" end
    local stripped = html
    if stripped:find("<", 1, true) then
        stripped = stripped:gsub("<%s*[sS][cC][rR][iI][pP][tT].-<%s*/%s*[sS][cC][rR][iI][pP][tT]%s*>", " ")
            :gsub("<%s*[sS][tT][yY][lL][eE].-<%s*/%s*[sS][tT][yY][lL][eE]%s*>", " ")
            :gsub("<[^>]*>", "")
    end
    return (normalizePiece(stripped):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Split a paragraph's markup into its text nodes.
--
-- Returns { tag, text, total, segments = { { path, plain, start, length, text }, ... } }
-- where `path` is relative to the paragraph element ("text()[1]", "span[1]/text()[1]"),
-- `plain` is the same node spelled without its redundant index (only set where that is
-- legal), `start` is the 0-based character offset of the node's first character in `text`,
-- and `total` is the paragraph's length in characters. nil when the markup cannot be parsed.
--
-- `expected_tag` is the paragraph's own tag, taken from the caller's xpointer. When the
-- engine hands back more than the paragraph -- some flag combinations wrap the fragment in
-- its ancestors -- the scan is restarted at that tag, because every path returned here is
-- relative to it.
--
-- The text() index counts text siblings only. Getting it wrong costs an unresolved pointer,
-- never a wrong mark: the caller checks the character it landed on before drawing.
function TextNodes.segments(html, expected_tag)
    if type(html) ~= "string" or html == "" then return nil end
    local from = 1
    if expected_tag then
        local tag = expected_tag:lower()
        local first = html:find("<%s*" .. tag .. "[%s>/]")
        if first and first > 1 then from = first end
    end

    local segments, stack = {}, {}
    local text_children = {}    -- parent path -> how many text nodes it has
    local root_tag
    local pos, length = from, #html
    local started, trailing_space = false, false

    local function parentPath()
        local parts = {}
        for i = 2, #stack do
            parts[#parts + 1] = stack[i].name .. "[" .. stack[i].index .. "]"
        end
        return table.concat(parts, "/")
    end

    local function emitText(raw)
        local parent = stack[#stack]
        if not parent then return end -- text outside the paragraph element
        parent.texts = parent.texts + 1
        local prefix = parentPath()
        text_children[prefix] = parent.texts
        local piece = parent.skip and "" or normalizePiece(raw)
        if piece ~= "" and (not started or trailing_space) then
            -- A whitespace run spanning a tag boundary collapses to one space, and the
            -- paragraph's leading run is trimmed away entirely.
            piece = piece:gsub("^ +", "")
        end
        if piece ~= "" then
            trailing_space = piece:sub(-1) == " "
            if piece:find("[^ ]") then started = true end
        end
        segments[#segments + 1] = {
            parent = prefix, index = parent.texts, text = piece,
            length = TextNodes.charCount(piece, #piece),
        }
    end

    while pos <= length do
        local lt = html:find("<", pos, true)
        if not lt then
            emitText(html:sub(pos))
            break
        end
        if lt > pos then emitText(html:sub(pos, lt - 1)) end
        local head = html:sub(lt + 1, lt + 1)
        if html:sub(lt, lt + 3) == "<!--" then
            local stop = html:find("-->", lt + 4, true)
            pos = stop and stop + 3 or length + 1
        elseif head == "!" or head == "?" then
            local stop = html:find(">", lt + 1, true)
            pos = stop and stop + 1 or length + 1
        else
            local stop = html:find(">", lt + 1, true)
            if not stop then break end
            local raw = html:sub(lt + 1, stop - 1)
            local name = raw:match("^/?%s*([%w:_-]+)")
            if name then
                name = name:lower()
                if raw:sub(1, 1) == "/" then
                    for i = #stack, 1, -1 do
                        if stack[i].name == name then
                            for _ = i, #stack do table.remove(stack) end
                            break
                        end
                    end
                    -- The paragraph closed; anything after it belongs to a sibling.
                    if #stack == 0 and root_tag then break end
                else
                    local parent = stack[#stack]
                    local index = 1
                    if parent then
                        parent.elements[name] = (parent.elements[name] or 0) + 1
                        index = parent.elements[name]
                    else
                        root_tag = name
                    end
                    if not (VOID_TAGS[name] or raw:sub(-1) == "/") then
                        stack[#stack + 1] = {
                            name = name, index = index, elements = {}, texts = 0,
                            skip = SKIP_CONTENT[name] or (parent and parent.skip) or nil,
                        }
                    end
                end
            end
            pos = stop + 1
        end
    end

    if not root_tag or #segments == 0 then return nil end

    -- The trailing whitespace run is trimmed off the paragraph, so it has to come off the
    -- last nodes that carry it.
    for i = #segments, 1, -1 do
        local segment = segments[i]
        if segment.length > 0 then
            local trimmed = segment.text:gsub(" +$", "")
            if trimmed ~= segment.text then
                segment.length = TextNodes.charCount(trimmed, #trimmed)
                segment.text = trimmed
            end
            if segment.text ~= "" then break end
        end
    end

    local at, pieces = 0, {}
    for _, segment in ipairs(segments) do
        local prefix = segment.parent ~= "" and (segment.parent .. "/") or ""
        segment.path = prefix .. "text()[" .. segment.index .. "]"
        -- crengine's serializer omits a redundant index, so the first text node of a parent
        -- that has only one may be spelled either way. Its parser counts text children and
        -- should accept both, but that is the one thing here no fixture can prove, so the
        -- alternative spelling is kept for the caller to retry with.
        if segment.index == 1 and text_children[segment.parent] == 1 then
            segment.plain = prefix .. "text()"
        end
        segment.start = at
        at = at + segment.length
        pieces[#pieces + 1] = segment.text
        segment.parent, segment.index = nil, nil
    end
    return { tag = root_tag, segments = segments, total = at, text = table.concat(pieces) }
end

-- The node holding paragraph character `offset` (0-based), plus the offset inside it.
--
-- `edge` picks what happens exactly on a node boundary: "start" wants a node that really
-- has a character there, "stop" wants the end of the node the previous character is in.
-- Pointing a range's start at the end of the preceding node is what the reported bug looked
-- like from the engine's side -- an empty range, no geometry, and a whole line tinted.
function TextNodes.locate(list, offset, edge)
    if type(list) ~= "table" then return nil end
    for _, segment in ipairs(list.segments or {}) do
        if segment.length > 0 then
            local last = segment.start + segment.length
            if edge == "stop" then
                if offset > segment.start and offset <= last then
                    return segment, offset - segment.start
                end
            elseif offset >= segment.start and offset < last then
                return segment, offset - segment.start
            end
        end
    end
    return nil
end

return TextNodes
