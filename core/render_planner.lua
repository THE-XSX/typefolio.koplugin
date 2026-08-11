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

function RenderPlanner.plan(config, policy, painter_available)
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

    return {
        policy = policy,
        underline = underline,
        underline_backend = backend,
        painter_enabled = backend == "paint",
        css_enabled = backend == "css" or has_tweaks,
        fallback = fallback,
    }
end

return RenderPlanner
