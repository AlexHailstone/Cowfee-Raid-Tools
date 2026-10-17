local ADDON, CRT = ...

-- The Timeline page's Review tab controls: the Difficulty, Boss and Pull dropdowns, the recording
-- and overlay checkboxes, the zoom slider, the Recent pulls list and the timeline view itself. The
-- page builds it with Build(parent, ctx) and gets back { view, holder, recent, emptyLabel,
-- unnamedHelp, controls }, the controls being everything it must call refresh() on. The page keeps
-- the choices (difficulty, boss, pull, overlay); ctx gives this file group(), boss(), pull() and
-- the setters selectGroup(key), selectBoss(key), selectPull(key), selectOrder(key),
-- toggleOverlay(pullID) and movePhase(index, seconds), plus bossOptions, pullOptions, orderOptions,
-- order(), hasOrder(), pullLabel, showingReference() and groups (the label of each difficulty group).

local Timeline = CRT.Timeline
local View = CRT.TimelineView
local ReferencePage = CRT.TimelineReferencePage
local UI = CRT.UI

local ReviewTab = {}
CRT.TimelineReviewTab = ReviewTab

local RECENT_W = 150
ReviewTab.RECENT_W = RECENT_W

local EMPTY_ALL = "No boss pulls recorded yet"

local function settings()
    return Timeline:Settings()
end

function ReviewTab.Build(f, ctx)
    local tab = { controls = {} }
    local controls = tab.controls

    -- A checkbox with its text on the right. get() is the setting, set(on) saves it.
    local function checkbox(x, y, text, get, set)
        local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", f, "TOPLEFT", x - 4, y)
        cb.Label = f:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
        cb.Label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        cb.Label:SetJustifyH("LEFT")
        cb.Label:SetText(text)
        cb:SetScript("OnClick", function(self)
            set(self:GetChecked() and true or false)
        end)
        cb.refresh = function()
            cb:SetChecked(get() and true or false)
        end
        controls[#controls + 1] = cb
        return cb
    end

    local function place(row, x, y)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
        controls[#controls + 1] = row
        return row
    end

    -- Difficulty first: it decides what the Boss and Pull lists hold.
    place(UI.Dropdown(f, "Difficulty", {
        options = {
            { key = "nh", label = ctx.groups.nh },
            { key = "mythic", label = ctx.groups.mythic },
        },
        labelWidth = 52,
        width = 110,
        get = ctx.group,
        set = ctx.selectGroup,
    }), 8, -4)
    UI.Help(f, "Difficulty", "Normal and Heroic share one schedule, so they are one view, and Mythic is the other. The boss list, the pulls, the references and the recent pulls show only the difficulty picked here. The page starts on Normal/Heroic each time.\n\nRows and abilities that are Mythic-only never show on Normal/Heroic."):SetPoint("TOPLEFT", f, "TOPLEFT", 176, -8)
    place(UI.Dropdown(f, "Boss", {
        options = ctx.bossOptions,
        labelWidth = 40,
        width = 170,
        get = ctx.boss,
        set = ctx.selectBoss,
    }), 200, -4)
    place(UI.Dropdown(f, "Pull", {
        options = ctx.pullOptions,
        labelWidth = 36,
        width = 190,
        get = ctx.pull,
        set = ctx.selectPull,
        enabledIf = function()
            return ctx.pull() ~= nil
        end,
    }), 424, -4)

    -- Order: shown only for a reference with an Order line. It sits beside Pull when the window is
    -- wide enough (popped out), else at the end of the second row, where the docked panel has room.
    local order = UI.Dropdown(f, "Order", {
        options = ctx.orderOptions,
        labelWidth = 40,
        width = 140,
        get = ctx.order,
        set = ctx.selectOrder,
    })
    local orderHelp = UI.Help(f, "Order", "The order your raid takes this boss's parts in, such as which turtle empowers first. Each part's abilities move into the window it now has; abilities shared by every part stay where they are.\n\nThe choice is kept for this boss and difficulty.")
    local ORDER_W, WIDE_X, NARROW_X = 40 + 5 + 140, 664, 498
    local function placeOrder()
        local wide = (f:GetWidth() or 0) >= WIDE_X + ORDER_W + 32
        order:ClearAllPoints()
        order:SetPoint("TOPLEFT", f, "TOPLEFT", wide and WIDE_X or NARROW_X, wide and -4 or -38)
        orderHelp:ClearAllPoints()
        orderHelp:SetPoint("LEFT", order, "RIGHT", 4, 0)
        local shown = ctx.hasOrder()
        order:SetShown(shown)
        orderHelp:SetShown(shown and wide)
    end
    local orderRefresh = order.refresh
    order.refresh = function()
        placeOrder()
        orderRefresh()
    end
    controls[#controls + 1] = order
    if f.HookScript then
        f:HookScript("OnSizeChanged", placeOrder)
    end

    checkbox(8, -38, "Record every pull", function()
        return settings().record
    end, function(on)
        Timeline:Set("record", on)
    end)
    local overlay = checkbox(220, -38, "Deaths from recent pulls", function()
        return settings().overlayOn
    end, function(on)
        Timeline:Set("overlayOn", on)
    end)
    overlay.Label:SetWidth(170)
    UI.Help(f, "Deaths from recent pulls", "Draws the deaths of the pulls before this one over it, faded by how old they are, so deaths that repeat stand out. How many pulls it covers is on the Settings tab."):SetPoint("TOPLEFT", f, "TOPLEFT", 440, -40)

    tab.unnamedHelp = UI.Help(f, "Unnamed casts", function()
        local text = "Some boss casts come from the game without a readable spell, so they are drawn in the \"Boss casts (unnamed)\" row with only their time. That is the game hiding the name, not a missing record."
        -- a reference has no casts of its own, so the hint is for recorded pulls only
        if tab.view and tab.view:CastCount() == 0 and ctx.pull() and not ctx.showingReference() then
            text = text .. "\n\nThis pull has no casts at all. The game's Boss Timeline option may be off, so no boss events arrived. Check it in the game's options."
        end
        return text
    end)
    tab.unnamedHelp:SetPoint("TOPLEFT", f, "TOPLEFT", 470, -40)

    -- Zoom: the mouse wheel writes span without telling the page, so refresh re-reads it here.
    place(UI.Slider(f, "Time visible", {
        min = 60, max = 600, step = 30, format = View.Format,
        labelWidth = 80, width = 160,
        get = function()
            return settings().span
        end,
        set = function(value)
            Timeline:Set("span", value)
            tab.view:SetSpan(value)
        end,
    }), 8, -64)

    tab.recent = ReferencePage.Recent(f, RECENT_W, ctx.pullLabel, ctx.toggleOverlay)

    tab.holder = CreateFrame("Frame", nil, f)
    tab.holder:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -96)
    tab.holder:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
    tab.view = View.Create(tab.holder)
    tab.view.onPhaseMoved = ctx.movePhase
    tab.emptyLabel = tab.holder:CreateFontString(nil, "OVERLAY", "CRTFontNormal")
    tab.emptyLabel:SetPoint("CENTER", tab.holder, "CENTER")
    tab.emptyLabel:SetText(EMPTY_ALL)
    return tab
end
