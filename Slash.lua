local ADDON, CRT = ...

local function printHelp()
    CRT:Print("v" .. CRT.version .. " commands:")
    print("  |cffffd100/crt|r - open or close the main panel")
    print("  |cffffd100/crt groups|r - open the Raid Groups page")
    print("  |cffffd100/crt readycheck|r - open the Ready Check page (|cffffd100/crt consumables|r opens its Your bar tab)")
    print("  |cffffd100/crt check|r - open the ready check window for your group, open until you right-click it")
    print("  |cffffd100/crt check food|r, |cffffd100flask|r, |cffffd100rune|r, |cffffd100vantus|r, |cffffd100buffs|r or |cffffd100all|r - check the group, add |cffffd100chat|r to post it")
    print("  |cffffd100/crt rc|r - preview your ready check bar")
    print("  |cffffd100/crt debuffs|r - open the Debuffs page")
    print("  |cffffd100/crt debuffs info|r - diagnostics for the debuff panel")
    print("  |cffffd100/crt notes|r - open the Raid Notes page (|cffffd100/crt notes settings|r opens its Settings tab)")
    print("  |cffffd100/crt note test|r, |cffffd100next|r, |cffffd100stop|r - start the active note now, start the next phase, stop")
    print("  |cffffd100/crt late|r - open the Late Tracker page")
    print("  |cffffd100/crt late start|r, |cffffd100end|r - start tonight's raid now, or end it")
    print("  |cffffd100/crt late export|r - the late totals as text to paste into Discord")
    print("  |cffffd100/crt qol|r - open the Quality of Life page")
    print("  |cffffd100/crt lowhp off|r, |cffffd100on|r - turn the experimental low-health alert off or on")
    print("  |cffffd100/crt perf|r - this addon's CPU use since the last /reload, from the game's profiler")
    print("  |cffffd100/crt previews|r - toggle the panel previews, same as the button in the main window")
    print("  |cffffd100/crt consumables scan|r - list your buffs and bag consumables, for updating the list")
    print("  |cffffd100/crt consumables check|r - test every ID in the built-in consumables list")
    print("  |cffffd100/crt help|r - show this list")
end

SLASH_COWFEERAIDTOOLS1 = "/crt"
SlashCmdList["COWFEERAIDTOOLS"] = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "" then
        CRT.UI:Toggle()
    elseif msg == "groups" then
        CRT.UI:Show("groups")
    elseif msg == "readycheck" or msg == "ready" then
        CRT.ReadyCheckPage.Open("report")
    elseif msg == "consumables" then
        CRT.ReadyCheckPage.Open("bar")
    elseif msg == "check" then
        CRT.ReadyCheckWindow:Show(nil, false, true)
    elseif msg:match("^check") then
        local what, chat = msg:match("^check%s*(%a*)%s*(%a*)$")
        local keys = {}
        for _, check in ipairs(CRT.RaidReport.CHECKS) do
            if what == "all" or what == check.key or (what == "buff" and check.key == "buffs") then
                keys[#keys + 1] = check.key
            end
        end
        if #keys == 0 then
            CRT:Print("Use /crt check food, flask, rune, vantus, buffs or all, and add chat to post it.")
        else
            CRT.RaidReport:Check(keys, chat == "chat")
        end
    elseif msg == "consumables scan" then
        CRT.ConsumablesTools:Scan()
    elseif msg == "consumables check" then
        CRT.ConsumablesTools:Check()
    elseif msg == "debuffs" then
        CRT.UI:Show("debuffs")
    elseif msg == "debuffs info" then
        CRT.DebuffPanel:ShowInfo()
    elseif msg == "notes" then
        CRT.NotesPage.Open("notes")
    elseif msg == "notes settings" then
        CRT.NotesPage.Open("settings")
    elseif msg == "note test" then
        local id = CRT.Notes:Active()
        if id then
            CRT.NoteEngine:Start(CRT.Notes:Parsed(id), "test")
        else
            CRT:Print("No note is in use. Pick one on the Raid Notes page.")
        end
    elseif msg == "note next" then
        local ph = CRT.NoteEngine:NextPhase()
        CRT:Print(ph and ("Phase " .. ph .. " started.") or "No phase left to start, or nothing is running.")
    elseif msg == "note stop" then
        CRT.NoteEngine:Stop()
    elseif msg == "late" then
        CRT.UI:Show("late")
    elseif msg == "late export" then
        CRT.LatePage.ExportTotals()
    elseif msg == "late start" then
        if CRT.Late:Start("button", time()) then
            CRT:Print("Raid night started.")
        end
    elseif msg == "late end" then
        if CRT.Late:Current() then
            CRT.Late:End("button", time())
            CRT:Print("Raid night ended and saved to the history.")
        else
            CRT:Print("No raid night is running.")
        end
    elseif msg == "lowhp off" or msg == "lowhp on" then
        CRT.LowHealth:SetEnabled(msg == "lowhp on")
        CRT:Print("Low-health alert " .. (msg == "lowhp on" and "on." or "off."))
    elseif msg == "qol" then
        CRT.UI:Show("qol")
    elseif msg == "perf" then
        CRT.Perf:Report()
    elseif msg == "previews" then
        CRT.UI:TogglePreviews()
    elseif msg == "rc" then
        CRT.ConsumablesDisplay:Preview()
    elseif msg == "help" or msg == "?" then
        printHelp()
    else
        CRT:Print("Unknown command '" .. msg .. "'. Type /crt help for the list.")
    end
end
