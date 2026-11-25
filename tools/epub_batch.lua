-- SPDX-FileCopyrightText: Copyright (C) 2026 THE-XSX
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- Typefolio (文笺) - KOReader plugin
-- Released under the GNU Affero General Public License v3.0 or later.
-- See the LICENSE file in the project root for the full license text.

-- tools/epub_batch.lua
-- Batch and single-book EPUB dialogue tagging:
--   1. Export to a designated folder with normalized "Title-Author(-文笺).epub" naming.
--   2. In-place overwrite with optional original-book backup and .sdr progress preservation.

local item_path = debug.getinfo(1, "S").source:sub(2)
local PLUGIN_ROOT = item_path:match("(.*[/\\]typefolio%.koplugin[/\\])")
    or item_path:match("(.*[/\\])tools[/\\]")
    or item_path:match("(.*[/\\])")
    or "plugins/typefolio.koplugin/"

local ModuleLoader = dofile(PLUGIN_ROOT .. "core/module_loader.lua")
local EpubDialogueTagger = ModuleLoader.load(PLUGIN_ROOT, "tools/epub_dialogue_tagger.lua")
local BookContext = ModuleLoader.load(PLUGIN_ROOT, "core/book_context.lua")

local EpubBatch = {}

EpubBatch.DEFAULT_BACKUP_DIR_NAME = ".typefolio_backup"

local function getLfs(lfs_mod)
    if type(lfs_mod) == "table" then return lfs_mod end
    local ok, mod = pcall(require, "libs/libkoreader-lfs")
    if ok and type(mod) == "table" then return mod end
    ok, mod = pcall(require, "lfs")
    if ok and type(mod) == "table" then return mod end
    return nil
end

local function normalizeDir(path)
    if type(path) ~= "string" then return "" end
    local clean = path:gsub("\\", "/")
    if #clean > 1 then
        clean = clean:gsub("/+$", "")
    end
    return clean
end

local function splitPath(path)
    local clean = normalizeDir(path)
    local dir, name = clean:match("^(.*)/([^/]+)$")
    if not dir then
        return ".", clean
    end
    if dir == "" then dir = "/" end
    return dir, name
end

local function makePath(dir, lfs_mod)
    dir = normalizeDir(dir)
    if dir == "" or dir == "." or dir == "/" then return true end
    local ok_util, util = pcall(require, "util")
    if ok_util and util and type(util.makePath) == "function" then
        return util.makePath(dir)
    end
    local lfs = getLfs(lfs_mod)
    if not lfs or type(lfs.mkdir) ~= "function" then return false, "lfs_unavailable" end
    if lfs.attributes(dir, "mode") == "directory" then return true end
    local parent = dir:match("^(.*)/[^/]+$")
    if parent and parent ~= "" and parent ~= dir then
        local ok_p, err_p = makePath(parent, lfs)
        if not ok_p then return false, err_p end
    end
    local ok, err = lfs.mkdir(dir)
    if ok or lfs.attributes(dir, "mode") == "directory" then return true end
    return false, err
end

local function copyFileStream(src, dst)
    local in_f, in_err = io.open(src, "rb")
    if not in_f then return false, tostring(in_err or "cannot open source") end
    local tmp = dst .. ".copy_tmp"
    os.remove(tmp)
    local out_f, out_err = io.open(tmp, "wb")
    if not out_f then
        in_f:close()
        return false, tostring(out_err or "cannot create destination")
    end
    local chunk_size = 65536
    local copy_ok, copy_err = pcall(function()
        while true do
            local chunk = in_f:read(chunk_size)
            if not chunk then break end
            local ok_w, w_err = out_f:write(chunk)
            if not ok_w then error(w_err or "write error") end
        end
    end)
    in_f:close()
    out_f:close()
    if not copy_ok then
        os.remove(tmp)
        return false, tostring(copy_err)
    end
    os.remove(dst)
    local ok_ren, ren_err = os.rename(tmp, dst)
    if not ok_ren then
        os.remove(tmp)
        return false, tostring(ren_err or "rename failed")
    end
    return true
end

local function moveFileSafe(src, dst)
    if normalizeDir(src) == normalizeDir(dst) then return true end
    os.remove(dst)
    local ok = os.rename(src, dst)
    if ok then return true end
    local copied, copy_err = copyFileStream(src, dst)
    if not copied then return false, copy_err end
    local removed, rem_err = os.remove(src)
    if not removed then
        return true, tostring(rem_err or "source remove failed after copy")
    end
    return true
end

function EpubBatch.defaultBackupDir(source_dir)
    local base = normalizeDir(source_dir)
    if base == "" then return nil end
    if base == "/" then return "/" .. EpubBatch.DEFAULT_BACKUP_DIR_NAME end
    return base .. "/" .. EpubBatch.DEFAULT_BACKUP_DIR_NAME
end

function EpubBatch.normalizeSettings(raw)
    raw = type(raw) == "table" and raw or {}
    local mode = raw.mode == "overwrite" and "overwrite" or "export"
    return {
        source_dir = type(raw.source_dir) == "string" and raw.source_dir ~= "" and normalizeDir(raw.source_dir) or nil,
        mode = mode,
        target_dir = type(raw.target_dir) == "string" and raw.target_dir ~= "" and normalizeDir(raw.target_dir) or nil,
        backup_enabled = raw.backup_enabled ~= false,
        backup_dir = type(raw.backup_dir) == "string" and raw.backup_dir ~= "" and normalizeDir(raw.backup_dir) or nil,
        keep_original_name = raw.keep_original_name ~= false,
        append_tag = raw.append_tag ~= false,
        recursive = raw.recursive == true,
        preserve_subdirs = raw.preserve_subdirs == true,
        skip_tagged = raw.skip_tagged ~= false,
        lang = (raw.lang == "cn" or raw.lang == "en" or raw.lang == "all") and raw.lang or "all",
    }
end

local function shouldExcludeDir(full_path, name, exclude_dirs)
    if name == "." or name == ".." then return true end
    if name:sub(1, 1) == "." then return true end
    if name:lower():match("%.sdr$") then return true end
    if name == EpubDialogueTagger.CACHE_DIR_NAME then return true end
    if name == EpubBatch.DEFAULT_BACKUP_DIR_NAME then return true end
    local norm = normalizeDir(full_path)
    for _, ex in ipairs(exclude_dirs or {}) do
        if ex ~= "" and norm == ex then return true end
    end
    return false
end

function EpubBatch.scanFolder(source_dir, opts, lfs_mod)
    opts = opts or {}
    local lfs = getLfs(lfs_mod)
    if not lfs or type(lfs.dir) ~= "function" then
        return {}, "filesystem_unavailable"
    end
    local root = normalizeDir(source_dir)
    if root == "" or lfs.attributes(root, "mode") ~= "directory" then
        return {}, "invalid_source_dir"
    end

    local exclude_dirs = {}
    if type(opts.target_dir) == "string" and opts.target_dir ~= "" then
        local t = normalizeDir(opts.target_dir)
        if t ~= root then table.insert(exclude_dirs, t) end
    end
    if type(opts.backup_dir) == "string" and opts.backup_dir ~= "" then
        local b = normalizeDir(opts.backup_dir)
        if b ~= root then table.insert(exclude_dirs, b) end
    end

    local recursive = opts.recursive == true
    local items = {}

    local function walk(dir, rel_dir)
        local ok, iter, state = pcall(lfs.dir, dir)
        if not ok or not iter then return end
        local subdirs = {}
        local files = {}
        for entry_name in iter, state do
            if entry_name ~= "." and entry_name ~= ".." then
                local full = (dir == "/" and "" or dir) .. "/" .. entry_name
                local mode = lfs.attributes(full, "mode")
                if mode == "directory" then
                    if recursive and not shouldExcludeDir(full, entry_name, exclude_dirs) then
                        table.insert(subdirs, {
                            path = full,
                            rel = rel_dir ~= "" and (rel_dir .. "/" .. entry_name) or entry_name,
                        })
                    end
                elseif mode == "file" then
                    local lower = entry_name:lower()
                    if lower:match("%.epub$")
                            and not lower:match("%.tf_dlg%.epub$")
                            and not lower:match("%.tf_work%.epub$")
                            and not lower:match("%.tf_old$") then
                        local size = tonumber(lfs.attributes(full, "size")) or 0
                        table.insert(files, {
                            path = full,
                            dir = dir,
                            rel_dir = rel_dir,
                            name = entry_name,
                            size = size,
                        })
                    end
                end
            end
        end
        table.sort(files, function(a, b) return a.name < b.name end)
        for _, f in ipairs(files) do
            table.insert(items, f)
        end
        table.sort(subdirs, function(a, b) return a.path < b.path end)
        for _, d in ipairs(subdirs) do
            walk(d.path, d.rel)
        end
    end

    walk(root, "")
    return items
end

local function hasExistingSidecar(book_path, doc_settings_mod, lfs_mod)
    local lfs = getLfs(lfs_mod)
    if not (lfs and doc_settings_mod and type(doc_settings_mod.getSidecarDir) == "function") then
        return false
    end
    local ok, sdr_dir = pcall(doc_settings_mod.getSidecarDir, doc_settings_mod, book_path)
    if not ok or type(sdr_dir) ~= "string" or sdr_dir == "" then return false end
    return lfs.attributes(sdr_dir, "mode") == "directory"
end

local function sanitizeSettingXPointer(ds)
    if not ds then return end
    local xp = ds:readSetting("last_xpointer")
    if type(xp) == "string" and xp ~= "" then
        local safe_xp = BookContext.blockPath(xp) or xp:gsub("/text%(%)[^/]*$", "")
        ds:saveSetting("last_xpointer", safe_xp)
    end
end

local function enableDialogueTweakOnSettings(ds)
    if not ds then return end
    local tweaks = ds:readSetting("style_tweaks") or {}
    if type(tweaks) == "table" then
        tweaks["99_typefolio.css"] = true
        ds:saveSetting("style_tweaks", tweaks)
    end
end

local function syncSidecar(src_path, dest_path, lfs_mod)
    local ok_ds, DocSettings = pcall(require, "docsettings")
    if not (ok_ds and DocSettings) then return end
    pcall(function()
        if normalizeDir(src_path) == normalizeDir(dest_path) then
            if hasExistingSidecar(src_path, DocSettings, lfs_mod) then
                local ds = DocSettings:open(src_path)
                if ds then
                    sanitizeSettingXPointer(ds)
                    enableDialogueTweakOnSettings(ds)
                    ds:flush()
                end
            end
            return
        end

        if not hasExistingSidecar(src_path, DocSettings, lfs_mod) then
            return
        end
        local src_ds = DocSettings:open(src_path)
        local dest_ds = DocSettings:open(dest_path)
        if not (src_ds and dest_ds) then return end
        if type(src_ds.data) == "table" then
            for k, v in pairs(src_ds.data) do
                if k ~= "typefolio_cached_copy" and k ~= "typefolio_auto_open_copy" then
                    dest_ds:saveSetting(k, v)
                end
            end
        end
        sanitizeSettingXPointer(dest_ds)
        enableDialogueTweakOnSettings(dest_ds)
        dest_ds:flush()
    end)
end

local function removeSidecarSafe(book_path)
    local ok_ds, DocSettings = pcall(require, "docsettings")
    if not (ok_ds and DocSettings and type(DocSettings.getSidecarDir) == "function") then return end
    pcall(function()
        local sdr = DocSettings:getSidecarDir(book_path)
        if type(sdr) == "string" and sdr ~= "" then
            local ok_util, util = pcall(require, "util")
            if ok_util and util and type(util.purgeDir) == "function" then
                util.purgeDir(sdr)
            end
        end
    end)
end

function EpubBatch.processOne(item, opts, lfs_mod)
    opts = opts or {}
    local lfs = getLfs(lfs_mod)
    local src_path = type(item) == "table" and item.path or item
    if type(src_path) ~= "string" or src_path == "" then
        return { status = "failed", source_path = src_path, reason = "invalid_source" }
    end

    local active = opts.active_doc_file and normalizeDir(opts.active_doc_file) or nil
    if active and normalizeDir(src_path) == active then
        return { status = "skipped", source_path = src_path, reason = "currently_open" }
    end

    local skip_tagged = opts.skip_tagged ~= false
    local mode = opts.mode == "overwrite" and "overwrite" or "export"
    local append_tag = opts.append_tag ~= false
    local lang = opts.lang or "all"

    local inspect = EpubDialogueTagger.inspectEpub(src_path, {
        extract_metadata = (mode == "export" or opts.keep_original_name == false),
        scan_html_fallback = skip_tagged,
    })
    if inspect.error then
        return { status = "failed", source_path = src_path, reason = inspect.error }
    end

    if skip_tagged and (inspect.has_marker or inspect.has_tf_dlg) then
        return {
            status = "skipped",
            source_path = src_path,
            reason = "already_tagged",
            title = inspect.title,
        }
    end

    local src_dir, src_name = splitPath(src_path)
    local rel_dir = type(item) == "table" and item.rel_dir or ""

    if mode == "export" then
        local base_target = normalizeDir(opts.target_dir)
        if base_target == "" then
            return { status = "failed", source_path = src_path, reason = "missing_target_dir" }
        end
        local out_dir = (opts.preserve_subdirs and rel_dir ~= "")
            and (base_target .. "/" .. rel_dir)
            or base_target
        local ok_dir, dir_err = makePath(out_dir, lfs)
        if not ok_dir then
            return { status = "failed", source_path = src_path, reason = tostring(dir_err or "mkdir_failed") }
        end

        local formatted = EpubDialogueTagger.buildFormattedFilename(src_path, inspect, {
            append_tag = append_tag,
        })
        local cand_path = out_dir .. "/" .. formatted
        local dest_path = cand_path
        if lfs and lfs.attributes(cand_path) then
            if skip_tagged then
                return {
                    status = "skipped",
                    source_path = src_path,
                    dest_path = cand_path,
                    reason = "target_exists",
                }
            end
            dest_path = EpubDialogueTagger.uniqueDestPath(out_dir, formatted, lfs)
        end

        local out_path, stats_or_err = EpubDialogueTagger.processEpub(src_path, dest_path, {
            lang = lang,
        })
        if not out_path then
            return {
                status = "failed",
                source_path = src_path,
                dest_path = dest_path,
                reason = tostring(stats_or_err or "process_failed"),
            }
        end

        if opts.sync_sidecar ~= false then
            syncSidecar(src_path, out_path, lfs)
        end

        return {
            status = "done",
            mode = "export",
            source_path = src_path,
            dest_path = out_path,
            stats = type(stats_or_err) == "table" and stats_or_err or {},
        }
    end

    -- Overwrite mode: always process into a temporary work file first so the
    -- original EPUB is never touched until generation succeeds completely.
    local keep_name = opts.keep_original_name ~= false
    local dest_path = src_path
    if not keep_name then
        local formatted = EpubDialogueTagger.buildFormattedFilename(src_path, inspect, {
            append_tag = append_tag,
        })
        dest_path = (src_dir == "/" and "" or src_dir) .. "/" .. formatted
        if normalizeDir(dest_path) ~= normalizeDir(src_path) and lfs and lfs.attributes(dest_path) then
            if skip_tagged then
                return {
                    status = "skipped",
                    source_path = src_path,
                    dest_path = dest_path,
                    reason = "target_exists",
                }
            end
            dest_path = EpubDialogueTagger.uniqueDestPath(src_dir, formatted, lfs)
        end
    end

    local tmp_work = src_path .. ".tf_work.epub"
    os.remove(tmp_work)
    local out_work, stats_or_err = EpubDialogueTagger.processEpub(src_path, tmp_work, {
        lang = lang,
    })
    if not out_work then
        os.remove(tmp_work)
        return {
            status = "failed",
            source_path = src_path,
            reason = tostring(stats_or_err or "process_failed"),
        }
    end

    local backup_path = nil
    if opts.backup_enabled ~= false then
        local backup_root = normalizeDir(opts.backup_dir)
        if backup_root == "" then
            backup_root = EpubBatch.defaultBackupDir(opts.source_dir or src_dir)
        end
        local backup_dir = (rel_dir ~= "" and backup_root .. "/" .. rel_dir) or backup_root
        local ok_bdir, bdir_err = makePath(backup_dir, lfs)
        if not ok_bdir then
            os.remove(tmp_work)
            return {
                status = "failed",
                source_path = src_path,
                reason = tostring(bdir_err or "backup_mkdir_failed"),
            }
        end
        backup_path = EpubDialogueTagger.uniqueDestPath(backup_dir, src_name, lfs)
        local moved, move_err = moveFileSafe(src_path, backup_path)
        if not moved then
            os.remove(tmp_work)
            return {
                status = "failed",
                source_path = src_path,
                reason = tostring(move_err or "backup_move_failed"),
            }
        end
        local ok_ren, ren_err = moveFileSafe(tmp_work, dest_path)
        if not ok_ren then
            -- Attempt rollback from backup.
            moveFileSafe(backup_path, src_path)
            os.remove(tmp_work)
            return {
                status = "failed",
                source_path = src_path,
                reason = tostring(ren_err or "finalize_failed"),
            }
        end
    else
        local old_hold = src_path .. ".tf_old"
        os.remove(old_hold)
        local held, hold_err = os.rename(src_path, old_hold)
        if not held then
            os.remove(tmp_work)
            return {
                status = "failed",
                source_path = src_path,
                reason = tostring(hold_err or "replace_lock_failed"),
            }
        end
        local ok_ren, ren_err = moveFileSafe(tmp_work, dest_path)
        if not ok_ren then
            os.rename(old_hold, src_path)
            os.remove(tmp_work)
            return {
                status = "failed",
                source_path = src_path,
                reason = tostring(ren_err or "finalize_failed"),
            }
        end
        os.remove(old_hold)
    end

    if normalizeDir(dest_path) ~= normalizeDir(src_path) then
        syncSidecar(src_path, dest_path, lfs)
        removeSidecarSafe(src_path)
    else
        syncSidecar(src_path, src_path, lfs)
    end

    return {
        status = "done",
        mode = "overwrite",
        source_path = src_path,
        dest_path = dest_path,
        backup_path = backup_path,
        stats = type(stats_or_err) == "table" and stats_or_err or {},
    }
end

-- Runs a list of scanned items one per event-loop tick via UIManager:scheduleIn
-- so KOReader remains responsive on e-ink devices and allows mid-run cancellation.
function EpubBatch.runAsync(items, opts, callbacks)
    callbacks = callbacks or {}
    local UIManager = callbacks.ui_manager or require("ui/uimanager")
    local schedule = callbacks.schedule or function(delay, fn)
        return UIManager:scheduleIn(delay, fn)
    end

    local state = {
        cancelled = false,
        index = 0,
        total = #items,
        done = 0,
        skipped = 0,
        failed = 0,
        total_quotes = 0,
        results = {},
    }

    local function finish()
        if type(callbacks.on_complete) == "function" then
            callbacks.on_complete(state)
        end
    end

    local function step()
        if state.cancelled then
            finish()
            return
        end
        state.index = state.index + 1
        if state.index > state.total then
            finish()
            return
        end

        local item = items[state.index]
        if type(callbacks.on_progress) == "function" then
            callbacks.on_progress(state.index, state.total, item, state)
        end

        schedule(0.01, function()
            if state.cancelled then
                finish()
                return
            end
            local res = EpubBatch.processOne(item, opts)
            table.insert(state.results, res)
            if res.status == "done" then
                state.done = state.done + 1
                state.total_quotes = state.total_quotes + (tonumber(res.stats and res.stats.quotes_tagged) or 0)
            elseif res.status == "skipped" then
                state.skipped = state.skipped + 1
            else
                state.failed = state.failed + 1
            end
            schedule(0.01, step)
        end)
    end

    schedule(0.01, step)
    return {
        cancel = function()
            state.cancelled = true
        end,
        getState = function()
            return state
        end,
    }
end

return EpubBatch
