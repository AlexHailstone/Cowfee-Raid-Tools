local ADDON, CRT = ...

-- Shared settings controls in the style of the game's Edit Mode panels: a label on the left and the
-- control on its right, in a row 32 pixels high. They use the same game templates as
-- Blizzard_EditMode's EditModeSettingDropdownTemplate and EditModeSettingSliderTemplate:
--   UI.Dropdown  WowStyle1DropdownTemplate, a dropdown with a radio list of choices
--   UI.Slider    MinimalSliderWithSteppersTemplate, a bar with < and > steppers and the value on
--                its right
-- A setting with a few fixed choices is always a dropdown, never a button that cycles through them.

local UI = CRT.UI

local ROW_H = 32
local LABEL_W = 140
local GAP = 5
local VALUE_W = 44 -- room for the slider's value, which the template draws to the right of the bar

-- The row and its label. The label's own color is kept, so greying out can put it back.
local function makeRow(parent, text, labelWidth)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)
    row.Label = row:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    row.Label:SetPoint("LEFT")
    row.Label:SetWidth(labelWidth or LABEL_W)
    row.Label:SetJustifyH("LEFT")
    row.Label:SetWordWrap(false)
    row.Label:SetText(text)
    row.labelColor = { row.Label:GetTextColor() }
    return row
end

local function greyLabel(row, on)
    if on then
        row.Label:SetTextColor(row.labelColor[1], row.labelColor[2], row.labelColor[3])
    else
        row.Label:SetTextColor(0.5, 0.5, 0.5)
    end
end

-- A dropdown. opts:
--   options    { { key, label }, ... }, or a function returning that list when the menu opens
--   get()      the selected key
--   set(key)   called when a choice is picked
--   width, labelWidth, enabledIf() (greys the row out while it returns false)
-- Returns the row, with row.refresh() to call when the setting may have changed.
function UI.Dropdown(parent, text, opts)
    local labelWidth, width = opts.labelWidth or LABEL_W, opts.width or 200
    local row = makeRow(parent, text, labelWidth)
    row:SetWidth(labelWidth + GAP + width)

    local dropdown = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate")
    dropdown:SetWidth(width)
    dropdown:SetPoint("LEFT", row.Label, "RIGHT", GAP, 0)
    dropdown:SetupMenu(function(_, root)
        local list = type(opts.options) == "function" and opts.options() or opts.options
        for _, option in ipairs(list) do
            root:CreateRadio(option.label, function(key)
                return opts.get() == key
            end, function(key)
                opts.set(key)
            end, option.key)
        end
    end)
    row.Dropdown = dropdown

    row.refresh = function()
        -- Rebuilds the menu, which also updates the text shown on the closed dropdown.
        dropdown:GenerateMenu()
        if opts.enabledIf then
            local on = opts.enabledIf() and true or false
            dropdown:SetEnabled(on)
            greyLabel(row, on)
        end
    end
    return row
end

-- A slider. opts:
--   min, max, step (default 1)
--   get(), set(value)   value is always a whole step
--   format(value)       the text beside the bar, by default the number
--   onRelease           true to call set only when the mouse lets go of the bar, for a slider that
--                       resizes the window it sits in. The steppers still apply each click.
--   width, labelWidth, enabledIf()
-- Returns the row, with row.refresh().
function UI.Slider(parent, text, opts)
    local labelWidth, width = opts.labelWidth or LABEL_W, opts.width or 200
    local low, high, step = opts.min, opts.max, opts.step or 1
    local row = makeRow(parent, text, labelWidth)
    row:SetWidth(labelWidth + GAP + width + VALUE_W)

    local function snap(value)
        return math.floor((value - low) / step + 0.5) * step + low
    end
    local format = opts.format or tostring

    local slider = CreateFrame("Frame", nil, row, "MinimalSliderWithSteppersTemplate")
    slider:SetSize(width, ROW_H)
    slider:SetPoint("LEFT", row.Label, "RIGHT", GAP, 0)
    local Label, Event = MinimalSliderWithSteppersMixin.Label, MinimalSliderWithSteppersMixin.Event
    local formatters = {
        [Label.Right] = CreateMinimalSliderFormatter(Label.Right, function(value)
            return format(snap(value))
        end),
    }
    slider:Init(opts.get() or low, low, high, (high - low) / step, formatters)
    row.Slider = slider

    -- updating: the value is being set from the saved setting, so it is not saved back.
    -- dragging and pending: with onRelease, the value waits until the mouse lets go.
    local updating, dragging, pending = false, false, nil
    slider:RegisterCallback(Event.OnValueChanged, function(_, value)
        if updating then
            return
        end
        value = snap(value)
        if opts.onRelease and dragging then
            pending = value
            return
        end
        opts.set(value)
    end, row)
    slider:RegisterCallback(Event.OnInteractStart, function()
        dragging = true
    end, row)
    slider:RegisterCallback(Event.OnInteractEnd, function()
        dragging = false
        if pending ~= nil then
            local value = pending
            pending = nil
            opts.set(value)
        end
    end, row)

    row.refresh = function()
        if not dragging then
            updating = true
            slider:SetValue(opts.get() or low)
            updating = false
        end
        if opts.enabledIf then
            local on = opts.enabledIf() and true or false
            slider:SetEnabled(on)
            greyLabel(row, on)
        end
    end
    return row
end
