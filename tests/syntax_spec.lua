-- Every Lua file the plugin loads must parse.
--
-- This was a hand-written list of eleven paths, which is the wrong shape for a
-- forward-compatibility check. The file that did break under Lua 5.4/5.5 -- tools/
-- semantic_index.lua, where a generic-for control variable was assigned, and that variable
-- is const from 5.5 on, so it is a *parse* error rather than a runtime one -- happened to be
-- on the list. The twenty-odd files that were not on it could have broken unnoticed.
--
-- So walk the dofile graph from main.lua instead of naming files. There is no directory
-- listing in the Lua standard library and this spec has to run without KOReader, so
-- discovery reads the sources: every `.lua` string literal is a candidate path, plus the one
-- dynamic form the registries use (a directory prefix concatenated with names from a
-- `*_FILES` list, which is how the locales are loaded).
--
-- Walking the graph also checks something a directory walk cannot: every path a dofile names
-- has to exist, so a moved or renamed module fails here too.
--
-- tests/ is deliberately outside the graph -- running the specs is a stronger check than
-- parsing them.

local failed = 0
local function fail(message)
    failed = failed + 1
    print("FAIL " .. message)
end

local function readFile(path)
    local handle = io.open(path, "r")
    if not handle then return nil end
    local source = handle:read("*a")
    handle:close()
    return source
end

local function exists(path)
    local handle = io.open(path, "r")
    if not handle then return false end
    handle:close()
    return true
end

local function directoryOf(path)
    return path:match("^(.*/)") or ""
end

-- A literal with a slash is relative to the plugin root. A bare filename is relative to the
-- file that names it: settings/init.lua loads its siblings as SETTINGS_ROOT .. "help.lua".
local function resolve(literal, referrer)
    local candidates = {}
    if literal:find("/", 1, true) then
        table.insert(candidates, literal)
    else
        table.insert(candidates, directoryOf(referrer) .. literal)
        table.insert(candidates, literal)
    end
    for _, candidate in ipairs(candidates) do
        if exists(candidate) then return candidate end
    end
    return nil, table.concat(candidates, " or ")
end

-- Two roots: main.lua is the graph, and _meta.lua is loaded by KOReader's plugin loader
-- rather than by any dofile, so nothing would reach it.
local seen = { ["main.lua"] = true, ["_meta.lua"] = true }
local queue = { "main.lua", "_meta.lua" }
local checked = 0

local function enqueue(literal, referrer)
    local path, tried = resolve(literal, referrer)
    if not path then
        return fail(referrer .. " loads " .. tried .. ", which does not exist")
    end
    if not seen[path] then
        seen[path] = true
        table.insert(queue, path)
    end
end

while #queue > 0 do
    local path = table.remove(queue, 1)
    local source = readFile(path)
    if not source then
        fail(path .. ": cannot be read")
    else
        local chunk, err = loadfile(path)
        if chunk then
            checked = checked + 1
        else
            fail(tostring(err))
        end
        for literal in source:gmatch('"([%w_%-/%.]+%.lua)"') do
            enqueue(literal, path)
        end
        -- i18n/locale_registry.lua: "i18n/locales/" .. filename .. ".lua" over LOCALE_FILES.
        -- Read the list out of the source so a new locale is covered the day it is added.
        local prefix = source:match('"([%w_%-/%.]*/)"%s*%.%.%s*[%w_]+%s*%.%.%s*"%.lua"')
        local list = source:match("_FILES%s*=%s*{(.-)}")
        if prefix and list then
            for name in list:gmatch('"([%w_%-]+)"') do
                enqueue(prefix .. name .. ".lua", path)
            end
        end
    end
end

-- A wrong working directory, or a discovery pattern that stopped matching, would otherwise
-- show up as a cheerful "ok (1 files)". Name a few files from the far side of the graph.
for _, required in ipairs({
    "core/book_context.lua",
    "css/preset_codec.lua",
    "i18n/locales/en.lua",
    "settings/presets.lua",
    "tools/semantic_index.lua",
}) do
    if not seen[required] then
        fail(required .. " was never reached -- run this spec from the plugin root")
    end
end

print(string.format("syntax_spec: %s (%d files)", failed == 0 and "ok" or "FAILED", checked))
if failed > 0 then error("syntax_spec failed", 0) end
