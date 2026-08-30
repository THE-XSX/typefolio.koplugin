-- SPDX-FileCopyrightText: Copyright (C) 2026 THE-XSX
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- Typefolio (文笺) - KOReader plugin
-- Released under the GNU Affero General Public License v3.0 or later.
-- See the LICENSE file in the project root for the full license text.

-- core/menu_preview.lua
-- Step the settings menu aside after a change, and put it back on the next tap.
--
-- The menu covers most of the screen, so every setting is judged from the sliver of text
-- around it. The reader's workaround is to close the menu, look, reopen it and walk back
-- down two or three submenu levels. This module does that walk for them: after a change is
-- applied the live menu window is taken off the window stack, an invisible full-screen tap
-- catcher goes up in its place, and the *same* window instance is shown again when the
-- catcher is dismissed.
--
-- Why the same instance, rather than reopening the menu at a recorded path: TouchMenu keeps
-- its position in `item_table_stack` / `cur_tab` / `page` and nothing else -- there is no
-- item index to record -- and this plugin builds every submenu through
-- `sub_item_table_func`, which returns a fresh table on each call. Reopening would land at
-- the top level. UIManager's `show`/`close` are pure window-stack operations that leave the
-- widget itself untouched (`TouchMenu:onCloseWidget` only asks for a flashing refresh), so
-- hiding and re-showing costs nothing but the refresh and returns to the exact same screen.
--
-- Deliberately free of `require`, like the rest of core/: UIManager, the trap widget factory
-- and the tick scheduler are injected, which is also what makes tests/menu_preview_spec.lua
-- possible without KOReader.
--
-- Two things this must never do:
--   * paint or refresh the menu while it is off the stack. `TouchMenu:updateItems()` hands
--     UIManager a *function* refreshtype, and those are queued unconditionally, so calling
--     it on a hidden menu leaks a refresh of a region nothing is drawing. `updateItems` is
--     therefore only ever called after the window is back on the stack.
--   * go through `TouchMenu:closeMenu()`. That runs `close_callback`, which for the reader
--     menu is `ReaderMenu:onCloseReaderMenu()` -- it drops `ReaderMenu.menu_container`, and
--     with the reference gone the reader menu can never be closed normally again.

local MenuPreview = {}
MenuPreview.__index = MenuPreview

-- Toasts (notifications) sit above everything by contract and never stop event
-- propagation, and an invisible widget is our own trap or a Trapper's. Neither one means
-- "something is in front of the menu", so both are walked past. The bound is a safety net,
-- not a real limit: the stack is a handful of windows deep.
local MAX_STACK_WALK = 12

local function isMenuWidget(widget)
    return type(widget) == "table"
        and type(widget.updateItems) == "function"
        and type(widget.item_table) == "table"
end

-- The window on the stack is usually a CenterContainer wrapping the TouchMenu, but a menu
-- shown without one is its own `show_parent`. Both spellings are accepted so this works for
-- the reader menu (ReaderMenu.menu_container) and for the plugin's own gesture-opened menu
-- alike, without either of them having to register itself here.
local function menuOf(window)
    if type(window) ~= "table" then return nil end
    if isMenuWidget(window) then return window end
    if isMenuWidget(window[1]) then return window[1] end
    return nil
end

local function topSolidWindow(uim)
    if type(uim.getNthTopWidget) ~= "function" then return nil end
    for n = 1, MAX_STACK_WALK do
        local widget = uim:getNthTopWidget(n)
        if widget == nil then return nil end
        if not widget.toast and not widget.invisible then return widget end
    end
    return nil
end

local function isShown(uim, widget)
    if type(uim.isWidgetShown) ~= "function" then return nil end
    return uim:isWidgetShown(widget) and true or false
end

function MenuPreview.new(opts)
    return setmetatable({
        ui_manager = assert(opts.ui_manager),
        make_trap = assert(opts.make_trap),
        schedule = assert(opts.schedule),
        is_enabled = assert(opts.is_enabled),
        mark = opts.mark,
    }, MenuPreview)
end

function MenuPreview:_mark(name)
    if self.mark then self.mark(name) end
end

-- A trap that left the stack without going through its own dismissal (the reader tearing
-- down, a rotation closing every window) would otherwise block previews for the rest of the
-- session.
function MenuPreview:_forgetStaleTrap()
    if not self.trap then return end
    if isShown(self.ui_manager, self.trap) == false then
        self.trap, self.window, self.menu = nil, nil, nil
    end
end

--- Ask for a preview after a change has been applied. Returns true if one was scheduled.
--
-- Scheduled rather than immediate, and that is the whole trick for the dialog cases: a
-- callback that changes a setting from inside an InputDialog or a SpinWidget applies the
-- change *before* closing its dialog, so at call time the menu is not the top window. One
-- tick later it is, and the reader gets a preview from a dialog too. When the dialog stays
-- up on purpose (a confirmation, an info message, the help text) it is still there a tick
-- later and the preview is skipped, which is what we want -- there is nothing to look at
-- behind a dialog.
function MenuPreview:requestAfterChange()
    if not self.is_enabled() then return false end
    self:_forgetStaleTrap()
    -- Already previewing, or already about to: several applyStyle calls can belong to one
    -- tap (a preset applies once but publishes twice), and the second one must not queue a
    -- second hide.
    if self.pending or self.trap then return false end
    self.pending = true
    self.schedule(function()
        self.pending = nil
        self:_hide()
    end)
    return true
end

function MenuPreview:_hide()
    local uim = self.ui_manager
    local window = topSolidWindow(uim)
    local menu = menuOf(window)
    -- No menu in front: the change came from a gesture, a dialog is still up, or the
    -- callback closed the menu itself. Nothing to step aside.
    if not menu then return false end

    local trap = self.make_trap(function() self:_restore() end)
    -- No trap widget on this build: leaving the menu closed with no way back would be worse
    -- than not previewing at all.
    if not trap then return false end

    self.window, self.menu, self.trap = window, menu, trap
    -- Order matters: closing first lets the trap go up over the bare page, and the page
    -- underneath has already been repainted with the new style (every applyStyle asks for
    -- it), so the flashing refresh that `TouchMenu:onCloseWidget` requests is all it takes
    -- to reveal the change.
    uim:close(window)
    uim:show(trap)
    self:_mark("menu.preview.hide")
    return true
end

function MenuPreview:_restore()
    local uim = self.ui_manager
    local window, menu = self.window, self.menu
    self.trap, self.window, self.menu = nil, nil, nil
    if not window then return false end
    -- Put back already (a second dismissal, or the menu was reopened by hand).
    if isShown(uim, window) then return false end
    -- Something rebuilt the menu while we were away -- ReaderMenu does exactly that on
    -- rotation -- and the instance we are holding is now an orphan. Showing it would stack
    -- two menus.
    local top = topSolidWindow(uim)
    if top and top ~= window and menuOf(top) then return false end

    uim:show(window)
    -- Now, and only now: this is what repaints the rows and asks for the refresh, and it
    -- also picks up the checkmark that changed while the menu was away.
    menu:updateItems()
    self:_mark("menu.preview.restore")
    return true
end

--- Give up any pending or live preview without restoring anything (teardown).
function MenuPreview:cancel()
    local trap = self.trap
    self.pending, self.trap, self.window, self.menu = nil, nil, nil, nil
    if trap and isShown(self.ui_manager, trap) ~= false then
        self.ui_manager:close(trap)
    end
end

return MenuPreview
