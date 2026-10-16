local ADDON, CRT = ...

-- Alerts engine: the blocks that supply alert items, the run (one pull) and its phase clock, and the
-- timed lines everything else reads. A block (the note, your reminders, a shared pack) registers with
-- RegisterBlock and answers Entries(run) with items: an entry as AlertRules describes it, without `at`,
-- plus `ph` (the phase it belongs to) and `time` (seconds into that phase). A speech item carries
-- `offset` (seconds before the entry) instead of `at`. Start collects every block's items once, so a
-- block edited mid-pull shows on the next start. The run's lowest phase (1 when nothing names one) starts at the pull; a later phase starts when
-- its event fires or Next phase is pressed, and starting one skips every earlier phase that never began.
-- Settings are read from CRT.db.alerts fresh each time, so a profile switch or reset mid-pull is safe.

local Rules = CRT.AlertRules

local Alerts = {
    listeners = {},
    blocks = {},       -- [key] = def
    blockOrder = {},   -- keys in registration order
    onPull = {},       -- functions (run) called when an encounter run starts, before items are collected
    phaseSources = {}, -- functions (run) -> { ph }: phases that come from events rather than items
    running = false,
    runId = 0,
}
CRT.Alerts = Alerts

-- Calls fn inside pcall, sending a failure to the error handler. Returns ok, result.
local function safe(fn, ...)
    local ok, res = pcall(fn, ...)
    if not ok and geterrorhandler then
        geterrorhandler()(res)
    end
    return ok, res
end

function Alerts:Settings()
    return CRT.db.alerts
end

function Alerts:OnChange(fn)
    self.listeners[#self.listeners + 1] = fn
end

function Alerts:Fire()
    for _, fn in ipairs(self.listeners) do
        -- A listener (a window) failing must never stop the engine or the other listeners.
        safe(fn)
    end
end

-- def = { label, group = bool, Entries = function(run) -> { item } }. Registering a key again replaces it.
function Alerts:RegisterBlock(key, def)
    if not self.blocks[key] then
        self.blockOrder[#self.blockOrder + 1] = key
    end
    self.blocks[key] = def
end

-- Every block's items for a run, each copied and stamped with its block key. A failing block is skipped.
-- opts.blocks limits which blocks run; opts.filter(blockKey, item) -> bool keeps only some items.
function Alerts:Collect(run, opts)
    local out = {}
    for _, key in ipairs(self.blockOrder) do
        local def = self.blocks[key]
        if def and (not (opts and opts.blocks) or opts.blocks[key]) then
            local ok, list = safe(def.Entries, run)
            if ok and type(list) == "table" then
                for _, it in ipairs(list) do
                    local keep = type(it) == "table"
                    if keep and opts and opts.filter then
                        local okF, res = safe(opts.filter, key, it)
                        keep = okF and res and true or false
                    end
                    if keep then
                        local copy = {}
                        for k, v in pairs(it) do copy[k] = v end
                        copy.block = key
                        copy.ph = type(copy.ph) == "number" and copy.ph or 1
                        copy.time = type(copy.time) == "number" and copy.time or 0
                        out[#out + 1] = copy
                    end
                end
            end
        end
    end
    return out
end

-- The sorted phases for a run: those of the given items and of the phase sources, or just 1 when
-- nothing names a phase. The lowest is the one that starts at the pull.
local function phaseList(self, run, items)
    local seen, list = {}, {}
    local function add(ph)
        if type(ph) == "number" and not seen[ph] then
            seen[ph] = true
            list[#list + 1] = ph
        end
    end
    for _, it in ipairs(items) do
        add(it.ph)
    end
    for _, fn in ipairs(self.phaseSources) do
        local ok, res = safe(fn, run)
        if ok and type(res) == "table" then
            for _, ph in ipairs(res) do
                add(ph)
            end
        end
    end
    if #list == 0 then
        list[1] = 1
    end
    table.sort(list)
    return list
end

-- The phases a run would have, without starting anything.
function Alerts:PhasesFor(run)
    return phaseList(self, run, self:Collect(run))
end

-- The phases of the current run (its collected items and the phase sources, or 1).
function Alerts:Phases()
    if not self.running then
        return { 1 }
    end
    return phaseList(self, self.run, self.items)
end

-- Starts a run. reason "encounter" also runs the onPull hooks (the note engine picks its note there).
-- Alerts.starting is true while the hooks and the first phase run, so a hook can tell not to start again.
-- opts.firstAt is the start time recorded for the lowest phase (default now): the editor's Test uses it to
-- begin a reminder a few seconds before its first time.
function Alerts:Start(encounterID, difficultyName, reason, opts)
    if self.running then
        self:Stop(true)
    end
    local run = { encounterID = encounterID, difficultyName = difficultyName, reason = reason }
    self.run = run
    self.starting = true
    self.runId = self.runId + 1
    self.running = true
    self.starts, self.skipped = {}, {}
    self.items = {}
    if reason == "encounter" then
        for _, fn in ipairs(self.onPull) do
            safe(fn, run)
        end
    end
    -- A hook may have called Stop; only carry on if this run is still the current one.
    -- Anything failing here must still clear `starting`, so it runs inside pcall.
    local ok, err = pcall(function()
        if self.run == run then
            self.items = self:Collect(run, opts)
            self:StartPhase(self:Phases()[1], "start", opts and type(opts.firstAt) == "number" and opts.firstAt or GetTime())
        end
    end)
    self.starting = false
    if not ok and geterrorhandler then
        geterrorhandler()(err)
    end
    self:Fire()
end

-- Ends the run. `quiet` skips the change notice (used when a new start follows at once).
function Alerts:Stop(quiet)
    self.running = false
    self.run = nil
    self.items, self.starts, self.skipped = {}, {}, {}
    if not quiet then
        self:Fire()
    end
end

-- Starts a phase now (or at `at`). False when no run is going or the phase already started.
-- Every earlier phase that never started is marked skipped.
function Alerts:StartPhase(ph, source, at)
    -- A skipped phase never starts: its alerts must not fire once a later phase has begun.
    if not self.running or type(ph) ~= "number" or self.starts[ph] or self.skipped[ph] then
        return false
    end
    self.starts[ph] = at or GetTime()
    for _, p in ipairs(self:Phases()) do
        if p < ph and not self.starts[p] then
            self.skipped[p] = true
        end
    end
    if not self.run.firstAt then
        self.run.firstAt = self.starts[ph]
    end
    if not self.starting then
        self:Fire()
    end
    return true
end

-- Starts the first phase that has neither started nor been skipped. Returns it, or nil.
function Alerts:NextPhase()
    if not self.running then
        return nil
    end
    for _, ph in ipairs(self:Phases()) do
        if not self.starts[ph] and not self.skipped[ph] then
            self:StartPhase(ph, "next")
            return ph
        end
    end
    return nil
end

function Alerts:PhaseStart(ph)
    return self.starts and self.starts[ph] or nil
end

function Alerts:Skipped(ph)
    return self.skipped and self.skipped[ph] and true or false
end

-- The started phase with the latest start.
function Alerts:CurrentPhase()
    local best, bestAt
    for ph, at in pairs(self.starts or {}) do
        if not bestAt or at > bestAt or (at == bestAt and ph > best) then
            best, bestAt = ph, at
        end
    end
    return best
end

-- Seconds since the first phase started.
function Alerts:Elapsed()
    if not self.running or not self.run.firstAt then
        return nil
    end
    return GetTime() - self.run.firstAt
end

-- The timed lines of the run: items of started phases, through the conflict rules.
function Alerts:Lines(now)
    if not self.running then
        return {}
    end
    local entries = {}
    for _, it in ipairs(self.items) do
        local start = self.starts[it.ph]
        if start and not self.skipped[it.ph] then
            local e = {}
            for k, v in pairs(it) do e[k] = v end
            e.at = start + it.time
            if it.speech then
                e.speech = {}
                for i, s in ipairs(it.speech) do
                    e.speech[i] = { at = e.at - (s.offset or 0), text = s.text }
                end
            end
            entries[#entries + 1] = e
        end
    end
    local groupBlocks = {}
    for key, def in pairs(self.blocks) do
        if def.group then
            groupBlocks[key] = true
        end
    end
    return Rules.Lines(entries, groupBlocks)
end

function Alerts.HandleEvent(event, ...)
    if event == "ENCOUNTER_START" then
        local encounterID, _, difficultyID = ...
        local name
        if GetDifficultyInfo then
            local ok, n = pcall(GetDifficultyInfo, difficultyID)
            if ok and type(n) == "string" and not (issecretvalue and issecretvalue(n)) then
                name = n
            end
        end
        Alerts:Start(encounterID, name, "encounter")
    elseif event == "ENCOUNTER_END" then
        if Alerts.running and Alerts.run.reason == "encounter" then
            Alerts:Stop()
        end
    end
end

local driver = CreateFrame("Frame")
driver:RegisterEvent("ENCOUNTER_START")
driver:RegisterEvent("ENCOUNTER_END")
driver:SetScript("OnEvent", function(_, event, ...)
    Alerts.HandleEvent(event, ...)
end)
