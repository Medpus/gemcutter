local addonName, ns = ...
local Core, Progression = ns.Core, ns.Progression

function ns.NewSeed()
    return math.random(1, 2147483646)
end

local function InitDB()
    if type(GemFlightDB) ~= "table" then GemFlightDB = {} end
    local db = GemFlightDB

    if type(db.profile) ~= "table" then db.profile = Progression.NewProfile() end
    db.profile = Progression.Upgrade(db.profile)

    if type(db.minimap) ~= "table" then db.minimap = {} end
    if type(db.minimap.angle) ~= "number" then db.minimap.angle = 200 end
    db.minimap.hide = db.minimap.hide == true

    if type(db.window) ~= "table" then db.window = {} end
    if type(db.window.scale) ~= "number" then db.window.scale = 1 end
    if db.sound == nil then db.sound = true end

    ns.db = db
    ns.board = (type(db.board) == "table" and Core.Deserialize(db.board)) or Core.NewBoard(ns.NewSeed())
end

-- Teller hver flytur én gang, første gang du gjør et trekk mens du er i lufta
local flightCounted = false
local moveContext = { onTaxi = false, newFlight = false }

function ns.GetMoveContext()
    local onTaxi = UnitOnTaxi("player") and true or false
    local newFlight = false
    if onTaxi and not flightCounted then
        flightCounted = true
        newFlight = true
    elseif not onTaxi then
        flightCounted = false
    end
    moveContext.onTaxi, moveContext.newFlight = onTaxi, newFlight
    return moveContext
end

function ns.NewBoard()
    ns.board = Core.NewBoard(ns.NewSeed())
    local report = Progression.RecordNewBoard(ns.db.profile)
    ns.UI.OnBoardReplaced()
    ns.UI.ShowReport(report)
end

function ns.ResetProgress()
    ns.db.profile = Progression.NewProfile()
    ns.board = Core.NewBoard(ns.NewSeed())
    ns.UI.OnBoardReplaced()
    ns.Print("All progress has been reset.")
end

StaticPopupDialogs["GEMFLIGHT_RESET_PROGRESS"] = {
    text = "Reset all GemFlight progress?\nYour level, XP, stats and achievements will be lost.",
    button1 = "Reset",
    button2 = CANCEL,
    OnAccept = function() ns.ResetProgress() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function PrintHelp()
    ns.Print("Commands:")
    ns.Print("/gemflight - open or close the board")
    ns.Print("/gemflight minimap - show or hide the minimap button")
    ns.Print("/gemflight scale <0.5-2> - window size")
    ns.Print("/gemflight sound - turn sound on or off")
    ns.Print("/gemflight reset - erase all progress")
end

SLASH_GEMFLIGHT1 = "/gemflight"
SLASH_GEMFLIGHT2 = "/gf"
SlashCmdList.GEMFLIGHT = function(msg)
    local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    if cmd == "" then
        ns.UI.Toggle()
    elseif cmd == "minimap" then
        if ns.MinimapButton.Toggle() then
            ns.Print("Minimap button shown.")
        else
            ns.Print("Minimap button hidden. Type /gemflight minimap to bring it back.")
        end
    elseif cmd == "scale" then
        local n = tonumber(arg)
        if n and n >= 0.5 and n <= 2 then
            ns.UI.SetScale(n)
            ns.Print(("Window scale set to %.2f."):format(n))
        else
            ns.Print(("Usage: /gemflight scale 0.5-2 (now %.2f)"):format(ns.db.window.scale))
        end
    elseif cmd == "sound" then
        ns.db.sound = not ns.db.sound
        ns.Print(ns.db.sound and "Sound on." or "Sound off.")
    elseif cmd == "reset" then
        StaticPopup_Show("GEMFLIGHT_RESET_PROGRESS")
    else
        PrintHelp()
    end
end

-- Addon compartment (addon-menyen ved minimap), satt opp i TOC-filen
function GemFlight_OnAddonCompartmentClick()
    ns.UI.Toggle()
end

function GemFlight_OnAddonCompartmentEnter(_, menuButton)
    ns.MinimapButton.ShowTooltip(menuButton)
end

function GemFlight_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGOUT")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("READY_CHECK")
events:RegisterEvent("PLAYER_CONTROL_GAINED")
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        self:UnregisterEvent("ADDON_LOADED")
        InitDB()
        ns.UI.Create()
        ns.MinimapButton.Create()
    elseif event == "PLAYER_LOGOUT" then
        if ns.db and ns.board then
            ns.db.board = Core.Serialize(ns.board)
        end
    elseif event == "PLAYER_REGEN_DISABLED" or event == "READY_CHECK" then
        ns.UI.Hide()
    elseif event == "PLAYER_CONTROL_GAINED" then
        -- Også etter stun/fear, så sjekk at vi faktisk har landet
        if not UnitOnTaxi("player") then flightCounted = false end
    end
end)
