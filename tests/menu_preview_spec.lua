-- SPDX-FileCopyrightText: Copyright (C) 2026 THE-XSX
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- Typefolio (文笺) - KOReader plugin
-- Released under the GNU Affero General Public License v3.0 or later.
-- See the LICENSE file in the project root for the full license text.

-- Stepping the settings menu aside to preview a change, and putting it back on a tap.
--
-- What is easy to get wrong here is not the hiding, it is everything around it, so this
-- spec is mostly about the cases where the menu must be left alone:
--
--   * a dialog is on top (the reader is looking at an InputDialog, a confirmation, the help
--     text) -- there is nothing to preview behind it;
--   * ...but a dialog that closes itself right after applying, which is what the thickness
--     dialog and every SpinWidget do, *should* preview, and that is the reason the hide is
--     scheduled a tick later rather than run inline;
--   * a notification is on top -- toasts are not "in front of" anything and must be walked
--     past, or no change that reports itself would ever preview;
--   * the menu was rebuilt while we were away (ReaderMenu does that on rotation) -- the
--     instance we hold is an orphan and showing it would stack two menus;
--   * no trap widget could be made -- hiding the menu with no way back is worse than not
--     previewing.
--
-- Two invariants are load-bearing and both were found by reading KOReader rather than by
-- guessing: `updateItems()` must never run while the window is off the stack (it hands
-- UIManager a *function* refreshtype, and those are queued unconditionally, so a hidden
-- menu would leak a refresh), and `closeMenu()` / `close_callback` must never be called
-- (for the reader menu that is `ReaderMenu:onCloseReaderMenu()`, which drops
-- `ReaderMenu.menu_container` -- lose that reference and the menu can never be closed
-- normally again).
--
-- The module takes UIManager, the trap factory and the tick scheduler as arguments, so all
-- of this runs without KOReader.
--
-- Run from the plugin root:
--   python3 runlua.py <plugin_dir> <plugin_dir>/tests/menu_preview_spec.lua

local function pluginRoot()
    local here = debug.getinfo(1, "S").source:sub(2)
    local root = here:match("^(.*[/\\])tests[/\\][^/\\]*$")
    if root and root:find("typefolio%.koplugin") then return root end
    return "../typefolio.koplugin/"
end
local ROOT = pluginRoot()

local MenuPreview = dofile(ROOT .. "core/menu_preview.lua")

local checks, failures = 0, 0
local function check(label, ok)
    checks = checks + 1
    if ok then
        print("ok " .. label)
    else
        failures = failures + 1
        print("FAIL " .. label)
    end
end

-- ------------------------------------------------------------------ the world, in miniature

-- A window stack with just enough of UIManager's contract: show appends, close removes and
-- notifies the widget, getNthTopWidget counts down from the top, isWidgetShown answers
-- honestly. The real one inserts non-modals below modals; nothing here depends on that.
local function fakeUIManager()
    local uim = { stack = {}, closed = {}, shown = {} }
    function uim:show(widget)
        table.insert(self.stack, widget)
        table.insert(self.shown, widget)
    end
    function uim:close(widget)
        for i = #self.stack, 1, -1 do
            if self.stack[i] == widget then table.remove(self.stack, i) end
        end
        table.insert(self.closed, widget)
        -- The real UIManager sends CloseWidget; TouchMenu answers it with a full-screen
        -- flashing refresh, which is the one refresh this feature pays for.
        if widget.onCloseWidget then widget:onCloseWidget() end
    end
    function uim:getNthTopWidget(n)
        return self.stack[#self.stack - (n - 1)]
    end
    function uim:isWidgetShown(widget)
        for _, w in ipairs(self.stack) do
            if w == widget then return true end
        end
        return false
    end
    function uim:top() return self.stack[#self.stack] end
    function uim:countClosed(widget)
        local n = 0
        for _, w in ipairs(self.closed) do if w == widget then n = n + 1 end end
        return n
    end
    return uim
end

-- A CenterContainer holding a TouchMenu, as ReaderMenu builds it.
local function fakeMenuWindow(uim, name)
    local menu = {
        name = (name or "menu") .. ".touchmenu",
        item_table = { { text = "row" } },
        updates = 0,
        flashes = 0,
        closed_through_callback = false,
    }
    local window = { name = name or "menu", covers_header = true, menu }
    function menu:updateItems()
        self.updates = self.updates + 1
        if not uim:isWidgetShown(window) then self.updated_while_hidden = true end
    end
    function menu:onCloseWidget() self.flashes = self.flashes + 1 end
    function window:onCloseWidget() menu:onCloseWidget() end
    -- If either of these ever runs, the reader menu has lost its container reference.
    menu.close_callback = function() menu.closed_through_callback = true end
    function menu:closeMenu() self.close_callback() end
    return window, menu
end

local function harness(opts)
    opts = opts or {}
    local uim = fakeUIManager()
    local reader = { name = "readerui", covers_fullscreen = true }
    uim:show(reader)

    local ticks = {}
    local traps = {}
    local marks = {}
    local enabled = opts.enabled ~= false

    local preview = MenuPreview.new{
        ui_manager = uim,
        is_enabled = function() return enabled end,
        schedule = function(action) table.insert(ticks, action) end,
        make_trap = function(dismiss_callback)
            if opts.no_trap then return nil end
            local trap = {
                name = "trap",
                invisible = true,
                modal = true,
                dismiss_callback = dismiss_callback,
            }
            table.insert(traps, trap)
            return trap
        end,
        mark = function(name) marks[name] = (marks[name] or 0) + 1 end,
    }

    local h = {
        uim = uim, reader = reader, preview = preview,
        traps = traps, marks = marks,
        setEnabled = function(value) enabled = value end,
    }
    function h.runTicks()
        local queued = ticks
        ticks = {}
        for _, action in ipairs(queued) do action() end
        return #queued
    end
    function h.pendingTicks() return #ticks end
    -- TrapWidget calls dismiss_callback first and closes itself after.
    function h.tap()
        local trap = traps[#traps]
        if not trap then return false end
        trap.dismiss_callback()
        uim:close(trap)
        return true
    end
    return h
end

-- ------------------------------------------------------------------- the ordinary case

do
    local h = harness()
    local window, menu = fakeMenuWindow(h.uim, "menu")
    h.uim:show(window)
    menu:updateItems()                      -- as the changed row's own callback does

    check("a change with the menu in front schedules a preview",
        h.preview:requestAfterChange() == true and h.pendingTicks() == 1)
    check("and nothing has moved yet -- the tick is what does it",
        h.uim:top() == window)

    h.runTicks()
    check("the menu window is off the stack", not h.uim:isWidgetShown(window))
    check("an invisible tap catcher took its place",
        h.uim:top() == h.traps[1] and h.traps[1].invisible == true)
    check("the page is what is left visible",
        h.uim.stack[#h.uim.stack - 1] == h.reader)
    check("closing it asked for the flashing refresh once", menu.flashes == 1)
    check("the menu was not closed through its close_callback",
        menu.closed_through_callback == false)
    check("no repaint was requested while the menu was hidden",
        menu.updated_while_hidden == nil)

    local updates_before = menu.updates
    check("a tap dismisses the catcher", h.tap())
    check("the very same window instance came back",
        h.uim:top() == window and h.uim:isWidgetShown(window))
    check("its rows were repainted exactly once on the way back",
        menu.updates == updates_before + 1)
    check("and the catcher is gone", not h.uim:isWidgetShown(h.traps[1]))
    check("both halves were counted",
        h.marks["menu.preview.hide"] == 1 and h.marks["menu.preview.restore"] == 1)
    check("the window was closed once, not once per change",
        h.uim:countClosed(window) == 1)
end

-- ------------------------------------------------------------------------ dialogs

do
    -- The help text, a confirmation, an info message: still up a tick later, so there is
    -- nothing to preview.
    local h = harness()
    local window = fakeMenuWindow(h.uim, "menu")
    h.uim:show(window)
    local dialog = { name = "infomessage", modal = true }
    h.uim:show(dialog)

    h.preview:requestAfterChange()
    h.runTicks()
    check("a dialog still on screen keeps the menu where it is",
        h.uim:isWidgetShown(window) and #h.traps == 0)
end

do
    -- The thickness dialog and every SpinWidget: apply, then close themselves. This is the
    -- case the scheduled tick exists for -- checking at call time would refuse it.
    local h = harness()
    local window, menu = fakeMenuWindow(h.uim, "menu")
    h.uim:show(window)
    local dialog = { name = "inputdialog", modal = true }
    h.uim:show(dialog)

    check("the request is accepted even with the dialog up",
        h.preview:requestAfterChange() == true)
    h.uim:close(dialog)                     -- UIManager:close(dialog) in the Set callback
    menu:updateItems()
    h.runTicks()
    check("once the dialog closes itself the preview happens",
        not h.uim:isWidgetShown(window) and #h.traps == 1)
    h.tap()
    check("and the tap returns to the same submenu", h.uim:top() == window)
end

do
    -- Notifications are toasts: above everything by contract, and never in the way.
    local h = harness()
    local window = fakeMenuWindow(h.uim, "menu")
    h.uim:show(window)
    h.uim:show({ name = "notification", toast = true })

    h.preview:requestAfterChange()
    h.runTicks()
    check("a notification on top does not count as being in front",
        not h.uim:isWidgetShown(window) and #h.traps == 1)
end

-- ------------------------------------------------------------------------ refusals

do
    local h = harness{ enabled = false }
    local window = fakeMenuWindow(h.uim, "menu")
    h.uim:show(window)

    check("switched off, nothing is even scheduled",
        h.preview:requestAfterChange() == false and h.pendingTicks() == 0)
    check("and the menu is untouched", h.uim:top() == window)
end

do
    local h = harness()
    -- No menu anywhere: a gesture or a preset applied from outside the menu.
    h.preview:requestAfterChange()
    h.runTicks()
    check("a change with no menu open moves nothing",
        h.uim:top() == h.reader and #h.traps == 0)
end

do
    local h = harness{ no_trap = true }
    local window = fakeMenuWindow(h.uim, "menu")
    h.uim:show(window)

    h.preview:requestAfterChange()
    h.runTicks()
    check("with no trap widget available the menu is never hidden",
        h.uim:isWidgetShown(window) and h.uim:countClosed(window) == 0)
end

do
    -- One tap can apply more than once (a preset applies and then republishes). The reader
    -- should see one preview, not a hide racing a restore.
    local h = harness()
    local window = fakeMenuWindow(h.uim, "menu")
    h.uim:show(window)

    check("the first change schedules", h.preview:requestAfterChange() == true)
    check("the second one in the same tap does not",
        h.preview:requestAfterChange() == false)
    check("so only one hide is queued", h.pendingTicks() == 1)
    h.runTicks()
    check("and there is exactly one catcher", #h.traps == 1)
    check("a change while already previewing is ignored too",
        h.preview:requestAfterChange() == false)
end

-- ------------------------------------------------------------------------ the menu moved on

do
    -- Rotation: ReaderMenu closes its container and builds a new one. The instance we are
    -- holding is now an orphan.
    local h = harness()
    local window = fakeMenuWindow(h.uim, "menu")
    h.uim:show(window)
    h.preview:requestAfterChange()
    h.runTicks()

    local rebuilt = fakeMenuWindow(h.uim, "rebuilt")
    h.uim:show(rebuilt)
    h.tap()
    check("a menu rebuilt while previewing is not stacked over",
        h.uim:isWidgetShown(rebuilt) and not h.uim:isWidgetShown(window))
end

do
    -- The reader reopened the menu by hand while the catcher was up.
    local h = harness()
    local window, menu = fakeMenuWindow(h.uim, "menu")
    h.uim:show(window)
    h.preview:requestAfterChange()
    h.runTicks()

    h.uim:show(window)                      -- back on the stack by other means
    local updates = menu.updates
    h.tap()
    check("a window already back on the stack is not shown twice",
        h.uim:countClosed(window) == 1 and menu.updates == updates)
    local same = 0
    for _, w in ipairs(h.uim.stack) do if w == window then same = same + 1 end end
    check("and it appears on the stack exactly once", same == 1)
end

do
    -- A catcher that left the stack without being dismissed (teardown, rotation) must not
    -- block every later preview.
    local h = harness()
    local window = fakeMenuWindow(h.uim, "menu")
    h.uim:show(window)
    h.preview:requestAfterChange()
    h.runTicks()
    h.uim:close(h.traps[1])                 -- gone, dismiss_callback never ran
    h.uim:show(window)

    check("a stale catcher is forgotten rather than blocking",
        h.preview:requestAfterChange() == true)
    h.runTicks()
    check("and the next preview works", #h.traps == 2 and not h.uim:isWidgetShown(window))
end

do
    -- Teardown: an invisible modal catcher outliving the book would eat the first tap in
    -- the file manager.
    local h = harness()
    local window = fakeMenuWindow(h.uim, "menu")
    h.uim:show(window)
    h.preview:requestAfterChange()
    h.runTicks()

    h.preview:cancel()
    check("cancel takes the catcher off the stack",
        not h.uim:isWidgetShown(h.traps[1]))
    check("cancel does not resurrect the menu", not h.uim:isWidgetShown(window))
    h.uim:show(window)
    check("and a later change previews again",
        h.preview:requestAfterChange() == true)
end

do
    -- A pending tick whose menu vanished before it ran: the callback closed the menu itself
    -- (keep_menu_open not set).
    local h = harness()
    local window = fakeMenuWindow(h.uim, "menu")
    h.uim:show(window)
    h.preview:requestAfterChange()
    h.uim:close(window)
    h.runTicks()
    check("a menu that closed itself first is not reopened by the preview",
        not h.uim:isWidgetShown(window) and #h.traps == 0)
end

-- --------------------------------------------------------- a menu that is its own window

do
    -- A TouchMenu shown without a container is its own show_parent. Both spellings have to
    -- be recognized, or the plugin's gesture-opened menu would never preview.
    local h = harness()
    local menu = {
        name = "bare.touchmenu",
        item_table = { { text = "row" } },
        updates = 0,
    }
    function menu:updateItems() self.updates = self.updates + 1 end
    h.uim:show(menu)

    h.preview:requestAfterChange()
    h.runTicks()
    check("a container-less menu is recognized", not h.uim:isWidgetShown(menu))
    h.tap()
    check("and comes back the same way",
        h.uim:top() == menu and menu.updates == 1)
end

do
    -- Anything else on the stack is not a menu, however container-shaped it looks.
    local h = harness()
    h.uim:show({ name = "textviewer", modal = true, { name = "inner" } })
    h.preview:requestAfterChange()
    h.runTicks()
    check("a window whose child has no item_table is not treated as a menu", #h.traps == 0)
end

print(string.format("menu_preview_spec: %s (%d checks, %d failures)",
    failures == 0 and "ok" or "FAILED", checks, failures))
if failures > 0 then error("menu_preview_spec failed", 0) end
