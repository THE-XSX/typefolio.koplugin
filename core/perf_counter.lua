local PerfCounter = {}
PerfCounter.__index = PerfCounter

local unpack_values = unpack or table.unpack

local function pack(...)
    return { n = select("#", ...), ... }
end

local function defaultClock()
    return os.clock() * 1000
end

local function copyMetric(metric)
    return {
        calls = metric.calls,
        total_ms = metric.total_ms,
        max_ms = metric.max_ms,
        errors = metric.errors,
    }
end

function PerfCounter.new(opts)
    opts = opts or {}
    local self = setmetatable({
        clock = opts.clock or defaultClock,
        enabled = opts.enabled == true,
        metrics = {},
        active_ms = 0,
    }, PerfCounter)
    local now = self.clock()
    self.reset_at = now
    self.enabled_at = self.enabled and now or nil
    return self
end

function PerfCounter:isEnabled()
    return self.enabled
end

function PerfCounter:setEnabled(enabled)
    enabled = enabled == true
    if enabled == self.enabled then return end
    local now = self.clock()
    if self.enabled and self.enabled_at then
        self.active_ms = self.active_ms + math.max(0, now - self.enabled_at)
    end
    self.enabled = enabled
    self.enabled_at = enabled and now or nil
end

function PerfCounter:reset()
    local now = self.clock()
    self.metrics = {}
    self.active_ms = 0
    self.reset_at = now
    self.enabled_at = self.enabled and now or nil
end

function PerfCounter:start()
    if not self.enabled then return nil end
    return self.clock()
end

function PerfCounter:_record(name, elapsed_ms, ok, calls)
    if not self.enabled or type(name) ~= "string" then return end
    local metric = self.metrics[name]
    if not metric then
        metric = { calls = 0, total_ms = 0, max_ms = 0, errors = 0 }
        self.metrics[name] = metric
    end
    metric.calls = metric.calls + (calls or 1)
    if elapsed_ms then
        elapsed_ms = math.max(0, elapsed_ms)
        metric.total_ms = metric.total_ms + elapsed_ms
        metric.max_ms = math.max(metric.max_ms, elapsed_ms)
    end
    if ok == false then metric.errors = metric.errors + 1 end
end

function PerfCounter:finish(name, started_at, ok)
    if started_at == nil or not self.enabled then return end
    self:_record(name, self.clock() - started_at, ok ~= false)
end

function PerfCounter:mark(name, count)
    if not self.enabled then return end
    self:_record(name, nil, true, count or 1)
end

function PerfCounter:safeCall(name, fn)
    if not self.enabled then return pcall(fn) end
    local started_at = self.clock()
    local values = pack(pcall(fn))
    self:_record(name, self.clock() - started_at, values[1])
    return unpack_values(values, 1, values.n)
end

function PerfCounter:measure(name, fn)
    if not self.enabled then return fn() end
    local started_at = self.clock()
    local values = pack(pcall(fn))
    self:_record(name, self.clock() - started_at, values[1])
    if not values[1] then error(values[2], 0) end
    return unpack_values(values, 2, values.n)
end

function PerfCounter:activeMilliseconds()
    local active_ms = self.active_ms
    if self.enabled and self.enabled_at then
        active_ms = active_ms + math.max(0, self.clock() - self.enabled_at)
    end
    return active_ms
end

function PerfCounter:hasMeasurements()
    return next(self.metrics) ~= nil
end

function PerfCounter:snapshot()
    local metrics = {}
    for name, metric in pairs(self.metrics) do
        metrics[name] = copyMetric(metric)
    end
    return {
        enabled = self.enabled,
        active_ms = self:activeMilliseconds(),
        metrics = metrics,
    }
end

function PerfCounter:format()
    local snapshot = self:snapshot()
    local rows = {}
    for name, metric in pairs(snapshot.metrics) do
        table.insert(rows, { name = name, metric = metric })
    end
    table.sort(rows, function(a, b)
        if a.metric.total_ms == b.metric.total_ms then
            if a.metric.calls == b.metric.calls then return a.name < b.name end
            return a.metric.calls > b.metric.calls
        end
        return a.metric.total_ms > b.metric.total_ms
    end)

    local lines = {
        string.format("counter_enabled=%s", tostring(snapshot.enabled)),
        string.format("active_ms=%.3f", snapshot.active_ms),
        "",
        string.format("%-42s %7s %11s %10s %10s %7s",
            "metric", "calls", "total_ms", "avg_ms", "max_ms", "errors"),
        string.rep("-", 105),
    }
    for _, row in ipairs(rows) do
        local metric = row.metric
        local average = metric.calls > 0 and metric.total_ms / metric.calls or 0
        table.insert(lines, string.format("%-42s %7d %11.3f %10.3f %10.3f %7d",
            row.name, metric.calls, metric.total_ms, average, metric.max_ms, metric.errors))
    end
    if #rows == 0 then table.insert(lines, "(no measurements)") end
    return table.concat(lines, "\n")
end

return PerfCounter
