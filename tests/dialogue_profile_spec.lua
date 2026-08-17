local DialogueLayout = dofile("painters/dialogue_layout.lua")

local resolver_calls = 0
local rects = DialogueLayout.build({
    page = { viewport = { w = 600, h = 800 } },
    nodes = {
        {
            box = { x = 20, y = 40, w = 400, h = 24 },
            pos0 = "/body/p[1]/text().0",
            screen_text = "“Hello ",
        },
        {
            box = { x = 20, y = 70, w = 400, h = 24 },
            pos0 = "/body/p[1]/text().7",
            screen_text = "world.” he said.",
        },
    },
}, {
    enabled = true,
    mode = "tint",
    lang = "all",
    quote_boxes = function()
        resolver_calls = resolver_calls + 1
        return { { x = 20, y = 40, w = 250, h = 54 } }
    end,
})

assert(resolver_calls == 1)
assert(#rects == 1)

print("dialogue_profile_spec: ok")
