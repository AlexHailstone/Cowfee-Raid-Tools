local ADDON, CRT = ...

-- /crt perf: this addon's CPU cost, from the game's own profiler (C_AddOnProfiler, added in 11.0.7).
-- It is always on and needs no setting. Every metric the game offers is printed, with this addon's
-- value beside the total for all addons, so the numbers can be compared before and after a change.
-- Time metrics are milliseconds per frame (a "tick"), and the "Count" metrics are numbers of frames.
-- Everything resets on /reload.

local Perf = {}
CRT.Perf = Perf

local function metricNames()
    local list = {}
    for name, value in pairs(Enum and Enum.AddOnProfilerMetric or {}) do
        list[#list + 1] = { name = name, value = value }
    end
    table.sort(list, function(a, b)
        return a.value < b.value
    end)
    return list
end

local function read(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok and type(result) == "number" and not (issecretvalue and issecretvalue(result)) then
        return result
    end
    return nil
end

local function show(name, value)
    if not value then
        return "-"
    end
    if name:find("^Count") or not name:find("Time") then
        return format("%d", value)
    end
    return format("%.3f ms", value)
end

function Perf:Report()
    local profiler = C_AddOnProfiler
    if not (profiler and profiler.GetAddOnMetric) then
        CRT:Print("This game client has no addon profiler (C_AddOnProfiler).")
        return
    end
    local names = metricNames()
    if #names == 0 then
        CRT:Print("The addon profiler gave no metrics.")
        return
    end
    CRT:Print("CPU use since the last /reload: this addon, then all addons together.")
    for _, m in ipairs(names) do
        local mine = read(profiler.GetAddOnMetric, ADDON, m.value)
        local all = profiler.GetOverallMetric and read(profiler.GetOverallMetric, m.value)
        local share = ""
        if mine and all and all > 0 and m.name:find("Time") and not m.name:find("^Count") then
            share = format("  (%.0f%% of all addons)", mine / all * 100)
        end
        print(format("  %s: %s, all addons %s%s", m.name, show(m.name, mine), show(m.name, all), share))
    end
end
