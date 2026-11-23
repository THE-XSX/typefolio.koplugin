-- SPDX-FileCopyrightText: Copyright (C) 2026 THE-XSX
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- Typefolio (文笺) - KOReader plugin
-- Released under the GNU Affero General Public License v3.0 or later.
-- See the LICENSE file in the project root for the full license text.

-- tools/epub_dialogue_tagger.lua
-- Tag-aware offline EPUB dialogue markup generator.
--
-- Creates a non-destructive cached EPUB copy under <data_dir>/typefolio_cache/
-- with quoted utterances wrapped in <span class="tf-dlg">...</span> so crengine
-- can apply native CSS font-family / font-weight / font-style / background-color
-- during layout with zero page-turn runtime overhead.
--
-- Safety invariants:
--   1. Never modifies the source EPUB file.
--   2. Never alters HTML/XML tags, attributes, comments, CDATA, or PIs.
--   3. Skips <head>, <script>, <style>, <title>, <h1>..<h6>, <svg>, <math>,
--      <pre>, <code>, and any subtree already tagged with a dialogue class.
--   4. Splits <span class="tf-dlg"> cleanly across inline elements (<em>, <b>,
--      <i>, <span>, <a>, etc.) and resets at block boundaries so output stays
--      strictly well-formed XHTML even on malformed punctuation.

local EpubDialogueTagger = {}

EpubDialogueTagger.CACHE_DIR_NAME = "typefolio_cache"
EpubDialogueTagger.SUFFIX = ".tf_dlg.epub"
EpubDialogueTagger.CLASS_NAME = "tf-dlg"

local SKIP_TAGS = {
    head = true, script = true, style = true, title = true,
    h1 = true, h2 = true, h3 = true, h4 = true, h5 = true, h6 = true,
    svg = true, math = true, pre = true, code = true,
}

local BLOCK_TAGS = {
    body = true, section = true, article = true, div = true, p = true,
    blockquote = true, li = true, ul = true, ol = true, dd = true, dt = true,
    dl = true, table = true, tr = true, td = true, th = true,
    h1 = true, h2 = true, h3 = true, h4 = true, h5 = true, h6 = true,
    header = true, footer = true, aside = true, figure = true, figcaption = true,
    hr = true, br = true,
}

local VOID_TAGS = {
    area = true, base = true, br = true, col = true, embed = true, hr = true,
    img = true, input = true, link = true, meta = true, param = true,
    source = true, track = true, wbr = true,
}

local DIALOGUE_CLASS_TOKENS = {
    ["tf-dlg"] = true,
    dialogue = true,
    dialog = true,
    speech = true,
    ["quote-text"] = true,
    dlg = true,
}

local QUOTE_PAIRS_BY_LANG = {
    cn = {
        { open = "“", close = "”" },
        { open = "「", close = "」" },
        { open = "『", close = "』" },
    },
    en = {
        { open = "“", close = "”" },
        { open = '"', close = '"' },
    },
    all = {
        { open = "“", close = "”" },
        { open = "「", close = "」" },
        { open = "『", close = "』" },
        { open = '"', close = '"' },
    },
}

local function hasDialogueClass(attrs)
    if type(attrs) ~= "string" or attrs == "" then return false end
    local lowered = attrs:lower()
    for class_val in lowered:gmatch('class%s*=%s*"([^"]*)"') do
        for tok in class_val:gmatch("%S+") do
            if DIALOGUE_CLASS_TOKENS[tok] then return true end
        end
    end
    for class_val in lowered:gmatch("class%s*=%s*'([^']*)'") do
        for tok in class_val:gmatch("%S+") do
            if DIALOGUE_CLASS_TOKENS[tok] then return true end
        end
    end
    return false
end

-- Tokenizes an HTML/XHTML document into alternating { kind = "tag"|"text", raw = ... }
-- items while keeping comments, CDATA, DOCTYPE and processing instructions intact.
local function tokenize(html)
    local tokens = {}
    local len = #html
    local pos = 1
    while pos <= len do
        local lt = html:find("<", pos, true)
        if not lt then
            table.insert(tokens, { kind = "text", raw = html:sub(pos) })
            break
        end
        if lt > pos then
            table.insert(tokens, { kind = "text", raw = html:sub(pos, lt - 1) })
        end
        if html:sub(lt, lt + 3) == "<!--" then
            local close = html:find("-->", lt + 4, true)
            local stop = close and (close + 2) or len
            table.insert(tokens, { kind = "special", raw = html:sub(lt, stop) })
            pos = stop + 1
        elseif html:sub(lt, lt + 8) == "<![CDATA[" then
            local close = html:find("]]>", lt + 9, true)
            local stop = close and (close + 2) or len
            table.insert(tokens, { kind = "special", raw = html:sub(lt, stop) })
            pos = stop + 1
        elseif html:sub(lt, lt + 1) == "<?" then
            local close = html:find("?>", lt + 2, true)
            local stop = close and (close + 1) or len
            table.insert(tokens, { kind = "special", raw = html:sub(lt, stop) })
            pos = stop + 1
        elseif html:sub(lt, lt + 1) == "<!" then
            local close = html:find(">", lt + 2, true)
            local stop = close or len
            table.insert(tokens, { kind = "special", raw = html:sub(lt, stop) })
            pos = stop + 1
        else
            -- Scan to matching '>' respecting quoted attribute values.
            local i = lt + 1
            local quote_char = nil
            local stop = nil
            while i <= len do
                local b = html:byte(i)
                if quote_char then
                    if b == quote_char then quote_char = nil end
                else
                    if b == 34 or b == 39 then -- " or '
                        quote_char = b
                    elseif b == 62 then -- >
                        stop = i
                        break
                    end
                end
                i = i + 1
            end
            if not stop then
                table.insert(tokens, { kind = "text", raw = html:sub(lt) })
                break
            end
            local raw_tag = html:sub(lt, stop)
            local is_close = raw_tag:match("^<%s*/") ~= nil
            local is_self = not is_close and raw_tag:match("/%s*>$") ~= nil
            local name = raw_tag:match("^<%s*/?%s*([%a][%w:%-_]*)")
            name = name and name:lower() or ""
            table.insert(tokens, {
                kind = "tag",
                raw = raw_tag,
                name = name,
                is_close = is_close,
                is_self = is_self or VOID_TAGS[name] == true,
            })
            pos = stop + 1
        end
    end
    return tokens
end

-- Finds the earliest opening quote marker in `text` starting from `pos`.
local function findNextOpen(text, pos, pairs_list)
    local best_s, best_e, best_pair
    for _, pair in ipairs(pairs_list) do
        local s, e = text:find(pair.open, pos, true)
        if s and (not best_s or s < best_s) then
            best_s, best_e, best_pair = s, e, pair
        end
    end
    return best_s, best_e, best_pair
end

-- Processes a contiguous slice of tokens within one block context (no block tags inside,
-- only text/special/inline tags). Wraps matched paired quotes in <span class="tf-dlg">,
-- splitting cleanly across inline tags so every tag stays properly nested.
local function tagBlockSlice(tokens, first_idx, last_idx, pairs_list)
    -- Collect only text tokens with their slice offsets so we can match paired quotes
    -- across inline tags (e.g. “He said <em>quietly</em>.”) and verify every opener has
    -- a matching closer inside the same block before emitting any <span>.
    local pieces = {}
    local concat_parts = {}
    local total_len = 0
    for idx = first_idx, last_idx do
        local tok = tokens[idx]
        if tok.kind == "text" and #tok.raw > 0 then
            table.insert(pieces, {
                tok_idx = idx,
                start_pos = total_len + 1,
                end_pos = total_len + #tok.raw,
                raw = tok.raw,
            })
            table.insert(concat_parts, tok.raw)
            total_len = total_len + #tok.raw
        end
    end
    if #pieces == 0 then
        local out = {}
        for idx = first_idx, last_idx do table.insert(out, tokens[idx].raw) end
        return table.concat(out), 0
    end

    local joined = table.concat(concat_parts)
    -- Fast skip when block has no quote characters at all.
    local has_any = false
    for _, pair in ipairs(pairs_list) do
        if joined:find(pair.open, 1, true) then
            has_any = true
            break
        end
    end
    if not has_any then
        local out = {}
        for idx = first_idx, last_idx do table.insert(out, tokens[idx].raw) end
        return table.concat(out), 0
    end

    -- Find non-overlapping paired quote spans in `joined`.
    local spans = {}
    local scan = 1
    while scan <= #joined do
        local os, oe, pair = findNextOpen(joined, scan, pairs_list)
        if not os then break end
        local cs, ce = joined:find(pair.close, oe + 1, true)
        if not cs then
            -- Unclosed quote: do not guess or swallow the paragraph; skip this opener.
            scan = oe + 1
        else
            if cs > oe + 1 then
                table.insert(spans, { first = os, last = ce })
            end
            scan = ce + 1
        end
    end

    if #spans == 0 then
        local out = {}
        for idx = first_idx, last_idx do table.insert(out, tokens[idx].raw) end
        return table.concat(out), 0
    end

    -- Map global byte spans back onto individual text tokens.
    local piece_by_tok = {}
    for _, p in ipairs(pieces) do
        piece_by_tok[p.tok_idx] = p
    end

    local open_tag = '<span class="' .. EpubDialogueTagger.CLASS_NAME .. '">'
    local close_tag = "</span>"
    local out = {}
    local span_i = 1
    local span_count = #spans

    for idx = first_idx, last_idx do
        local tok = tokens[idx]
        local piece = piece_by_tok[idx]
        if not piece then
            table.insert(out, tok.raw)
        else
            local raw = piece.raw
            local p_start = piece.start_pos
            local p_end = piece.end_pos
            while span_i <= span_count and spans[span_i].last < p_start do
                span_i = span_i + 1
            end
            if span_i > span_count or spans[span_i].first > p_end then
                table.insert(out, raw)
            else
                local cursor = 1
                local local_len = #raw
                local k = span_i
                while k <= span_count and spans[k].first <= p_end do
                    local seg_start = math.max(1, spans[k].first - p_start + 1)
                    local seg_end = math.min(local_len, spans[k].last - p_start + 1)
                    if seg_start > cursor then
                        table.insert(out, raw:sub(cursor, seg_start - 1))
                    end
                    if seg_end >= seg_start then
                        table.insert(out, open_tag)
                        table.insert(out, raw:sub(seg_start, seg_end))
                        table.insert(out, close_tag)
                    end
                    cursor = seg_end + 1
                    if spans[k].last <= p_end then
                        k = k + 1
                    else
                        break
                    end
                end
                if cursor <= local_len then
                    table.insert(out, raw:sub(cursor))
                end
                span_i = k
            end
        end
    end

    return table.concat(out), #spans
end

-- Transforms an XHTML/HTML string, wrapping quoted dialogue utterances in
-- <span class="tf-dlg">...</span> without touching tags or existing dialogue subtrees.
-- Returns tagged_html, match_count.
function EpubDialogueTagger.tagXhtml(html, lang_or_opts)
    if type(html) ~= "string" or html == "" then return html or "", 0 end
    local lang = type(lang_or_opts) == "table" and lang_or_opts.lang or lang_or_opts
    local pairs_list = QUOTE_PAIRS_BY_LANG[lang or "all"] or QUOTE_PAIRS_BY_LANG.all
    -- Quick check: if none of the opening marks appear anywhere, return untouched.
    local any_mark = false
    for _, pair in ipairs(pairs_list) do
        if html:find(pair.open, 1, true) then
            any_mark = true
            break
        end
    end
    if not any_mark then return html, 0 end

    local tokens = tokenize(html)
    local out = {}
    local total_matches = 0
    local skip_stack = {}
    local skip_depth = 0
    local slice_start = nil

    local function flushSlice(up_to)
        if not slice_start then return end
        if up_to >= slice_start then
            local chunk, count = tagBlockSlice(tokens, slice_start, up_to, pairs_list)
            table.insert(out, chunk)
            total_matches = total_matches + count
        end
        slice_start = nil
    end

    for idx, tok in ipairs(tokens) do
        if tok.kind == "tag" then
            local name = tok.name
            local is_block = BLOCK_TAGS[name] == true
            local is_skip_tag = SKIP_TAGS[name] == true
            local is_dlg_class = (not tok.is_close) and hasDialogueClass(tok.raw)

            if is_block or is_skip_tag or is_dlg_class or skip_depth > 0 then
                flushSlice(idx - 1)
                table.insert(out, tok.raw)
                if not tok.is_self then
                    if tok.is_close then
                        -- Pop matching frame from skip_stack if present.
                        for s = #skip_stack, 1, -1 do
                            if skip_stack[s].name == name then
                                if skip_stack[s].skip then
                                    skip_depth = math.max(0, skip_depth - 1)
                                end
                                table.remove(skip_stack, s)
                                break
                            end
                        end
                    else
                        local should_skip = is_skip_tag or is_dlg_class
                        if should_skip or skip_depth > 0 then
                            table.insert(skip_stack, { name = name, skip = should_skip })
                            if should_skip then skip_depth = skip_depth + 1 end
                        end
                    end
                end
            else
                if not slice_start then slice_start = idx end
            end
        else
            if skip_depth > 0 then
                table.insert(out, tok.raw)
            else
                if not slice_start then slice_start = idx end
            end
        end
    end

    flushSlice(#tokens)
    return table.concat(out), total_matches
end

-- Exact 32-bit FNV-1a hash in pure Lua (uses 16-bit split multiplication so intermediate
-- products stay below 2^40, guaranteeing bit-identical output on LuaJIT doubles and Lua 5.4).
local function fnv1aHex(str)
    local hash = 2166136261
    for i = 1, #str do
        local b = str:byte(i)
        -- Pure arithmetic XOR for Lua 5.1/LuaJIT/5.4 compatibility without bitops dependency.
        local a, c, bit, res = hash, b, 1, 0
        while a > 0 or c > 0 do
            local ab = a % 2
            local cb = c % 2
            if ab ~= cb then res = res + bit end
            a = math.floor(a / 2)
            c = math.floor(c / 2)
            bit = bit * 2
        end
        local lo = res % 65536
        local hi = math.floor(res / 65536)
        hash = ((lo * 16777619) + (((hi * 16777619) % 65536) * 65536)) % 4294967296
    end
    return string.format("%08x", hash)
end

function EpubDialogueTagger.cacheDir(data_dir)
    local base = type(data_dir) == "string" and data_dir ~= "" and data_dir or "."
    base = base:gsub("/+$", "")
    return base .. "/" .. EpubDialogueTagger.CACHE_DIR_NAME
end

function EpubDialogueTagger.buildCachePath(source_path, data_dir, opts)
    opts = opts or {}
    local lang = opts.lang or "all"
    local size = tostring(opts.size or 0)
    local mtime = tostring(opts.mtime or 0)
    local filename = (source_path or "book.epub"):match("([^/\\]+)$") or "book.epub"
    local stem = filename:gsub("%.[eE][pP][uU][bB]$", "")
        :gsub("%.tf_dlg$", "")
        :gsub("[%c<>:\"/\\|%?%*]", "_")
        :gsub("%s+", "_")
    if stem == "" then stem = "book" end
    if #stem > 60 then stem = stem:sub(1, 60) end
    local hash = fnv1aHex(tostring(source_path) .. "|" .. size .. "|" .. mtime .. "|" .. lang)
    return EpubDialogueTagger.cacheDir(data_dir) .. "/" .. stem .. "_" .. hash .. EpubDialogueTagger.SUFFIX
end

function EpubDialogueTagger.isTaggedCopy(path)
    return type(path) == "string" and path:lower():match("%.tf_dlg%.epub$") ~= nil
end

function EpubDialogueTagger.getCachedCopyPath(source_path, data_dir, opts, lfs_mod)
    local path = EpubDialogueTagger.buildCachePath(source_path, data_dir, opts)
    if not path then return nil end
    local ok_lfs, lfs = true, lfs_mod
    if not lfs then
        ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
        if not ok_lfs then ok_lfs, lfs = pcall(require, "lfs") end
    end
    if ok_lfs and lfs and type(lfs.attributes) == "function" then
        local attr = lfs.attributes(path)
        if attr and (attr.size or 0) > 0 then
            return path
        end
    else
        local f = io.open(path, "rb")
        if f then
            local size = f:seek("end") or 0
            f:close()
            if size > 0 then return path end
        end
    end
    return nil
end

function EpubDialogueTagger.hasCachedCopy(source_path, data_dir, opts, lfs_mod)
    return EpubDialogueTagger.getCachedCopyPath(source_path, data_dir, opts, lfs_mod) ~= nil
end

local function isHtmlEntry(name)
    if type(name) ~= "string" then return false end
    local lower = name:lower()
    return lower:match("%.xhtml$") ~= nil
        or lower:match("%.html$") ~= nil
        or lower:match("%.htm$") ~= nil
end

local function isRegularFileEntry(entry)
    if type(entry) ~= "table" or type(entry.path) ~= "string" or entry.path == "" then
        return false
    end
    if entry.path:sub(-1) == "/" then return false end
    if entry.mode == nil or entry.mode == "file" then return true end
    -- libarchive / POSIX S_IFMT regular file bit (0100000 = 32768)
    if type(entry.mode) == "number" then
        return math.floor(entry.mode / 32768) % 2 == 1
    end
    return false
end

-- Archive backend using KOReader's built-in ffi/archiver (libarchive).
-- Streams entries one by one instead of buffering the entire EPUB in RAM so large
-- illustrated books (50–200 MB) never trigger OOM on low-RAM e-ink devices.
local function processWithArchiver(source_path, tmp_dest, lang, on_progress)
    local ok_arch, Archiver = pcall(require, "ffi/archiver")
    if not ok_arch or type(Archiver) ~= "table"
            or not Archiver.Reader or not Archiver.Writer then
        return nil, "archiver_unavailable"
    end

    -- First lightweight metadata pass: count file entries and grab the tiny mimetype entry
    -- (~20 bytes) so it can always be written first and uncompressed per EPUB spec.
    local scan_reader = Archiver.Reader:new()
    if not scan_reader:open(source_path) then
        return nil, "failed to open source epub"
    end
    local total = 0
    local mimetype_data = nil
    for entry in scan_reader:iterate() do
        if isRegularFileEntry(entry) then
            total = total + 1
            if entry.path == "mimetype" then
                mimetype_data = scan_reader:extractToMemory(entry.index) or "application/epub+zip"
            end
        end
    end
    scan_reader:close()

    local reader = Archiver.Reader:new()
    if not reader:open(source_path) then
        return nil, "failed to open source epub"
    end

    local writer = Archiver.Writer:new()
    local open_ok = writer:open(tmp_dest, "zip")
    if not open_ok then
        reader:close()
        return nil, "failed to create output epub"
    end

    local stats = { files_scanned = 0, files_modified = 0, quotes_tagged = 0 }
    local processed = 0
    local write_ok, write_err = pcall(function()
        if mimetype_data ~= nil then
            if type(writer.setZipCompressionStore) == "function" then
                pcall(writer.setZipCompressionStore, writer)
            end
            writer:addFileFromMemory("mimetype", mimetype_data)
            if type(writer.setZipCompressionDeflate) == "function" then
                pcall(writer.setZipCompressionDeflate, writer)
            end
            processed = processed + 1
            if type(on_progress) == "function" then
                on_progress(processed, total)
            end
        end

        for entry in reader:iterate() do
            if isRegularFileEntry(entry) and entry.path ~= "mimetype" then
                local data = reader:extractToMemory(entry.index) or ""
                if isHtmlEntry(entry.path) then
                    stats.files_scanned = stats.files_scanned + 1
                    local tagged, count = EpubDialogueTagger.tagXhtml(data, lang)
                    if count > 0 then
                        data = tagged
                        stats.files_modified = stats.files_modified + 1
                        stats.quotes_tagged = stats.quotes_tagged + count
                    end
                end
                writer:addFileFromMemory(entry.path, data)
                data = nil
                processed = processed + 1
                if type(on_progress) == "function" then
                    on_progress(processed, total)
                end
            end
        end
    end)
    pcall(reader.close, reader)
    pcall(writer.close, writer)
    if not write_ok then
        os.remove(tmp_dest)
        return nil, tostring(write_err)
    end
    return stats
end

-- Archive backend using pluggable zip_io (for tests or alternative runtimes).
local function processWithCustomIO(zip_io, source_path, tmp_dest, lang, on_progress)
    local entries, read_err = zip_io.readAll(source_path)
    if not entries then return nil, read_err or "failed to read epub" end

    table.sort(entries, function(a, b)
        if a.path == "mimetype" then return true end
        if b.path == "mimetype" then return false end
        return a.path < b.path
    end)

    local stats = { files_scanned = 0, files_modified = 0, quotes_tagged = 0 }
    local out_entries = {}
    local total = #entries
    for i, item in ipairs(entries) do
        local data = item.data or ""
        if isHtmlEntry(item.path) then
            stats.files_scanned = stats.files_scanned + 1
            local tagged, count = EpubDialogueTagger.tagXhtml(data, lang)
            if count > 0 then
                data = tagged
                stats.files_modified = stats.files_modified + 1
                stats.quotes_tagged = stats.quotes_tagged + count
            end
        end
        table.insert(out_entries, {
            path = item.path,
            data = data,
            store = item.path == "mimetype",
        })
        if type(on_progress) == "function" then
            on_progress(i, total)
        end
    end

    local ok, write_err = zip_io.writeAll(tmp_dest, out_entries)
    if not ok then
        os.remove(tmp_dest)
        return nil, write_err or "failed to write epub"
    end
    return stats
end

function EpubDialogueTagger.processEpub(source_path, dest_path, opts)
    opts = opts or {}
    if type(source_path) ~= "string" or source_path == "" then
        return nil, "invalid source path"
    end
    if type(dest_path) ~= "string" or dest_path == "" then
        return nil, "invalid destination path"
    end
    if source_path == dest_path then
        return nil, "destination must differ from source"
    end
    local zip_io = opts.zip_io
    if not zip_io then
        local f = io.open(source_path, "rb")
        if not f then return nil, "source file not readable" end
        f:close()
    end

    local remove_fn = (zip_io and zip_io.remove) or os.remove
    local rename_fn = (zip_io and zip_io.rename) or os.rename

    local lang = opts.lang or "all"
    local tmp_dest = dest_path .. ".tmp"
    remove_fn(tmp_dest)

    local stats, err
    if zip_io then
        stats, err = processWithCustomIO(zip_io, source_path, tmp_dest, lang, opts.on_progress)
    else
        stats, err = processWithArchiver(source_path, tmp_dest, lang, opts.on_progress)
    end
    if not stats then
        remove_fn(tmp_dest)
        return nil, err
    end

    remove_fn(dest_path)
    local renamed, rename_err = rename_fn(tmp_dest, dest_path)
    if not renamed then
        remove_fn(tmp_dest)
        return nil, tostring(rename_err or "failed to finalize output file")
    end
    return dest_path, stats
end

function EpubDialogueTagger.listCachedCopies(data_dir, lfs_mod)
    local ok_lfs, lfs = true, lfs_mod
    if not lfs then
        ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
        if not ok_lfs then ok_lfs, lfs = pcall(require, "lfs") end
    end
    if not (ok_lfs and type(lfs) == "table" and type(lfs.dir) == "function") then
        return {}, 0
    end
    local dir = EpubDialogueTagger.cacheDir(data_dir)
    local files = {}
    local total_bytes = 0
    local ok, iter, state = pcall(lfs.dir, dir)
    if not ok or not iter then return files, 0 end
    for name in iter, state do
        if name:lower():match("%.tf_dlg%.epub$") then
            local full = dir .. "/" .. name
            local attr = type(lfs.attributes) == "function" and lfs.attributes(full) or nil
            local size = attr and tonumber(attr.size) or 0
            total_bytes = total_bytes + size
            table.insert(files, { name = name, path = full, size = size })
        end
    end
    table.sort(files, function(a, b) return a.name < b.name end)
    return files, total_bytes, #files
end

function EpubDialogueTagger.clearCache(data_dir, lfs_mod, exclude_path, remove_fn)
    local files = EpubDialogueTagger.listCachedCopies(data_dir, lfs_mod)
    local removed = 0
    local freed_bytes = 0
    local skipped_active = 0
    local do_remove = type(remove_fn) == "function" and remove_fn or os.remove
    local normalized_exclude = type(exclude_path) == "string" and exclude_path:gsub("\\", "/") or nil
    for _, item in ipairs(files) do
        local normalized_item = item.path:gsub("\\", "/")
        if normalized_exclude and normalized_item == normalized_exclude then
            skipped_active = skipped_active + 1
        elseif item.name:lower():match("%.tf_dlg%.epub$") and not item.name:find("[/\\]") then
            local ok = do_remove(item.path)
            if ok then
                removed = removed + 1
                freed_bytes = freed_bytes + (tonumber(item.size) or 0)
            end
        end
    end
    return removed, freed_bytes, skipped_active
end

return EpubDialogueTagger
