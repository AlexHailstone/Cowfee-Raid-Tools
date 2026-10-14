local ADDON, CRT = ...

-- Your next assignment: a movable alert that appears only when a timer with your name (or your role) is
-- coming up, shows the spell or text with a countdown, and can read it out with text to speech.

local Notes = CRT.Notes
local Engine = CRT.NoteEngine
local Alert = {}
CRT.NoteAlert = Alert

local REFRESH_SECONDS = 0.1

local frame, handle, icon, label, countdown
local previewOn = false
local elapsed = 0
local spoken = {} -- "runId:index" -> true once read out

local function settings()
    return Notes:Alert()
end

-- Text to speech ------------------------------------------------------------------------

local function voiceId()
    if C_TTSSettings and C_TTSSettings.GetVoiceOptionID then
        local voiceType = (Enum and Enum.TtsVoiceType and Enum.TtsVoiceType.Standard) or 0
        local ok, id = pcall(C_TTSSettings.GetVoiceOptionID, voiceType)
        if ok and type(id) == "number" then
            return id
        end
    end
    if C_VoiceChat and C_VoiceChat.GetTtsVoices then
        local ok, voices = pcall(C_VoiceChat.GetTtsVoices)
        if ok and type(voices) == "table" and voices[1] then
            return voices[1].voiceID
        end
    end
    return nil
end

function Alert:Speak(text)
    if not (C_VoiceChat and C_VoiceChat.SpeakText) then
        CRT:Print("Text to speech isn't available on this client.")
        return
    end
    local id = voiceId()
    if not id then
        CRT:Print("No text to speech voice is installed. Check the game's Text to Speech settings.")
        return
    end
    local s = settings()
    local ok, err = pcall(C_VoiceChat.SpeakText, id, text, s.ttsRate or 0, s.ttsVolume or 100, false)
    if not ok then
        CRT:Print("Text to speech failed: " .. tostring(err))
    end
end

-- The alert -------------------------------------------------------------------------------

local function show(iconTexture, text, time, color)
    icon:SetShown(iconTexture ~= nil)
    if iconTexture then
        icon:SetTexture(iconTexture)
    end
    label:SetText(text)
    if color then
        label:SetTextColor(color[1], color[2], color[3])
    else
        label:SetTextColor(1, 0.82, 0)
    end
    countdown:SetText(time)
    frame:Show()
end

local function countdownText(remaining)
    if remaining <= 0 then
        return "NOW"
    elseif remaining < 10 then
        return format("%.1f", remaining)
    end
    return tostring(math.floor(remaining))
end

function Alert:Refresh()
    if not frame then
        return
    end
    handle:SetShown(previewOn)
    if previewOn then
        local info = Notes:SpellInfo(31884)
        show(info and info.icon or 134400, info and info.name or "Your spell", "5.0")
        return
    end
    local s = settings()
    if not (s.enabled and Engine.running and Engine:Note()) then
        frame:Hide()
        return
    end

    local note = Engine:Note()
    local best, bestRemaining
    for index, item in ipairs(note.timers) do
        if Engine:IsMine(item) then
            local remaining = Engine:Remaining(item)
            if remaining then
                -- Read it out once, as it reaches the speech time. Skip any that passed long ago.
                local key = Engine.runId .. ":" .. index
                if s.tts and not spoken[key] and remaining <= (s.ttsSeconds or 3) then
                    spoken[key] = true
                    if remaining > -1 then
                        local info = item.kind == "spell" and Notes:SpellInfo(item.spellId)
                        self:Speak(info and info.name or item.text or "")
                    end
                end
                local window = item.kind == "text" and (item.dur or 0) or 0.5
                if remaining <= (s.seconds or 10) and remaining > -window then
                    if not bestRemaining or remaining < bestRemaining then
                        best, bestRemaining = item, remaining
                    end
                end
            end
        end
    end

    if not best then
        frame:Hide()
        return
    end
    if best.kind == "spell" then
        local info = Notes:SpellInfo(best.spellId)
        show(info and info.icon, info and info.name or ("Spell " .. best.spellId), countdownText(bestRemaining))
    else
        show(nil, best.text or "", countdownText(bestRemaining), best.color)
    end
end

local function applyPosition()
    local p = settings().position or { point = "CENTER", relativePoint = "CENTER", x = 0, y = 220 }
    frame:ClearAllPoints()
    frame:SetPoint(p.point, UIParent, p.relativePoint or p.point, p.x, p.y)
end

function Alert:ResetPosition()
    settings().position = nil
    if frame then
        applyPosition()
    end
end

local function build()
    if frame then
        return
    end
    frame = CreateFrame("Frame", "CowfeeRaidToolsNoteAlert", UIParent)
    frame:SetSize(320, 56)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)

    icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(52, 52)
    icon:SetPoint("LEFT", 0, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    label = frame:CreateFontString(nil, "OVERLAY", "CRTFontLarge")
    label:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
    label:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    label:SetJustifyH("LEFT")
    label:SetShadowOffset(1, -1)

    countdown = frame:CreateFontString(nil, "OVERLAY", "CRTFontLarge")
    countdown:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 10, 2)
    countdown:SetTextColor(1, 1, 1)
    countdown:SetShadowOffset(1, -1)

    handle = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    handle:SetHeight(20)
    handle:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2)
    handle:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 2)
    handle:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    handle:SetBackdropColor(0.3, 0.25, 0.05, 0.9)
    handle:SetBackdropBorderColor(1, 0.82, 0, 1)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    local text = handle:CreateFontString(nil, "OVERLAY", "CRTFontSmall")
    text:SetPoint("CENTER")
    text:SetText("Your next spell: drag to move")
    handle:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    handle:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local point, _, relativePoint, x, y = frame:GetPoint()
        settings().position = { point = point, relativePoint = relativePoint, x = x, y = y }
    end)
    handle:Hide()

    applyPosition()
    frame:Hide()
end

-- The alert hides itself when there is nothing to show, so this frame keeps it updated.
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < REFRESH_SECONDS then
        return
    end
    elapsed = 0
    if frame then
        Alert:Refresh()
    end
end)
ticker:RegisterEvent("PLAYER_LOGIN")
ticker:SetScript("OnEvent", function()
    build()
end)

CRT.UI:RegisterPreview("alert", function(on)
    build()
    previewOn = on and true or false
    Alert:Refresh()
    if not previewOn and not Engine.running then
        frame:Hide()
    end
end)
