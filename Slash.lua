local ADDON, CRT = ...

local function printHelp()
    CRT:Print("v" .. CRT.version .. " commands:")
    print("  |cffffd100/crt|r - open or close the main panel")
    print("  |cffffd100/crt groups|r - open the Raid Groups page")
    print("  |cffffd100/crt consumables|r - open the Consumables page")
    print("  |cffffd100/crt readycheck|r - preview the ready check consumables row")
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
    elseif msg == "consumables" then
        CRT.UI:Show("consumables")
    elseif msg == "consumables scan" then
        CRT.ConsumablesTools:Scan()
    elseif msg == "consumables check" then
        CRT.ConsumablesTools:Check()
    elseif msg == "readycheck" or msg == "rc" then
        CRT.ConsumablesDisplay:Preview()
    elseif msg == "help" or msg == "?" then
        printHelp()
    else
        CRT:Print("Unknown command '" .. msg .. "'. Type /crt help for the list.")
    end
end
