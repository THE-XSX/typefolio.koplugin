local SemanticLayout = {}

local function add(rects, x, y, w, h, screen, kind)
    local x0, y0 = math.max(0, math.floor(x)), math.max(0, math.floor(y))
    local x1 = math.min(screen.w, math.floor(x + w))
    local y1 = math.min(screen.h, math.floor(y + h))
    if x1 > x0 and y1 > y0 then
        table.insert(rects, { x = x0, y = y0, w = x1 - x0, h = y1 - y0, kind = kind })
    end
end

function SemanticLayout.build(snapshot, options, report)
    options = options or {}
    if options.enabled ~= true then return {} end
    local screen = snapshot and snapshot.page and snapshot.page.viewport
    if not screen then return {} end

    local thickness = math.max(1, tonumber(options.thickness) or 1)
    local rects = {}
    local problem_nodes = {}
    if options.diagnostics and report then
        for _, finding in ipairs(report.findings or {}) do
            for _, node in ipairs(finding.nodes or {}) do problem_nodes[node] = true end
        end
    end

    for _, node in ipairs(snapshot.nodes or {}) do
        local box = node.box
        if box and node.kind == "heading" and options.headings then
            add(rects, box.x - thickness * 4, box.y, thickness, box.h, screen, "heading")
            add(rects, box.x - thickness * 2, box.y, thickness, box.h, screen, "heading")
        elseif box and node.kind == "blockquote" and options.blockquotes then
            add(rects, box.x - thickness * 4, box.y, thickness, box.h, screen, "blockquote")
            add(rects, box.x - thickness * 2, box.y, thickness / 2, box.h, screen, "blockquote")
        elseif box and node.kind == "scene_break" and options.scene_breaks then
            local size = thickness * 2
            local center = screen.w / 2
            local cy = box.y + box.h / 2
            for offset = -3, 3 do
                local dot_s = (offset == 0) and (size * 1.5) or size
                add(rects, center + offset * size * 2.5 - dot_s / 2, cy - dot_s / 2, dot_s, dot_s,
                    screen, "scene_break")
            end
        end
        if box and problem_nodes[node] then
            add(rects, box.x, box.y, math.min(box.w, thickness * 8), thickness, screen, "diagnostic")
            add(rects, box.x, box.y, thickness, math.min(box.h, thickness * 8), screen, "diagnostic")
        end
    end
    return rects
end

return SemanticLayout
