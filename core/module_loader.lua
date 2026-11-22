-- SPDX-FileCopyrightText: Copyright (C) 2026 THE-XSX
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- Typefolio (文笺) - KOReader plugin
-- Released under the GNU Affero General Public License v3.0 or later.
-- See the LICENSE file in the project root for the full license text.

-- Shared per-session module cache so internal plugin modules are loaded once
-- instead of being re-parsed by repeated dofile() calls across submodules.
-- Callers still pass literal relative ".lua" paths so tests/syntax_spec.lua
-- continues to discover every module in the static dependency graph.

local ModuleLoader = {}

local cache = rawget(_G, "_typefolio_module_cache")
if type(cache) ~= "table" then
    cache = {}
    _G._typefolio_module_cache = cache
end

function ModuleLoader.root(source, subdir)
    if type(source) ~= "string" then return "plugins/typefolio.koplugin/" end
    local path = source:sub(1, 1) == "@" and source:sub(2) or source
    local root = path:match("(.*[/\\]typefolio%.koplugin[/\\])")
    if root then return root end
    if type(subdir) == "string" and subdir ~= "" then
        root = path:match("^(.*)" .. subdir .. "[/\\]")
        if root then return root end
    end
    return path:match("(.*[/\\])") or "plugins/typefolio.koplugin/"
end

function ModuleLoader.load(plugin_root, rel_path)
    local full_path = (plugin_root or "") .. rel_path
    local cached = cache[full_path]
    if cached ~= nil then return cached end
    local mod = dofile(full_path)
    if mod ~= nil then
        cache[full_path] = mod
    end
    return mod
end

function ModuleLoader.clear()
    for k in pairs(cache) do
        cache[k] = nil
    end
end

return ModuleLoader
