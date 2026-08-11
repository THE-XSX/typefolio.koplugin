-- settings/text_styling.lua
-- Text styling settings: text marks, body bold/italic, dialogue, blockquote,
-- drop caps, pure black text
local item_path = debug.getinfo(1, "S").source:sub(2)
local SETTINGS_ROOT = item_path:match("(.*[/\\])") or ""
local TextMarksSettings = dofile(SETTINGS_ROOT .. "text_marks.lua")

local TextStylingSettings = {}

function TextStylingSettings.items(ctx)
    -- Text marks used to be a top-level menu. It is a styling choice like the
    -- rest of this group, so it lives here as the first row instead.
    local items = {
        {
            text = ctx.tr("Text marks"),
            sub_item_table_func = function() return TextMarksSettings.items(ctx) end,
            separator = true,
        },
    }
    for _, item in ipairs(ctx.tweakItems({
        { key = "body_bold", text = "Body bold" },
        { key = "body_italic", text = "Body italic" },
        { key = "dialogue_style", text = "Dialogue" },
        { key = "blockquote_box", text = "Blockquote" },
        { key = "drop_caps", text = "Drop caps" },
        { key = "pure_black", text = "Pure black text" },
    })) do
        table.insert(items, item)
    end
    return items
end

return TextStylingSettings
