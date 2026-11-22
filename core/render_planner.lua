-- SPDX-FileCopyrightText: Copyright (C) 2026 THE-XSX
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- Typefolio (文笺) - KOReader plugin
-- Released under the GNU Affero General Public License v3.0 or later.
-- See the LICENSE file in the project root for the full license text.

local RenderPlanner = {}

local PAINTABLE = {
    all_lines = true,
    marker = true,
}

local CSS_ONLY = {
    para = true,
    em_only = true,
}

function RenderPlanner.normalizePolicy(policy)
    if policy == "css" or policy == "paint" then return policy end
    return "auto"
end

function RenderPlanner.plan(config, policy, painter_available, capabilities)
    policy = RenderPlanner.normalizePolicy(policy)
    local underline = config.underline or "none"
    local backend = "none"
    local fallback

    if underline ~= "none" then
        if policy == "css" or not painter_available then
            backend = "css"
            if not painter_available and PAINTABLE[underline] and policy ~= "css" then
                fallback = "painter_unavailable"
            end
        elseif PAINTABLE[underline] then
            backend = "paint"
        elseif CSS_ONLY[underline] then
            backend = "css"
            if policy == "paint" then fallback = "css_only" end
        else
            backend = "css"
            fallback = "unknown_underline"
        end
    end

    local has_tweaks = false
    for _, enabled in pairs(config.tweaks or {}) do
        if enabled then
            has_tweaks = true
            break
        end
    end

    -- Dual-path dialogue coordination: when the book already carries dialogue class
    -- markup (.tf-dlg, .dialogue, etc.) and CSS dialogue styling is enabled, automatically
    -- suppress the runtime dynamic dialogue painter to prevent double-darkening and avoid
    -- per-page-turn FFI text extraction overhead.
    local css_dialogue = config.tweaks and config.tweaks.dialogue_style == true
    local dp = config.dialogue_painter
    local dialogue_painter_requested = type(dp) == "table" and dp.enabled == true
    local has_dialogue_class = type(capabilities) == "table" and capabilities.has_dialogue_class == true
    local dialogue_suppressed_by_css = dialogue_painter_requested and css_dialogue and has_dialogue_class
    local dialogue_painter_enabled = dialogue_painter_requested and not dialogue_suppressed_by_css
    local dialogue_backend = "none"
    if css_dialogue and has_dialogue_class then
        dialogue_backend = "css"
    elseif dialogue_painter_enabled then
        dialogue_backend = "paint"
    elseif css_dialogue then
        dialogue_backend = "css"
    end

    return {
        policy = policy,
        underline = underline,
        underline_backend = backend,
        painter_enabled = backend == "paint",
        css_enabled = backend == "css" or has_tweaks,
        fallback = fallback,
        dialogue_backend = dialogue_backend,
        dialogue_painter_enabled = dialogue_painter_enabled,
        dialogue_suppressed_by_css = dialogue_suppressed_by_css,
    }
end

return RenderPlanner
