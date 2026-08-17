local PerfCounter = dofile("core/perf_counter.lua")

local now = 100
local counter = PerfCounter.new{
    enabled = true,
    clock = function() return now end,
}

local first, second = counter:measure("phase.example", function()
    now = now + 5
    return "one", "two"
end)
assert(first == "one" and second == "two")

local ok = counter:safeCall("native.example", function()
    now = now + 3
    error("expected")
end)
assert(ok == false)

counter:mark("cache.example.hit", 2)
local snapshot = counter:snapshot()
assert(snapshot.metrics["phase.example"].calls == 1)
assert(snapshot.metrics["phase.example"].total_ms == 5)
assert(snapshot.metrics["native.example"].errors == 1)
assert(snapshot.metrics["cache.example.hit"].calls == 2)

counter:setEnabled(false)
now = now + 10
counter:mark("ignored")
assert(counter:snapshot().metrics.ignored == nil)
assert(counter:format():find("phase.example", 1, true))

counter:reset()
assert(counter:hasMeasurements() == false)

print("perf_counter_spec: ok")
