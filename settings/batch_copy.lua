-- SPDX-FileCopyrightText: Copyright (C) 2026 THE-XSX
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- Typefolio (文笺) - KOReader plugin
-- Released under the GNU Affero General Public License v3.0 or later.
-- See the LICENSE file in the project root for the full license text.

-- settings/batch_copy.lua
-- UI menus and interactive flows for batch EPUB dialogue processing,
-- normalized "Title-Author(-文笺).epub" folder export, and in-place overwrite with backup.

local item_path = debug.getinfo(1, "S").source:sub(2)
local PLUGIN_ROOT = item_path:match("(.*[/\\]typefolio%.koplugin[/\\])")
    or item_path:match("(.*[/\\])settings[/\\]")
    or item_path:match("(.*[/\\])")
    or "plugins/typefolio.koplugin/"

local ModuleLoader = dofile(PLUGIN_ROOT .. "core/module_loader.lua")
local EpubBatch = ModuleLoader.load(PLUGIN_ROOT, "tools/epub_batch.lua")
local EpubDialogueTagger = ModuleLoader.load(PLUGIN_ROOT, "tools/epub_dialogue_tagger.lua")

local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")

local BatchCopySettings = {}

local function getDefaultDir(ctx)
    if ctx.getDefaultBrowseDir then
        local dir = ctx.getDefaultBrowseDir()
        if type(dir) == "string" and dir ~= "" then return dir end
    end
    local g_settings = rawget(_G, "G_reader_settings")
    if g_settings and type(g_settings.readSetting) == "function" then
        local lastdir = g_settings:readSetting("lastdir")
        if type(lastdir) == "string" and lastdir ~= "" then return lastdir end
    end
    return "/"
end

local function readSettings(ctx)
    if ctx.getBatchSettings then
        return EpubBatch.normalizeSettings(ctx.getBatchSettings())
    end
    return EpubBatch.normalizeSettings({})
end

local function saveSettings(ctx, settings)
    local normalized = EpubBatch.normalizeSettings(settings)
    if ctx.saveBatchSettings then
        ctx.saveBatchSettings(normalized)
    end
    return normalized
end

local function chooseDirectory(initial_dir, on_confirm)
    local ok, PathChooser = pcall(require, "ui/widget/pathchooser")
    if not ok or type(PathChooser) ~= "table" then return end
    UIManager:show(PathChooser:new{
        path = initial_dir or "/",
        show_files = false,
        select_directory = true,
        select_file = false,
        onConfirm = function(dir_path)
            if type(dir_path) == "string" and dir_path ~= "" and type(on_confirm) == "function" then
                on_confirm(dir_path)
            end
        end,
    })
end

local function shortenPath(path, max_len)
    if type(path) ~= "string" or path == "" then return "" end
    max_len = max_len or 32
    if #path <= max_len then return path end
    return "…" .. path:sub(#path - max_len + 4)
end

local function previewNamingExample(settings, tr)
    if settings.mode == "overwrite" and settings.keep_original_name then
        return tr("Keep original filename")
    end
    if settings.append_tag then
        return tr("Title-Author-文笺.epub")
    end
    return tr("Title-Author.epub")
end

local function buildSummaryReport(ctx, state, settings)
    local tr = ctx.tr
    local T = ctx.T
    local lines = {
        "--------------------------------------------------",
        state.cancelled
            and tr("Batch processing cancelled.")
            or tr("Batch processing complete."),
        "--------------------------------------------------",
        T(tr("Total scanned: %1"), tostring(state.total or 0)),
        T(tr("Processed: %1"), tostring(state.done or 0)),
        T(tr("Skipped: %1"), tostring(state.skipped or 0)),
        T(tr("Failed: %1"), tostring(state.failed or 0)),
        T(tr("Total dialogue runs tagged: %1"), tostring(state.total_quotes or 0)),
        "",
    }

    if settings.mode == "export" then
        table.insert(lines, T(tr("Output folder: %1"), tostring(settings.target_dir or "")))
    elseif settings.backup_enabled then
        local bdir = settings.backup_dir or EpubBatch.defaultBackupDir(settings.source_dir)
        table.insert(lines, T(tr("Backup folder: %1"), tostring(bdir or "")))
    end

    if #(state.results or {}) > 0 then
        table.insert(lines, "")
        table.insert(lines, tr("Details:"))
        for _, res in ipairs(state.results) do
            local src_name = (res.source_path or ""):match("([^/\\]+)$") or tostring(res.source_path or "")
            if res.status == "done" then
                local dest_name = (res.dest_path or ""):match("([^/\\]+)$") or src_name
                local quotes = tonumber(res.stats and res.stats.quotes_tagged) or 0
                table.insert(lines, string.format("  [OK] %s -> %s (%d)", src_name, dest_name, quotes))
            elseif res.status == "skipped" then
                table.insert(lines, string.format("  [SKIP] %s (%s)", src_name, tostring(res.reason or "")))
            else
                table.insert(lines, string.format("  [ERR] %s (%s)", src_name, tostring(res.reason or "")))
            end
        end
    end
    return table.concat(lines, "\n")
end

function BatchCopySettings.runBatchWizard(ctx)
    local tr = ctx.tr
    local T = ctx.T
    local Screen = ctx.Screen
    local showInfo = ctx.showInfo
    local notify = ctx.notify
    local settings = readSettings(ctx)

    local source_dir = settings.source_dir or getDefaultDir(ctx)
    if settings.mode == "export" and (not settings.target_dir or settings.target_dir == "") then
        showInfo(tr("Please choose a target output folder first."))
        return
    end

    local scan_opts = {
        recursive = settings.recursive,
        target_dir = settings.target_dir,
        backup_dir = settings.backup_dir or EpubBatch.defaultBackupDir(source_dir),
    }
    local items, scan_err = EpubBatch.scanFolder(source_dir, scan_opts)
    if scan_err then
        showInfo(T(tr("Cannot scan source folder: %1"), tostring(scan_err)))
        return
    end
    if #items == 0 then
        showInfo(tr("No EPUB files found in the selected source folder."))
        return
    end

    local mode_desc
    if settings.mode == "export" then
        mode_desc = T(tr("Save to folder: %1\nNaming: %2"),
            tostring(settings.target_dir),
            previewNamingExample(settings, tr))
    else
        local bdir = settings.backup_enabled
            and (settings.backup_dir or EpubBatch.defaultBackupDir(source_dir))
            or tr("Disabled")
        mode_desc = T(tr("Overwrite original files\nBackup: %1\nNaming: %2"),
            tostring(bdir),
            previewNamingExample(settings, tr))
    end

    UIManager:show(ConfirmBox:new{
        text = T(tr("Found %1 EPUB file(s) in:\n%2\n\n%3\n\nStart batch processing?"),
            tostring(#items), source_dir, mode_desc),
        ok_text = tr("Start"),
        cancel_text = tr("Cancel"),
        ok_callback = function()
            local active_doc = ctx.ui and ctx.ui.document and ctx.ui.document.file or nil
            local progress_box = nil
            local runner = nil

            local function closeProgress()
                if progress_box then
                    UIManager:close(progress_box)
                    progress_box = nil
                end
            end

            local function showProgress(idx, total, item)
                closeProgress()
                local name = (item and item.name) or ""
                progress_box = ConfirmBox:new{
                    text = T(tr("Processing %1 / %2:\n%3"), tostring(idx), tostring(total), name),
                    ok_text = tr("Cancel"),
                    cancel_text = tr("Hide"),
                    dismissable = false,
                    ok_callback = function()
                        if runner then runner.cancel() end
                        notify(tr("Cancelling after current book…"))
                    end,
                }
                UIManager:show(progress_box)
            end

            local run_opts = {
                mode = settings.mode,
                source_dir = source_dir,
                target_dir = settings.target_dir,
                backup_enabled = settings.backup_enabled,
                backup_dir = settings.backup_dir,
                keep_original_name = settings.keep_original_name,
                append_tag = settings.append_tag,
                preserve_subdirs = settings.preserve_subdirs,
                skip_tagged = settings.skip_tagged,
                lang = settings.lang,
                active_doc_file = active_doc,
            }

            runner = EpubBatch.runAsync(items, run_opts, {
                ui_manager = UIManager,
                on_progress = showProgress,
                on_complete = function(state)
                    closeProgress()
                    if ctx.refreshFileManager then
                        pcall(ctx.refreshFileManager)
                    end
                    local report = buildSummaryReport(ctx, state, settings)
                    UIManager:show(TextViewer:new{
                        title = tr("Batch dialogue processing report"),
                        text = report,
                        text_type = "code",
                        height = math.floor(Screen:getHeight() * 0.8),
                    })
                end,
            })
        end,
    })
end

function BatchCopySettings.exportCurrentBook(ctx)
    local tr = ctx.tr
    local T = ctx.T
    local showInfo = ctx.showInfo
    local notify = ctx.notify
    local doc_file = ctx.ui and ctx.ui.document and ctx.ui.document.file
    if type(doc_file) ~= "string" or not doc_file:lower():match("%.epub$") then
        showInfo(tr("Dialogue copies are only supported for standard EPUB books."))
        return
    end

    local settings = readSettings(ctx)
    local start_dir = settings.target_dir or doc_file:match("^(.*)/[^/]+$") or getDefaultDir(ctx)
    chooseDirectory(start_dir, function(chosen_dir)
        settings.target_dir = chosen_dir
        saveSettings(ctx, settings)

        local working_msg = InfoMessage:new{
            text = tr("Exporting dialogue EPUB…"),
        }
        UIManager:show(working_msg)
        UIManager:forceRePaint()

        if ctx.ui and ctx.ui.doc_settings then
            pcall(function() ctx.ui.doc_settings:flush() end)
        end

        local res = EpubBatch.processOne(doc_file, {
            mode = "export",
            target_dir = chosen_dir,
            append_tag = settings.append_tag,
            skip_tagged = false,
            sync_sidecar = true,
            lang = settings.lang,
        })
        UIManager:close(working_msg)

        if res.status ~= "done" then
            showInfo(T(tr("Failed to export dialogue book: %1"), tostring(res.reason or "unknown")))
            return
        end

        local quotes = tonumber(res.stats and res.stats.quotes_tagged) or 0
        UIManager:show(ConfirmBox:new{
            text = T(tr("Exported (%1 dialogue runs) to:\n%2\n\nOpen the exported book now?"),
                tostring(quotes), tostring(res.dest_path)),
            ok_text = tr("Open now"),
            cancel_text = tr("Stay here"),
            ok_callback = function()
                local ok_reader, ReaderUI = pcall(require, "apps/reader/readerui")
                if ok_reader and ReaderUI and type(ReaderUI.showReader) == "function" then
                    UIManager:nextTick(function()
                        ReaderUI:showReader(res.dest_path)
                    end)
                else
                    notify(T(tr("Saved to: %1"), tostring(res.dest_path)))
                end
            end,
        })
    end)
end

function BatchCopySettings.overwriteCurrentBook(ctx)
    local tr = ctx.tr
    local T = ctx.T
    local showInfo = ctx.showInfo
    local notify = ctx.notify
    local doc_file = ctx.ui and ctx.ui.document and ctx.ui.document.file
    if type(doc_file) ~= "string" or not doc_file:lower():match("%.epub$") then
        showInfo(tr("Dialogue copies are only supported for standard EPUB books."))
        return
    end
    if EpubDialogueTagger.isTaggedCopy(doc_file) then
        showInfo(tr("Dialogue copy active"))
        return
    end

    local settings = readSettings(ctx)
    local src_dir = doc_file:match("^(.*)/[^/]+$") or "."
    local backup_dir = settings.backup_dir or EpubBatch.defaultBackupDir(src_dir)
    local backup_note = settings.backup_enabled
        and T(tr("Original book will be backed up to:\n%1"), tostring(backup_dir))
        or tr("Backup is disabled; original file will be replaced directly.")

    UIManager:show(ConfirmBox:new{
        text = T(tr("Overwrite this book with a dialogue-tagged EPUB?\n\n%1\n\nReading progress and notes will be preserved."),
            backup_note),
        ok_text = tr("Overwrite"),
        cancel_text = tr("Cancel"),
        ok_callback = function()
            if ctx.ui and ctx.ui.doc_settings then
                pcall(function() ctx.ui.doc_settings:flush() end)
            end
            local working_msg = InfoMessage:new{
                text = tr("Processing book…"),
            }
            UIManager:show(working_msg)
            UIManager:forceRePaint()

            local res = EpubBatch.processOne(doc_file, {
                mode = "overwrite",
                source_dir = src_dir,
                backup_enabled = settings.backup_enabled,
                backup_dir = settings.backup_dir,
                keep_original_name = settings.keep_original_name,
                append_tag = settings.append_tag,
                skip_tagged = false,
                lang = settings.lang,
            })
            UIManager:close(working_msg)

            if res.status ~= "done" then
                showInfo(T(tr("Failed to overwrite book: %1"), tostring(res.reason or "unknown")))
                return
            end

            local quotes = tonumber(res.stats and res.stats.quotes_tagged) or 0
            notify(T(tr("Tagged %1 dialogue runs. Reloading book…"), tostring(quotes)))
            local ok_reader, ReaderUI = pcall(require, "apps/reader/readerui")
            if ok_reader and ReaderUI and type(ReaderUI.showReader) == "function" then
                UIManager:nextTick(function()
                    ReaderUI:showReader(res.dest_path)
                end)
            end
        end,
    })
end

function BatchCopySettings.items(ctx)
    local tr = ctx.tr
    local T = ctx.T

    local items = {
        {
            text_func = function()
                local s = readSettings(ctx)
                local dir = s.source_dir or getDefaultDir(ctx)
                return T(tr("Source folder: %1"), shortenPath(dir, 28))
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local s = readSettings(ctx)
                local init = s.source_dir or getDefaultDir(ctx)
                chooseDirectory(init, function(chosen)
                    s.source_dir = chosen
                    saveSettings(ctx, s)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end)
            end,
        },
        {
            text_func = function()
                local s = readSettings(ctx)
                local label = s.mode == "overwrite"
                    and tr("Overwrite original (with backup)")
                    or tr("Save to target folder")
                return T(tr("Output mode: %1"), label)
            end,
            sub_item_table = {
                {
                    text = tr("Save to target folder"),
                    radio = true,
                    keep_menu_open = true,
                    checked_func = function() return readSettings(ctx).mode == "export" end,
                    callback = function(touchmenu_instance)
                        local s = readSettings(ctx)
                        s.mode = "export"
                        saveSettings(ctx, s)
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                },
                {
                    text = tr("Overwrite original (with backup)"),
                    radio = true,
                    keep_menu_open = true,
                    checked_func = function() return readSettings(ctx).mode == "overwrite" end,
                    callback = function(touchmenu_instance)
                        local s = readSettings(ctx)
                        s.mode = "overwrite"
                        saveSettings(ctx, s)
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                },
            },
        },
        {
            text_func = function()
                local s = readSettings(ctx)
                if s.mode == "export" then
                    local dir = s.target_dir
                    return T(tr("Target folder: %1"),
                        dir and shortenPath(dir, 28) or tr("Not selected"))
                end
                if not s.backup_enabled then
                    return T(tr("Backup folder: %1"), tr("Disabled"))
                end
                local src = s.source_dir or getDefaultDir(ctx)
                local dir = s.backup_dir or EpubBatch.defaultBackupDir(src) or ".typefolio_backup"
                return T(tr("Backup folder: %1"), shortenPath(dir, 28))
            end,
            keep_menu_open = true,
            enabled_func = function()
                local s = readSettings(ctx)
                return s.mode == "export" or s.backup_enabled == true
            end,
            callback = function(touchmenu_instance)
                local s = readSettings(ctx)
                local init = (s.mode == "export" and s.target_dir)
                    or s.backup_dir
                    or s.source_dir
                    or getDefaultDir(ctx)
                chooseDirectory(init, function(chosen)
                    if s.mode == "export" then
                        s.target_dir = chosen
                    else
                        s.backup_dir = chosen
                    end
                    saveSettings(ctx, s)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end)
            end,
            separator = true,
        },
        {
            text = tr("Back up original files before overwriting"),
            keep_menu_open = true,
            enabled_func = function() return readSettings(ctx).mode == "overwrite" end,
            checked_func = function() return readSettings(ctx).backup_enabled == true end,
            callback = function(touchmenu_instance)
                local s = readSettings(ctx)
                s.backup_enabled = not s.backup_enabled
                saveSettings(ctx, s)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        },
        {
            text = tr("Keep original filename when overwriting"),
            help_text = tr("Recommended: keeps original file path so KOReader reading progress, highlights, and collections stay intact."),
            keep_menu_open = true,
            enabled_func = function() return readSettings(ctx).mode == "overwrite" end,
            checked_func = function() return readSettings(ctx).keep_original_name == true end,
            callback = function(touchmenu_instance)
                local s = readSettings(ctx)
                s.keep_original_name = not s.keep_original_name
                saveSettings(ctx, s)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        },
        {
            text = tr("Append '-文笺' suffix to filename"),
            help_text = tr("Formats exported/renamed books as 'Title-Author-文笺.epub' instead of 'Title-Author.epub'."),
            keep_menu_open = true,
            enabled_func = function()
                local s = readSettings(ctx)
                return s.mode == "export" or s.keep_original_name == false
            end,
            checked_func = function() return readSettings(ctx).append_tag == true end,
            callback = function(touchmenu_instance)
                local s = readSettings(ctx)
                s.append_tag = not s.append_tag
                saveSettings(ctx, s)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        },
        {
            text = tr("Keep subfolder structure on export"),
            keep_menu_open = true,
            enabled_func = function()
                local s = readSettings(ctx)
                return s.mode == "export" and s.recursive == true
            end,
            checked_func = function() return readSettings(ctx).preserve_subdirs == true end,
            callback = function(touchmenu_instance)
                local s = readSettings(ctx)
                s.preserve_subdirs = not s.preserve_subdirs
                saveSettings(ctx, s)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        },
        {
            text = tr("Include subfolders"),
            keep_menu_open = true,
            checked_func = function() return readSettings(ctx).recursive == true end,
            callback = function(touchmenu_instance)
                local s = readSettings(ctx)
                s.recursive = not s.recursive
                saveSettings(ctx, s)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        },
        {
            text = tr("Skip already tagged or existing books"),
            keep_menu_open = true,
            checked_func = function() return readSettings(ctx).skip_tagged == true end,
            callback = function(touchmenu_instance)
                local s = readSettings(ctx)
                s.skip_tagged = not s.skip_tagged
                saveSettings(ctx, s)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
            separator = true,
        },
        {
            text_func = function()
                local s = readSettings(ctx)
                return T(tr("Start batch processing (%1)…"), previewNamingExample(s, tr))
            end,
            keep_menu_open = true,
            callback = function()
                BatchCopySettings.runBatchWizard(ctx)
            end,
        },
    }

    return items
end

return BatchCopySettings
