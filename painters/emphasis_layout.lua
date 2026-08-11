local EmphasisLayout = {}

local function addRect(rects, x, y, w, h, screen)
    local x0, y0 = math.max(0, math.floor(x)), math.max(0, math.floor(y))
    local x1 = math.min(screen.w, math.floor(x + w))
    local y1 = math.min(screen.h, math.floor(y + h))
    if x1 > x0 and y1 > y0 then
        table.insert(rects, { x = x0, y = y0, w = x1 - x0, h = y1 - y0 })
    end
end

function EmphasisLayout.build(snapshot, options)
    options = options or {}
    if options.enabled ~= true then return {} end
    local screen = snapshot and snapshot.page and snapshot.page.viewport
    if not screen then return {} end

    local rects = {}
    local dot_size = math.max(1, tonumber(options.size) or 2)
    local gap = math.max(4, tonumber(options.gap) or 12)

    -- semantic_index exposes normalized samples as `nodes`; `semantics` is the
    -- raw BookContext field and is absent here.
    for _, sample in ipairs(snapshot.nodes or {}) do
        local html = type(sample.html) == "string" and sample.html:lower() or nil
        -- Match the tag name only: a bare "<i" also hits <img>, and "<u" hits <ul>.
        local is_emphasis = sample.kind == "emphasis"
            or (html and (html:find("<em[%s>]") or html:find("<i[%s>]")
                or html:find("<u[%s>]") or html:find("<strong[%s>]")
                or html:find("<b[%s>]")) ~= nil)
        if is_emphasis and sample.box then
            local box = sample.box
            local y_dot = box.y + box.h + 1
            local step = gap
            for x_dot = box.x + step / 2, box.x + box.w - step / 4, step do
                addRect(rects, x_dot - dot_size / 2, y_dot, dot_size, dot_size, screen)
            end
        end
    end
    return rects
end

return EmphasisLayout
