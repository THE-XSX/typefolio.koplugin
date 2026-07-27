-- css_templates.lua
-- 集中管理自定义排版与下划线的 CSS 规则模板 (修复引用块子元素遮挡导致的底色未生效问题)

local CSSTemplates = {}

-- 默认参数
CSSTemplates.defaults = {
    line_thickness = "1.5px",
    line_offset = "2px",
    dash_pattern = "normal",
}

-- 构建动态下划线 CSS (纯外科手术级样式，绝对不破坏原书段落首行缩进与行距)
function CSSTemplates.getUnderlineCss(key, thickness, dash_pattern)
    thickness = thickness or "1.5px"
    dash_pattern = dash_pattern or "normal"

    -- 兼容旧键名
    if key == "all_lines_dashed_compat" or key == "all_lines_dashed" or key == "all_lines_solid" or key == "all_lines_dotted" or key == "thick_lines" then
        key = "all_lines"
    elseif key == "para_dashed" or key == "para_dotted" then
        key = "para"
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
        if line_style == "solid" and cur_thickness == "1.5px" then
            -- 实线直接使用原生下划线，性能最好且 100% 保护所有排版
            return [[
                /* 全局文字逐行实下划线 (自动排除标题) */
                p span, p em, p i, p u, p a, p font, p b, p strong, div > span, blockquote span {
                    text-decoration: underline !important;
                }
                h1 span, h2 span, h3 span, h4 span, h5 span, h6 span,
                p[align="center"] span, p[align="CENTER"] span, .title span, .chapter-title span, .calibre13 span {
                    text-decoration: none !important;
                }
            ]]
        else
            return string.format([[
                /* 全局文字逐行下划线 (完全保护原书段落 display:block，缩进与段距 100%% 正常) */
                p span, p em, p i, p u, p a, p font, p b, p strong, div > span, blockquote span {
                    text-decoration: none !important;
                    border-bottom: %s %s #000000 !important;
                }
                h1 span, h2 span, h3 span, h4 span, h5 span, h6 span,
                p[align="center"] span, p[align="CENTER"] span, .title span, .chapter-title span, .calibre13 span {
                    border-bottom: none !important;
                    text-decoration: none !important;
                }
            ]], tostring(cur_thickness), line_style)
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
        return [[
            /* 全局文字荧光笔高亮背景 */
            p span, p em, p i, u, mark {
                text-decoration: none !important;
                background-color: rgba(0, 0, 0, 0.12) !important;
            }
        ]]
    end
    return ""
end

-- 高级排版特效库 (修复引用块内部 p 标签白底覆盖导致的灰底未生效问题)
CSSTemplates.layout_tweaks = {
    blockquote_box = [[
        /* 引用块左侧加粗竖线与墨水屏浅灰色背景 (强制清空内部 p 标签的白底) */
        blockquote, .quote, .citation, div.quote, p.quote, section.quote {
            border-left: 5px solid #000000 !important;
            background-color: #e0e0e0 !important;
            background: #e0e0e0 !important;
            padding: 8px 14px !important;
            margin: 12px 0 !important;
            font-style: italic !important;
            display: block !important;
        }
        blockquote p, blockquote span, blockquote div,
        .quote p, .quote span, div.quote p, p.quote span {
            background-color: transparent !important;
            background: transparent !important;
        }
    ]],
    header_border = [[
        /* 章节标题居中与上下横线 */
        h1, h2, h3, .title, .chapter-title, .calibre13 {
            text-align: center !important;
            border-top: 1px solid #000000 !important;
            border-bottom: 1px solid #000000 !important;
            padding: 8px 0 !important;
            margin: 18px auto !important;
            width: 85% !important;
        }
    ]],
    custom_hr_dashed = [[
        /* 章尾/正文与脚注间长条短虚线 (----------------------------) */
        hr, .hr, .break, .separator, .asterisk, .ornament, .scene-break, .section-break, .split, div.break, p.break, section.fnote, aside.calibre16, .fnote {
            border: none !important;
            border-top: 2px dashed #000000 !important;
            height: 0px !important;
            margin: 2em auto 1.2em auto !important;
            width: 85% !important;
        }
    ]],
    drop_caps = [[
        /* 章节首字放大下沉 (覆盖所有 EPUB 章节结构：包含标题、横线 hr、容器首段等，彻底清除首行 2em 缩进与重叠) */
        h1 + p, h2 + p, h3 + p, h4 + p,
        h1 + hr + p, h2 + hr + p, h3 + hr + p,
        .title + p, .title + hr + p, .chapter-title + p, .chapter-title + hr + p, .chaptertitle + p, .chaptertitle + hr + p,
        hr + p, div > p:first-of-type, section > p:first-of-type, article > p:first-of-type, body > p:first-of-type,
        p:first-child, p:first-of-type {
            text-indent: 0 !important; /* 强制清空首字段落的 2em 默认缩进，消除右侧大空白 */
        }
        h1 + p::first-letter, h2 + p::first-letter, h3 + p::first-letter, h4 + p::first-letter,
        h1 + hr + p::first-letter, h2 + hr + p::first-letter, h3 + hr + p::first-letter,
        .title + p::first-letter, .title + hr + p::first-letter, .chapter-title + p::first-letter, .chapter-title + hr + p::first-letter, .chaptertitle + p::first-letter, .chaptertitle + hr + p::first-letter,
        hr + p::first-letter, div > p:first-of-type::first-letter, section > p:first-of-type::first-letter, article > p:first-of-type::first-letter, body > p:first-of-type::first-letter,
        p:first-child::first-letter, p:first-of-type::first-letter {
            font-size: 2.1em !important;
            float: left !important;
            line-height: 0.85 !important;
            margin-right: 6px !important;
            margin-top: 2px !important;
            font-weight: bold !important;
        }
    ]],
    pure_black = [[
        /* 强制所有深灰/浅灰文字为纯黑色 (提升墨水屏对比度) */
        body, p, div, span, li, a, .calibre14 {
            color: #000000 !important;
        }
    ]]
}

-- 组合预设 (Presets)
-- Preset names are locale source strings: keep them in English and add
-- translations to locales/*.lua (the menu renders them through translate()).
CSSTemplates.presets = {
    all_dashed_mode = {
        name = "All-line dashes (standard)",
        underline = "all_lines_dashed_compat",
        tweaks = { pure_black = true }
    },
    study = {
        name = "Study notes (emphasis underline + quote boxes)",
        underline = "em_only",
        tweaks = { blockquote_box = true, pure_black = true }
    },
    vintage = {
        name = "Vintage newspaper (headers + drop caps + rules)",
        underline = "em_only",
        tweaks = { drop_caps = true, header_border = true, custom_hr_dashed = true }
    }
}

return CSSTemplates
