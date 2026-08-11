local HealthCheck = {}

local function safeCall(fn)
    local ok, a, b, c = pcall(fn)
    if ok then return a, b, c end
    return nil
end

local function sampleTOCNodeHTML(ui)
    if not (ui and ui.toc) then return {} end
    local toc_list = ui.toc.toc
    if type(toc_list) ~= "table" or #toc_list == 0 then
        toc_list = safeCall(function() return ui.document:getToc() end)
    end
    if type(toc_list) ~= "table" or #toc_list == 0 then return {} end

    local document = ui.document
    if not (document and type(document.getHTMLFromXPointer) == "function") then return {} end

    local count = #toc_list
    local indices = { 1 }
    if count >= 2 then table.insert(indices, math.floor(count * 0.25) + 1) end
    if count >= 3 then table.insert(indices, math.floor(count * 0.5) + 1) end
    if count >= 4 then table.insert(indices, math.floor(count * 0.75) + 1) end
    if count >= 5 then table.insert(indices, count) end

    local sampled_html = {}
    for _, idx in ipairs(indices) do
        local entry = toc_list[idx]
        local xp = entry and (entry.xpointer or entry.pos0)
        if type(xp) == "string" and xp ~= "" then
            local html = safeCall(function()
                return document:getHTMLFromXPointer(xp, 0x1001, true)
            end)
            if type(html) == "string" and html ~= "" then
                table.insert(sampled_html, html)
            end
        end
    end
    return sampled_html
end

function HealthCheck.run(snapshot, config, ui)
    snapshot = snapshot or {}
    config = config or {}
    local findings = {}
    local features = {}

    local html_snippets = {}
    for _, node in ipairs(snapshot.nodes or {}) do
        if type(node.html) == "string" and node.html ~= "" then
            table.insert(html_snippets, node.html)
        end
    end

    local toc_samples = sampleTOCNodeHTML(ui)
    for _, html in ipairs(toc_samples) do
        table.insert(html_snippets, html)
    end

    local combined_html = table.concat(html_snippets, "\n"):lower()
    local has_html = #html_snippets > 0

    -- 1. Chapter Headings & Pagebreaks
    local has_standard_heading = combined_html:find("<h%d") ~= nil
    local has_centered_heading = combined_html:find("align=\"center\"") ~= nil
        or combined_html:find("align=center") ~= nil
        or combined_html:find("text%-align%s*:%s*center") ~= nil
        or combined_html:find("class=\"[^\"]*title[^\"]*\"") ~= nil
        or combined_html:find("class=\"[^\"]*center[^\"]*\"") ~= nil

    if has_standard_heading then
        table.insert(features, {
            name = "Chapter titles & page breaks",
            status = "ok",
            badge = "【✔】 Fully Supported",
            desc = "Detected standard <h1-h6> heading tags across chapters.",
            action1 = "Plugin setting: Standard titles are active out-of-the-box.",
            action2 = "Calibre edit: No EPUB modification required.",
        })
    elseif has_centered_heading then
        table.insert(features, {
            name = "Chapter titles & page breaks",
            status = "warn",
            badge = "【!】 Tweak Option Recommended",
            desc = "No <h1-h6> tags found, but centered paragraph titles were detected.",
            action1 = "Plugin setting: Enable 'Also break on centered paragraphs' in menu.",
            action2 = "Calibre edit: Search: <p[^>]*>\\s*(第[0-9一二...]+[章卷回][^<]*)</p>  →  Replace: <h2 class=\"chapter-title\">\\1</h2>",
        })
    else
        table.insert(features, {
            name = "Chapter titles & page breaks",
            status = "info",
            badge = "【i】 Non-standard Markup",
            desc = "No clear heading tags or centered title markers detected in TOC samples.",
            action1 = "Plugin setting: Add custom class selector under Semantic Settings.",
            action2 = "Calibre edit: Search: <p[^>]*>\\s*(第[0-9一二...]+[章卷回][^<]*)</p>  →  Replace: <h2 class=\"chapter-title\">\\1</h2>",
        })
    end

    -- 2. Dialogue Highlighting
    local has_dialogue_class = combined_html:find("class=\"[^\"]*dialogue[^\"]*\"") ~= nil
        or combined_html:find("class=\"[^\"]*dialog[^\"]*\"") ~= nil
        or combined_html:find("class=\"[^\"]*speech[^\"]*\"") ~= nil
        or combined_html:find("class=\"[^\"]*dlg[^\"]*\"") ~= nil
    local has_quotes = combined_html:find("“") ~= nil or combined_html:find("「") ~= nil or combined_html:find("\"") ~= nil

    if has_dialogue_class then
        table.insert(features, {
            name = "Dialogue highlighting",
            status = "ok",
            badge = "【✔】 Class Markup Found",
            desc = "Detected .dialogue / .dialog classes in HTML.",
            action1 = "Plugin setting: Enable Dialogue Highlighting (Class mode).",
            action2 = "Calibre edit: Class markup already present in EPUB.",
        })
    elseif has_quotes then
        table.insert(features, {
            name = "Dialogue highlighting",
            status = "ok",
            badge = "【✔】 Dynamic Detection Ready",
            desc = "No dialogue class found, but quote marks were detected.",
            action1 = "Plugin setting: Enable 'Dynamic quotes detection' (no EPUB modification required).",
            action2 = "Calibre edit: Search: “([^””]*)”  →  Replace: <span class=\"dialogue\">“\\1”</span>",
        })
    else
        table.insert(features, {
            name = "Dialogue highlighting",
            status = "info",
            badge = "【i】 No Quotes Sampled",
            desc = "No dialogue quotes or classes were found in sample pages.",
            action1 = "Plugin setting: Keep Dynamic quotes detection enabled.",
            action2 = "Calibre edit: Search: “([^””]*)”  →  Replace: <span class=\"dialogue\">“\\1”</span>",
        })
    end

    -- 3. Blockquote Boxes
    local has_blockquote = combined_html:find("<blockquote") ~= nil
        or combined_html:find("class=\"[^\"]*quote[^\"]*\"") ~= nil
        or combined_html:find("class=\"[^\"]*citation[^\"]*\"") ~= nil

    if has_blockquote then
        table.insert(features, {
            name = "Blockquote box decoration",
            status = "ok",
            badge = "【✔】 Fully Supported",
            desc = "Detected <blockquote> / .quote elements.",
            action1 = "Plugin setting: Enable Blockquote Box styling in menu.",
            action2 = "Calibre edit: No EPUB modification required.",
        })
    else
        table.insert(features, {
            name = "Blockquote box decoration",
            status = "info",
            badge = "【i】 No Blockquote Found",
            desc = "No standard <blockquote> elements detected in sampled chapters.",
            action1 = "Plugin setting: Add custom quote class under Semantic Settings if present.",
            action2 = "Calibre edit: Search: <p[^>]*>【引用】([^\\n<]*)</p>  →  Replace: <blockquote><p>\\1</p></blockquote>",
        })
    end

    -- 4. Drop Caps
    local has_title_class = combined_html:find("class=\"[^\"]*title[^\"]*\"") ~= nil
    local has_valid_heading_for_dropcaps = has_standard_heading or has_title_class
    local has_fullwidth_space = combined_html:find("　") ~= nil

    if not has_valid_heading_for_dropcaps then
        table.insert(features, {
            name = "Drop caps (Newspaper style)",
            status = "warn",
            badge = "【!】 Heading Tags Required",
            desc = "No <h1-h6> tags or .title class found. CSS first-letter selectors cannot locate chapter first paragraphs.",
            action1 = "Plugin setting: Disable Drop Caps if not editing EPUB.",
            action2 = "Calibre edit: Search: <p[^>]*>\\s*(第[0-9一二...]+[章卷回][^<]*)</p>  →  Replace: <h2 class=\"chapter-title\">\\1</h2>",
        })
    elseif has_fullwidth_space then
        table.insert(features, {
            name = "Drop caps (Newspaper style)",
            status = "warn",
            badge = "【!】 Space Cleanup Needed",
            desc = "Fullwidth indent spaces ('　') detected at paragraph starts.",
            action1 = "Plugin setting: Drop Caps will target spaces unless cleaned.",
            action2 = "Calibre edit: Search: (<h[1-4][^>]*>[^<]*</h[1-4]>\\s*<p[^>]*>)　+  →  Replace: \\1",
        })
    else
        table.insert(features, {
            name = "Drop caps (Newspaper style)",
            status = "ok",
            badge = "【✔】 Fully Supported",
            desc = "Heading structure and first-line paragraphs are clean.",
            action1 = "Plugin setting: Enable Drop Caps in menu.",
            action2 = "Calibre edit: No EPUB modification required.",
        })
    end

    -- 5. Underlines & Skip Centered
    if config.skip_headings ~= false then
        table.insert(features, {
            name = "Underline & Skip Centered",
            status = "ok",
            badge = "【✔】 Skip Headings Active",
            desc = "'Skip headings and centered text' is enabled.",
            action1 = "Plugin setting: Skip Headings is already active.",
            action2 = "Calibre edit: No EPUB modification required.",
        })
    else
        table.insert(features, {
            name = "Underline & Skip Centered",
            status = "warn",
            badge = "【!】 Recommendation",
            desc = "'Skip headings and centered text' is currently disabled.",
            action1 = "Plugin setting: Enable 'Skip headings and centered text' in Text Marks menu.",
            action2 = "Calibre edit: Search: <p[^>]*>\\s*(第[0-9一二...]+[章卷回][^<]*)</p>  →  Replace: <h2 class=\"chapter-title\">\\1</h2>",
        })
    end

    local warning_count, info_count = 0, 0
    for _, feat in ipairs(features) do
        if feat.status == "warn" then warning_count = warning_count + 1
        elseif feat.status == "info" then info_count = info_count + 1 end
    end

    return {
        score = math.max(0, 100 - warning_count * 10 - info_count * 5),
        features = features,
        warning_count = warning_count,
        info_count = info_count,
        html_available = has_html,
        findings = findings,
    }
end

return HealthCheck
