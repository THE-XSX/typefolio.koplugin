local Engine = {}
Engine.__index = Engine

function Engine.new(opts)
    return setmetatable({
        config = assert(opts.config),
        planner = assert(opts.planner),
        get_policy = assert(opts.get_policy),
        painter_available = assert(opts.painter_available),
        build_underline_css = assert(opts.build_underline_css),
        build_tweak_css = assert(opts.build_tweak_css),
        persist = assert(opts.persist),
        apply_css = assert(opts.apply_css),
        apply_painter = assert(opts.apply_painter),
        refresh = assert(opts.refresh),
        last_css = nil,
    }, Engine)
end

function Engine:apply(value, opts)
    opts = opts or {}
    local config = self.config.normalize(value)
    local plan = self.planner.plan(config, self.get_policy(), self.painter_available())
    local parts = {}

    if plan.underline_backend == "css" then
        local underline = self.build_underline_css(config)
        if underline ~= "" then table.insert(parts, underline) end
    end
    local tweaks = self.build_tweak_css(config)
    if tweaks ~= "" then table.insert(parts, tweaks) end
    local css = table.concat(parts, "\n\n")
    local css_changed = css ~= self.last_css

    if opts.persist ~= false then self.persist(config) end
    self.apply_css(css, css ~= "", css_changed)
    self.last_css = css
    self.apply_painter(plan.painter_enabled, config)
    self.refresh()

    return {
        config = config,
        plan = plan,
        css = css,
        css_changed = css_changed,
    }
end

return Engine
