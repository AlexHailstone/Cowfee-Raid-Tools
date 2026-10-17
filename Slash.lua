local ADDON, CRT = ...

local function printHelp()
    CRT:Print("v" .. CRT.version .. " commands:")
    print("  |cffffd100/crt|r - open or close the main panel")
    print("  |cffffd100/crt groups|r - open the Raid Groups page")
    print("  |cffffd100/crt readycheck|r - open the Ready Check page (|cffffd100/crt consumables|r opens its Your bar tab)")
    print("  |cffffd100/crt check|r - open the ready check window for your group, open until you right-click it")
    print("  |cffffd100/crt check food|r, |cffffd100flask|r, |cffffd100rune|r, |cffffd100vantus|r, |cffffd100buffs|r or |cffffd100all|r - check the group, add |cffffd100chat|r to post it")
    print("  |cffffd100/crt rc|r - preview your ready check bar")
    print("  |cffffd100/crt debuffs|r - open the Debuffs tab on Quality of Life")
    print("  |cffffd100/crt notes|r - open the Raid Notes page (|cffffd100/crt notes settings|r opens its Settings tab)")
    print("  |cffffd100/crt reminders|r - open the Reminders tab of Raid Notes")
    print("  |cffffd100/crt note test|r, |cffffd100next|r, |cffffd100stop|r - start the active note now, start the next phase, stop")
    print("  |cffffd100/crt late|r - open the Late Tracker page")
    print("  |cffffd100/crt late start|r, |cffffd100end|r - start tonight's raid now, or end it")
    print("  |cffffd100/crt late export|r - the late totals as text to paste into Discord")
    print("  |cffffd100/crt tattle|r - open the Tattlebot page")
    print("  |cffffd100/crt tattle post|r, |cffffd100night|r, |cffffd100end|r - post the last pull or tonight's totals, or end the night")
    print("  |cffffd100/crt tattle scan|r - pick spells to track from the last fight (|cffffd100/crt tattle scan text|r for the plain list)")
    print("  |cffffd100/crt tattle export|r - the Tattlebot totals as text to paste into Discord")
    print("  |cffffd100/crt pace|r - open the Pace page: where each boss's health should be")
    print("  |cffffd100/crt timeline|r - open the Timeline page (|cffffd100/crt timeline pop|r opens it in its own window)")
    print("  |cffffd100/crt break 10|r - a 10 minute break timer (any minutes, 0 cancels); from a raid leader or assistant it reaches the whole raid")
    print("  |cffffd100/crt qol|r - open the Quality of Life page (low health and debuffs)")
    print("  |cffffd100/crt settings|r - open General Settings: window, fonts, sound, minimap button, layers, profiles")
    print("  |cffffd100/crt minimap|r - show or hide the minimap button")
    print("  |cffffd100/crt lowhp off|r, |cffffd100on|r, |cffffd100info|r, |cffffd100stop|r - turn the experimental low-health alert off or on, print its diagnostics, or stop any sound it is playing")
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
        CRT.ReadyCheckPage.Open("window")
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
        CRT.QoLPage.Open("debuffs")
    elseif msg == "notes" then
        CRT.NotesPage.Open("notes")
    elseif msg == "reminders" then
        CRT.NotesPage.Open("reminders")
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
    elseif msg == "timeline" then
        CRT.UI:Show("timeline")
    elseif msg == "pace" then
        CRT.UI:Show("pace")
    elseif msg == "timeline pop" then
        CRT.TimelinePopout()
    elseif msg == "tattle" then
        CRT.UI:Show("tattle")
    elseif msg == "tattle post" then
        CRT.Tattle:PostLastPull()
    elseif msg == "tattle night" then
        CRT.Tattle:PostNight()
    elseif msg == "tattle end" then
        if CRT.Tattle:Current() then
            CRT.Tattle:EndNight("button")
            CRT:Print("Tattlebot night ended and saved to the history.")
        else
            CRT:Print("No Tattlebot night is running.")
        end
    elseif msg == "tattle scan text" then
        CRT.TattlePage.ScanText()
    elseif msg == "tattle scan" then
        CRT.TattlePage.Scan()
    elseif msg == "tattle export" then
        CRT.TattlePage.ExportTotals()
    elseif msg == "lowhp stop" then
        CRT.LowHealthSound:StopAll()
        CRT:Print("Stopped every low-health sound the addon was playing.")
    elseif msg == "lowhp info" then
        CRT.LowHealth:Info()
    elseif msg == "lowhp off" or msg == "lowhp on" then
        CRT.LowHealth:SetEnabled(msg == "lowhp on")
        CRT:Print("Low-health alert " .. (msg == "lowhp on" and "on." or "off."))
    --@do-not-package@
    elseif msg == "dev debuffs" then
        CRT.DebuffPanel:ShowInfo()
    elseif msg == "dev seasons" then
        if CRT.SeasonTools then
            CRT.SeasonTools:Toggle()
        end
    elseif msg == "dev markers" then
        if CRT.MarkerEditor then
            CRT.MarkerEditor:Toggle()
        end
    elseif msg == "dev types" then
        if CRT.ReferenceTypes then
            CRT.ReferenceTypes:Toggle()
        end
    elseif msg == "dev reset" then
        if CRT.Dev then
            CRT.Dev:ResetAllPositions()
        end
    elseif msg == "dev clear" then
        if CRT.Dev then
            CRT.Dev:ClearAll()
        end
    elseif msg == "dev probe show" or msg == "dev probe" then
        if CRT.TimelineProbe then
            if msg == "dev probe" then
                CRT.TimelineProbe:Arm()
            else
                CRT.TimelineProbe:Show()
            end
        else
            CRT:Print("The timeline probe is not loaded.")
        end
    elseif msg == "dev edit" then
        if CRT.Dev then
            CRT.Dev:Toggle()
        end
    elseif msg == "dev" then
        if CRT.UI.pages.dev then
            CRT.UI:SetPageHidden("dev", false)
            CRT.UI:Show("dev")
        else
            CRT:Print("The Development page is not loaded.")
        end
    --@end-do-not-package@
    elseif msg == "break" or msg:match("^break%s") then
        CRT.BreakTimer:Command(msg:match("^break%s+(%S+)"))
    elseif msg == "qol" then
        CRT.UI:Show("qol")
    elseif msg == "settings" then
        CRT.UI:Show("settings")
    elseif msg == "minimap" then
        local hide = not CRT.db.minimap.hide
        CRT.MinimapButton:SetHidden(hide)
        CRT:Print(hide and "Minimap button hidden. Type /crt minimap to show it again." or "Minimap button shown.")
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
