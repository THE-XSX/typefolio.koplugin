-- SPDX-FileCopyrightText: Copyright (C) 2026 THE-XSX
-- SPDX-License-Identifier: AGPL-3.0-or-later
--
-- Typefolio (文笺) - KOReader plugin
-- Released under the GNU Affero General Public License v3.0 or later.
-- See the LICENSE file in the project root for the full license text.

-- tests/epub_dialogue_tagger_spec.lua
-- Unit test for offline EPUB dialogue tagger and include_quotes option.

local EpubDialogueTagger = dofile("tools/epub_dialogue_tagger.lua")

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

-- Test 1: include_quotes = true (default)
local html1 = "<p>张三说：“你好世界！”</p>"
local tagged1, count1 = EpubDialogueTagger.tagXhtml(html1, { lang = "cn", include_quotes = true })
check("tags dialogue with quotes included", count1 == 1 and tagged1 == '<p>张三说：<span class="tf-dlg">“你好世界！”</span></p>')

-- Test 2: include_quotes = false
local tagged2, count2 = EpubDialogueTagger.tagXhtml(html1, { lang = "cn", include_quotes = false })
check("tags dialogue with quotes excluded", count2 == 1 and tagged2 == '<p>张三说：“<span class="tf-dlg">你好世界！</span>”</p>')

-- Test 3: multiple quotes in block with include_quotes = false
local html3 = "<p>“第一句，”他说，“第二句。”</p>"
local tagged3, count3 = EpubDialogueTagger.tagXhtml(html3, { lang = "cn", include_quotes = false })
check("tags multiple quotes without quotes", count3 == 2 and tagged3 == '<p>“<span class="tf-dlg">第一句，</span>”他说，“<span class="tf-dlg">第二句。</span>”</p>')

-- Test 4: nested inline tags with include_quotes = false
local html4 = "<p>“他说<em>悄悄</em>话。”</p>"
local tagged4, count4 = EpubDialogueTagger.tagXhtml(html4, { lang = "cn", include_quotes = false })
check("splits across inline tags cleanly without quotes", count4 == 1 and tagged4 == '<p>“<span class="tf-dlg">他说</span><em><span class="tf-dlg">悄悄</span></em><span class="tf-dlg">话。</span>”</p>')

-- Test 5: Cache path hash distinguishes include_quotes
local path_with = EpubDialogueTagger.buildCachePath("book.epub", "cache", { lang = "cn", include_quotes = true })
local path_without = EpubDialogueTagger.buildCachePath("book.epub", "cache", { lang = "cn", include_quotes = false })
check("cache path differs when include_quotes changes", path_with ~= path_without)

-- Test 6: getCachedCopyPath and hasCachedCopy non-existent
local fake_path = EpubDialogueTagger.getCachedCopyPath("non_existent_book.epub", "cache_non_existent")
check("getCachedCopyPath returns nil when file does not exist", fake_path == nil)
check("hasCachedCopy returns false when file does not exist", EpubDialogueTagger.hasCachedCopy("non_existent_book.epub", "cache_non_existent") == false)

print(string.format("epub_dialogue_tagger_spec: %d checks, %d failures", checks, failures))
if failures > 0 then error("epub_dialogue_tagger_spec failed", 0) end
