-- SPDX-FileCopyrightText: Copyright (C) 2026 THE-XSX
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- Typefolio (文笺) - KOReader plugin
-- Released under the GNU Affero General Public License v3.0 or later.
-- See the LICENSE file in the project root for the full license text.

-- css_templates.lua
-- 集中管理自定义排版与下划线的 CSS 规则模板

local item_path = debug.getinfo(1, "S").source:sub(2)
local PLUGIN_ROOT = item_path:match("(.*[/\\]typefolio%.koplugin[/\\])")
    or item_path:match("^(.*)css[/\\]") or item_path:match("(.*[/\\])")
    or "plugins/typefolio.koplugin/"
local ModuleLoader = dofile(PLUGIN_ROOT .. "core/module_loader.lua")
local Config = ModuleLoader.load(PLUGIN_ROOT, "core/config.lua")

local CSSTemplates = {}

-- 默认参数
CSSTemplates.defaults = {
    line_thickness = "1.5px",
    line_offset = "2px",
    dash_pattern = "normal",
}

local function buildExcludeSelectors(skip_headings, skip_blockquotes)
    local exclude_selectors = {}
    if skip_headings then
        table.insert(exclude_selectors, "h1 span, h2 span, h3 span, h4 span, h5 span, h6 span")
        table.insert(exclude_selectors, "h1 em, h1 i, h1 u, h1 mark, h2 em, h2 i, h2 u, h2 mark, h3 em, h3 i, h3 u, h3 mark, h4 em, h4 i, h4 u, h4 mark, h5 em, h5 i, h5 u, h5 mark, h6 em, h6 i, h6 u, h6 mark")
        table.insert(exclude_selectors, 'p[align="center"] span, p[align="CENTER"] span, p[align="centre"] span, p[align="middle"] span')
        table.insert(exclude_selectors, ".title span, .chapter-title span, .chaptertitle span, p.center span, div.center span")
        table.insert(exclude_selectors, 'p[style*="center"] span, p[style*="CENTER"] span')
    end
    if skip_blockquotes then
        table.insert(exclude_selectors, "blockquote span, blockquote em, blockquote i, blockquote u, blockquote mark")
    end
    return exclude_selectors
end

-- 构建动态下划线 CSS (纯外科手术级样式，绝对不破坏原书段落首行缩进与行距)
function CSSTemplates.getUnderlineCss(key, thickness, dash_pattern, skip_headings, skip_blockquotes)
    thickness = thickness or "1.5px"
    dash_pattern = dash_pattern or "normal"
    if skip_headings == nil then skip_headings = true end
    if skip_blockquotes == nil then skip_blockquotes = true end

    -- 兼容旧键名（统一来源：Config.UNDERLINE_ALIASES）
    local alias = Config.UNDERLINE_ALIASES[key]
    if alias then
        key = alias.underline
    end

    -- 补全 px 单位
    if type(thickness) == "string" and not thickness:find("px") and tonumber(thickness) then
        thickness = thickness .. "px"
    end

    -- 匹配 crengine 笔触样式 (dashed 短虚线 / dotted 点状虚线 / solid 实下划线)
    local line_style = "dashed"
    local cur_thickness = thickness

    if dash_pattern == "solid" then
        line_style = "solid"
    elseif dash_pattern == "dense" then
        line_style = "dotted"
    elseif dash_pattern == "thick" then
        line_style = "solid"
        if cur_thickness == "1.5px" or cur_thickness == "1.0px" then
            cur_thickness = "2.5px"
        end
    else
        line_style = "dashed"
    end

    if key == "all_lines" then
        local include_selectors = { "p span", "p em", "p i", "p u", "p a", "p font", "p b", "p strong", "div > span" }
        if not skip_blockquotes then
            table.insert(include_selectors, "blockquote span")
        end

        local exclude_selectors = buildExcludeSelectors(skip_headings, skip_blockquotes)
        local inc_str = table.concat(include_selectors, ", ")
        local exc_css = ""
        if #exclude_selectors > 0 then
            local exc_str = table.concat(exclude_selectors, ",\n")
            if line_style == "solid" and cur_thickness == "1.5px" then
                exc_css = string.format([[
                %s {
                    text-decoration: none !important;
                }
                ]], exc_str)
            else
                exc_css = string.format([[
                %s {
                    border-bottom: none !important;
                    text-decoration: none !important;
                }
                ]], exc_str)
            end
        end

        if line_style == "solid" and cur_thickness == "1.5px" then
            return string.format([[
                /* 全局文字逐行实下划线 */
                %s {
                    text-decoration: underline !important;
                }
                %s
            ]], inc_str, exc_css)
        else
            return string.format([[
                /* 全局文字逐行下划线 */
                %s {
                    text-decoration: none !important;
                    border-bottom: %s %s #000000 !important;
                }
                %s
            ]], inc_str, tostring(cur_thickness), line_style, exc_css)
        end
    elseif key == "para" then
        return string.format([[
            /* 段落底部画线 (完全保护原书段落属性) */
            p {
                border-bottom: %s %s #000000 !important;
            }
        ]], tostring(cur_thickness), line_style)
    elseif key == "em_only" then
        return string.format([[
            /* 仅原书斜体/强调词下划线 */
            em, i, u {
                font-style: normal !important;
                text-decoration: none !important;
                border-bottom: %s %s #000000 !important;
            }
        ]], tostring(cur_thickness), line_style)
    elseif key == "marker" then
        local include_selectors = { "p span", "p em", "p i", "u", "mark" }
        if not skip_blockquotes then
            table.insert(include_selectors, "blockquote span")
        end
        local exclude_selectors = buildExcludeSelectors(skip_headings, skip_blockquotes)
        local exc_css = ""
        if #exclude_selectors > 0 then
            exc_css = string.format([[
            %s {
                background-color: transparent !important;
            }
            ]], table.concat(exclude_selectors, ",\n"))
        end
        return string.format([[
            /* 全局文字荧光笔高亮背景 */
            %s {
                text-decoration: none !important;
                background-color: rgba(0, 0, 0, 0.12) !important;
            }
            %s
        ]], table.concat(include_selectors, ", "), exc_css)
    end
    return ""
end

-- 高级排版特效库
-- 每个特效是 function(params) -> css；params 缺省时由各自的 defaults 兜底。
CSSTemplates.tweak_defaults = {
    dialogue_style = { tint = true, tint_level = "light", font_color = "default", bold = false, italic = false, font_family = "" },
    header_border = { border = "both", line_style = "solid", thickness = 1, centered = true,
        include_centered = true },
    chapter_pagebreak = { include_centered = true },
    paragraph_spacing = { gap = 0.45 },
    blockquote_box = { bar = 5, tint = "light", italic = true },
    drop_caps = { scale = 2.1, bold = true },
}

-- 参数取值域，菜单与模板共用一份，避免两处各写各的
CSSTemplates.tweak_options = {
    tint_level = { "light", "medium", "strong" },
    font_color = { "default", "black", "dark", "medium", "light" },
    line_style = { "solid", "dashed", "dotted" },
    border = { "both", "bottom", "top", "left", "none" },
    tint = { "none", "light", "medium" },
}

local TINT_COLORS = { none = nil, light = "#e0e0e0", medium = "#c8c8c8" }

-- Calibre-converted EPUBs often carry no heading tags at all and mark chapter
-- titles as center-aligned paragraphs. Both "chapter page break" and "chapter
-- title decoration" need to recognise them, so the selector list lives here
-- once instead of being spelled out (and drifting) in each template.
local CENTERED_TITLE_SELECTORS = {
    'p[align="center"]', 'p[align="CENTER"]',
    'p[align="centre"]', 'p[align="middle"]',
}

local function centeredTitleSelectors(suffix, prefix)
    local out = {}
    for _, sel in ipairs(CENTERED_TITLE_SELECTORS) do
        table.insert(out, (prefix or "") .. sel .. (suffix or ""))
    end
    return table.concat(out, ", ")
end

-- Every centered-title selector paired with every other, for the
-- adjacent-sibling rules that treat "title + subtitle" as one block.
local function centeredTitlePairs()
    local out = {}
    for _, first in ipairs(CENTERED_TITLE_SELECTORS) do
        for _, second in ipairs(CENTERED_TITLE_SELECTORS) do
            table.insert(out, first .. " + " .. second)
        end
    end
    return table.concat(out, ",\n        ")
end

CSSTemplates.layout_tweaks = {
    dialogue_style = function(params)
        local defaults = CSSTemplates.tweak_defaults.dialogue_style
        local tint = params and params.tint
        if tint == nil then tint = defaults.tint end
        local bold = params and params.bold
        if bold == nil then bold = defaults.bold end
        local italic = params and params.italic
        if italic == nil then italic = defaults.italic end
        local tint_level = (params and params.tint_level) or defaults.tint_level
        local font_color = (params and params.font_color) or defaults.font_color or "default"
        local font_family = Config.sanitizeFontFamily(params and params.font_family or defaults.font_family)

        local tint_colors = {
            light  = "rgba(0, 0, 0, 0.08)",
            medium = "rgba(0, 0, 0, 0.16)",
            strong = "rgba(0, 0, 0, 0.25)",
        }
        local font_colors = {
            black  = "#000000",
            dark   = "#444444",
            medium = "#666666",
            light  = "#888888",
        }

        -- Emit only declarations that are actively requested so e.g. switching dialogue
        -- font alone does not forcibly reset nested <em>/<strong> or add unwanted padding.
        local decls = {}
        if font_family ~= "" then
            -- Omit a generic ", serif" fallback so crengine uses KOReader's configured
            -- CJK fallback font chain cleanly instead of substituting a CJK-incomplete serif.
            table.insert(decls, string.format('font-family: "%s" !important;', font_family))
        end
        if font_color and font_colors[font_color] then
            table.insert(decls, string.format("color: %s !important;", font_colors[font_color]))
        end
        if bold then
            table.insert(decls, "font-weight: bold !important;")
        end
        if italic then
            table.insert(decls, "font-style: italic !important;")
        end
        if tint then
            local bg = tint_colors[tint_level] or tint_colors.light
            table.insert(decls, string.format("background-color: %s !important;", bg))
            table.insert(decls, "padding: 0 2px !important;")
            table.insert(decls, "border-radius: 2px;")
        end
        if #decls == 0 then return "" end

        -- 覆盖文笺离线标注 (.tf-dlg) 与常见对话 class
        return string.format([[
        /* 对话文本样式 (.tf-dlg / .dialogue 等 class 标记) */
        span.tf-dlg, .tf-dlg, span.dialogue, .dialogue, span.dialog, .dialog, span.speech, span.quote-text, span.dlg {
            %s
        }
    ]], table.concat(decls, "\n            "))
    end,

    blockquote_box = function(params)
        local defaults = CSSTemplates.tweak_defaults.blockquote_box
        local bar = (params and params.bar) or defaults.bar
        local tint = (params and params.tint) or defaults.tint
        local italic = params and params.italic
        if italic == nil then italic = defaults.italic end

        local color = TINT_COLORS[tint]
        local decls = {}
        if bar > 0 then
            table.insert(decls, string.format("border-left: %dpx solid #000000 !important;", bar))
        else
            table.insert(decls, "border-left: none !important;")
        end
        if color then
            table.insert(decls, string.format("background-color: %s !important;", color))
            table.insert(decls, string.format("background: %s !important;", color))
        end
        table.insert(decls, string.format("font-style: %s !important;", italic and "italic" or "normal"))

        -- 内部 p 标签的白底会盖住引用块底色，必须一并清掉
        return string.format([[
        /* 引用块装饰 */
        blockquote, .quote, .citation, div.quote, p.quote, section.quote {
            %s
            padding: 8px 14px !important;
            margin: 12px 0 !important;
            display: block !important;
        }
        blockquote p, blockquote span, blockquote div,
        .quote p, .quote span, div.quote p, p.quote span {
            background-color: transparent !important;
            background: transparent !important;
        }
    ]], table.concat(decls, "\n            "))
    end,

    header_border = function(params)
        local defaults = CSSTemplates.tweak_defaults.header_border
        local border = (params and params.border) or defaults.border
        local style = (params and params.line_style) or defaults.line_style
        local thickness = (params and params.thickness) or defaults.thickness
        local centered = params and params.centered
        if centered == nil then centered = defaults.centered end
        local include_centered = params and params.include_centered
        if include_centered == nil then include_centered = defaults.include_centered end

        local rule = string.format("%dpx %s #000000 !important;", thickness, style)
        local decls = {}
        if border == "left" then
            -- KOBO-inspired left vertical bar beside a flush-left chapter title
            table.insert(decls, "border-top: none !important;")
            table.insert(decls, "border-bottom: none !important;")
            table.insert(decls, "border-left: " .. rule)
            table.insert(decls, string.format("text-align: %s !important;",
                centered and "center" or "left"))
            table.insert(decls, "padding: 0.08em 0 0.08em 0.55em !important;")
            table.insert(decls, "margin: 1.5em 0 1.8em 0 !important;")
        else
            table.insert(decls, (border == "both" or border == "top")
                and ("border-top: " .. rule) or "border-top: none !important;")
            table.insert(decls, (border == "both" or border == "bottom")
                and ("border-bottom: " .. rule) or "border-bottom: none !important;")
            table.insert(decls, "border-left: none !important;")
            table.insert(decls, string.format("text-align: %s !important;",
                centered and "center" or "left"))
            -- 边框为"无"时不必占位留白，也不必收窄——否则只改了版面却什么都看不见
            if border == "bottom" and not centered then
                -- WeRead-style flush-left heading with full-width thin bottom rule
                table.insert(decls, "padding: 0 0 0.45em 0 !important;")
                table.insert(decls, "margin: 1.4em 0 1.3em 0 !important;")
                table.insert(decls, "width: 100% !important;")
            elseif border ~= "none" then
                table.insert(decls, "padding: 8px 0 !important;")
                table.insert(decls, "margin: 18px auto !important;")
                table.insert(decls, "width: 85% !important;")
            end
        end

        local css = string.format([[
        /* 章节标题装饰 */
        h1, h2, h3, .title, .chapter-title, .chaptertitle {
            %s
        }
    ]], table.concat(decls, "\n            "))

        if include_centered then
            -- Same fallback the page-break tweak uses: books converted without
            -- heading tags mark titles as centered paragraphs.
            css = css .. string.format([[
        /* Centered-paragraph titles (EPUBs converted without heading tags) */
        %s {
            %s
        }
        /* A centered line that merely follows another is a subtitle inside the
           same title block, so it must not get its own frame. crengine has no
           :has(), so the run cannot be detected from the first line; dropping
           the border on followers is what keeps one title from being boxed
           twice. Adjacent-sibling "+" is supported (used by the engine's own
           MathML sheet). */
        %s {
            border-top: none !important;
            border-bottom: none !important;
            border-left: none !important;
            padding-top: 0 !important;
            padding-left: 0 !important;
            margin-top: 0 !important;
        }
    ]], centeredTitleSelectors(), table.concat(decls, "\n            "),
                centeredTitlePairs())
        end
        return css
    end,

    paragraph_spacing = function(params)
        local defaults = CSSTemplates.tweak_defaults.paragraph_spacing
        local gap = tonumber(params and params.gap)
        if gap == nil then gap = defaults.gap end
        if gap < 0 then gap = 0 elseif gap > 1.5 then gap = 1.5 end
        return string.format([[
        /* 段落间距 (em 相对单位，随字号自动等比缩放) */
        p {
            margin-top: 0 !important;
            margin-bottom: %.2fem !important;
        }
        blockquote p:last-child {
            margin-bottom: 0 !important;
        }
    ]], gap)
    end,

    drop_caps = function(params)
        local defaults = CSSTemplates.tweak_defaults.drop_caps
        local scale = (params and params.scale) or defaults.scale
        local bold = params and params.bold
        if bold == nil then bold = defaults.bold end

        -- 精准定位章节开头首段，排除引用块内段落，避免误伤正文中任意容器首段
        return string.format([[
        /* 章节首字放大下沉 */
        h1 + p, h2 + p, h3 + p, h4 + p,
        h1 + hr + p, h2 + hr + p, h3 + hr + p,
        .title + p, .title + hr + p, .chapter-title + p, .chapter-title + hr + p, .chaptertitle + p, .chaptertitle + hr + p,
        hr + p, section > p:first-of-type, article > p:first-of-type, body > p:first-of-type {
            text-indent: 0 !important;
        }
        h1 + p::first-letter, h2 + p::first-letter, h3 + p::first-letter, h4 + p::first-letter,
        h1 + hr + p::first-letter, h2 + hr + p::first-letter, h3 + hr + p::first-letter,
        .title + p::first-letter, .title + hr + p::first-letter, .chapter-title + p::first-letter, .chapter-title + hr + p::first-letter, .chaptertitle + p::first-letter, .chaptertitle + hr + p::first-letter,
        hr + p::first-letter, section > p:first-of-type::first-letter, article > p:first-of-type::first-letter, body > p:first-of-type::first-letter {
            font-size: %.1fem !important;
            float: left !important;
            line-height: 0.85 !important;
            margin-right: 6px !important;
            margin-top: 2px !important;
            font-weight: %s !important;
        }
        blockquote p::first-letter, .quote p::first-letter {
            font-size: inherit !important;
            float: none !important;
            line-height: inherit !important;
            margin: 0 !important;
            font-weight: inherit !important;
        }
    ]], scale, bold and "bold" or "normal")
    end,

    chapter_pagebreak = function(params)
        local defaults = CSSTemplates.tweak_defaults.chapter_pagebreak
        local include_centered = params and params.include_centered
        if include_centered == nil then include_centered = defaults.include_centered end

        local heading_css = [[
        /* Force a new page before chapter headings inside multi-chapter HTML */
        h1, h2, h3, .title, .chapter-title, .chaptertitle {
            page-break-before: always !important;
            break-before: page !important;
            page-break-after: avoid !important;
            break-after: avoid !important;
            page-break-inside: avoid !important;
            break-inside: avoid !important;
        }
        /* Only skip the very first heading in the document to avoid a blank opening page.
           Do not use bare "div > h2:first-child", or mid-book chapter wrappers lose the break. */
        body > h1:first-child, body > h2:first-child, body > h3:first-child,
        body > .title:first-child, body > .chapter-title:first-child,
        body > .chaptertitle:first-child,
        body > section:first-child > h1:first-child,
        body > section:first-child > h2:first-child,
        body > section:first-child > h3:first-child,
        body > section:first-child > .title:first-child,
        body > section:first-child > .chapter-title:first-child,
        body > div:first-child > h1:first-child,
        body > div:first-child > h2:first-child,
        body > div:first-child > h3:first-child,
        body > div:first-child > .title:first-child,
        body > div:first-child > .chapter-title:first-child {
            page-break-before: auto !important;
            break-before: auto !important;
        }
        ]]
        if include_centered then
            heading_css = heading_css .. [[
        /* Centered-title fallback for EPUBs converted without heading tags
           (calibre "p > font > b" templates): treat center-aligned paragraphs
           as chapter titles. Quoted CSS2.1 form, supported everywhere. */
        ]] .. centeredTitleSelectors() .. [[ {
            page-break-before: always !important;
            break-before: page !important;
            page-break-after: avoid !important;
            break-after: avoid !important;
            page-break-inside: avoid !important;
            break-inside: avoid !important;
        }
        /* Mixed-case variants, kept in a separate block: the case-insensitive
           attribute flag is used by KOReader's own html5.css, but isolating it
           means a parser rejection cannot discard the rule above. */
        p[align=center i], p[align=centre i], p[align=middle i] {
            page-break-before: always !important;
            break-before: page !important;
            page-break-after: avoid !important;
            break-after: avoid !important;
        }
        /* The first title in each DocFragment already gets a break from
           epub.css, so suppress ours there to avoid a blank page. */
        ]] .. centeredTitleSelectors(":first-child", "body > ") .. [[,
        ]] .. centeredTitleSelectors(":first-child", "body > div:first-child > ") .. [[,
        ]] .. centeredTitleSelectors(":first-child", "body > section:first-child > ") .. [[ {
            page-break-before: auto !important;
            break-before: auto !important;
        }
        /* Consecutive centered lines are one title block (title + subtitle),
           not two chapters. */
        ]] .. centeredTitlePairs() .. [[ {
            page-break-before: avoid !important;
            break-before: avoid !important;
        }
        ]]
        end
        return heading_css
    end,
}

-- 内置全局平台风格预设 (Built-in global platform presets)
-- Calibrated from real device screenshots (WeRead, Kindle Native, KOBO Native).
-- Applying a global preset configures typography + margins + matching status bar;
-- readers can still swap the status bar independently anytime under "Status bar".
CSSTemplates.presets = {
    weread = {
        order = 1,
        name = "WeRead Style",
        underline = "none",
        dash_pattern = "normal",
        tweaks = {
            paragraph_spacing = true,
            header_border = true,
            chapter_pagebreak = true,
        },
        tweak_params = {
            paragraph_spacing = { gap = 0.40 },
            header_border = {
                border = "bottom",
                line_style = "solid",
                thickness = 1,
                centered = false,
                include_centered = true,
            },
            chapter_pagebreak = { include_centered = true },
        },
        koreader_settings = {
            copt_font_size = 22,
            copt_line_spacing = 158,
            copt_h_page_margins = { 22, 22 },
            copt_t_page_margin = 30,
            copt_b_page_margin = 30,
            copt_sync_t_b_page_margins = 1,
        },
        custom_header = {
            enabled = true,
            preset = "wechat_reading",
            left = "chapter_title",
            center = "none",
            right = "none",
            divider_style = "none",
            divider_position = "auto",
            hide_on_chapter_start = true,
        },
        custom_footer = {
            enabled = true,
            preset = "wechat_reading",
            left = "clock",
            center = "none",
            right = "page_progress",
            divider_style = "none",
            divider_position = "auto",
            hide_on_chapter_start = false,
        },
    },
    kindle = {
        order = 2,
        name = "Kindle Native Style",
        underline = "none",
        dash_pattern = "normal",
        tweaks = {
            paragraph_spacing = true,
            chapter_pagebreak = true,
        },
        tweak_params = {
            paragraph_spacing = { gap = 0.60 },
            chapter_pagebreak = { include_centered = true },
        },
        koreader_settings = {
            copt_font_size = 21,
            copt_line_spacing = 142,
            copt_h_page_margins = { 12, 12 },
            copt_t_page_margin = 26,
            copt_b_page_margin = 26,
            copt_sync_t_b_page_margins = 1,
        },
        custom_header = {
            enabled = true,
            preset = "wechat_duokan",
            left = "none",
            center = "clock",
            right = "none",
            divider_style = "none",
            divider_position = "auto",
            hide_on_chapter_start = false,
        },
        custom_footer = {
            enabled = true,
            preset = "wechat_duokan",
            left = "time_left_book",
            center = "none",
            right = "reading_percent",
            divider_style = "none",
            divider_position = "auto",
            hide_on_chapter_start = false,
        },
    },
    kobo = {
        order = 3,
        name = "Kobo Native Style",
        underline = "none",
        dash_pattern = "normal",
        tweaks = {
            paragraph_spacing = true,
            header_border = true,
            chapter_pagebreak = true,
        },
        tweak_params = {
            paragraph_spacing = { gap = 0.85 },
            header_border = {
                border = "left",
                line_style = "solid",
                thickness = 3,
                centered = false,
                include_centered = true,
            },
            chapter_pagebreak = { include_centered = true },
        },
        koreader_settings = {
            copt_font_size = 23,
            copt_line_spacing = 148,
            copt_h_page_margins = { 24, 24 },
            copt_t_page_margin = 32,
            copt_b_page_margin = 32,
            copt_sync_t_b_page_margins = 1,
        },
        custom_header = {
            enabled = true,
            preset = "classic_folio",
            left = "none",
            center = "chapter_title",
            right = "none",
            divider_style = "none",
            divider_position = "auto",
            hide_on_chapter_start = false,
        },
        custom_footer = {
            enabled = true,
            preset = "classic_folio",
            left = "none",
            center = "book_title_page_progress_cn",
            right = "none",
            divider_style = "progress_bar",
            divider_position = "below",
            divider_thickness = 1,
            hide_on_chapter_start = false,
        },
    },
}

return CSSTemplates
