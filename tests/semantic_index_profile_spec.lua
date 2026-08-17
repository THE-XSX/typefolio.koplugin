local SemanticIndex = dofile("tools/semantic_index.lua")

local calls = {}
local context = {}

function context:snapshot(request)
    local profile = request.semantic_profile
    calls[profile] = (calls[profile] or 0) + 1
    return {
        page = { viewport = { w = 600, h = 800 } },
        chapter = {},
        toc = {},
        capabilities = { html = profile ~= "dialogue" },
        semantics = {
            {
                box = { x = 20, y = 40, w = 400, h = 24 },
                xpointer = profile ~= "dialogue" and "/body/p[1]/text().0" or nil,
                pos0 = profile ~= "structure" and "/body/p[1]/text().0" or nil,
                html = profile ~= "dialogue" and "<p>Text</p>" or nil,
                screen_text = profile ~= "structure" and "Text" or nil,
            },
        },
    }
end

local index = SemanticIndex.new{ context = context }

local dialogue = index:inspect{ profile = "dialogue" }
assert(dialogue.nodes[1].screen_text == "Text")
assert(dialogue.nodes[1].html_available == false)
assert(index:inspect{ profile = "dialogue" } == dialogue)

local structure = index:inspect()
assert(structure.nodes[1].html_available == true)
assert(structure.nodes[1].screen_text == nil)
assert(index:inspect{ profile = "unknown" } == structure)

local full = index:inspect{ profile = "full" }
assert(full.nodes[1].screen_text == "Text")
assert(full.nodes[1].html_available == true)

assert(calls.dialogue == 1)
assert(calls.structure == 1)
assert(calls.full == 1)

index:invalidate("test")
index:inspect{ profile = "dialogue" }
assert(calls.dialogue == 2)

print("semantic_index_profile_spec: ok")
