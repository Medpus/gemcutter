-- Røyktest for WoW-laget: laster addonet som WoW gjør, mot en streng API-mock,
-- og spiller hundrevis av trekk med ekte musehendelser og animasjonstikk.
-- Kjør fra repo-roten: luajit tests/ui_smoke.lua

local ADDON = "Gemcutter"
local passed, failed = 0, 0
local require_frames

local function check(cond, msg)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        io.stderr:write("FAIL: " .. msg .. "\n")
    end
end

local function tocFiles()
    local files = {}
    for line in io.lines(ADDON .. "/" .. ADDON .. ".toc") do
        if line:match("%.lua%s*$") then files[#files + 1] = line:match("^%s*(.-)%s*$") end
    end
    return files
end

local function bootstrap(savedDB)
    package.loaded["tests.wow_mock"] = nil
    setmetatable(_G, nil)
    for k in pairs(require("tests.wow_mock").allowedGlobals) do rawset(_G, k, nil) end
    local M = dofile("tests/wow_mock.lua")
    M.Install()
    rawset(_G, "GemcutterDB", savedDB)
    M.Lockdown()
    local ns = {}
    for _, file in ipairs(tocFiles()) do
        local chunk = assert(loadfile(ADDON .. "/" .. file))
        chunk(ADDON, ns)
    end
    M.Fire("ADDON_LOADED", ADDON)
    return M, ns
end

local function findFrame(M, pred)
    for _, f in ipairs(M.frames) do
        if pred(f) then return f end
    end
end

local function settle(M, board)
    for _ = 1, 400 do
        if not (board._scripts and board._scripts.OnUpdate) then return true end
        M.Tick(0.05)
    end
    return false
end

-- Sjekker at de synlige steinrammene står nøyaktig på de 64 rutene og viser riktig ikon
local function boardMatchesState(board, ns)
    local CELL = 36
    local byPos = {}
    local count = 0
    for _, f in ipairs(require_frames) do
        if f._parent == board and f._shown and f.icon then
            count = count + 1
            local _, _, _, x, y = f:GetPoint()
            local c = math.floor(x / CELL + 0.5) + 1
            local r = math.floor(-y / CELL + 0.5) + 1
            local key = r * 100 + c
            if byPos[key] then return false, "two gems at " .. r .. "," .. c end
            if math.abs(x - (c - 1) * CELL) > 0.01 or math.abs(-y - (r - 1) * CELL) > 0.01 then
                return false, "gem off-grid at " .. x .. "," .. y
            end
            if (f._alpha or 1) < 0.99 then return false, "gem not fully visible at " .. r .. "," .. c end
            byPos[key] = f
        end
    end
    if count ~= 64 then return false, "expected 64 visible gems, got " .. count end
    for r = 1, 8 do
        for c = 1, 8 do
            local gem = ns.board.cells[r][c]
            local f = byPos[r * 100 + c]
            if not f then return false, "missing gem at " .. r .. "," .. c end
            local tex = f.icon._texture
            if gem.special == "prism" then
                if not tex:find("Prismatic") then return false, "prism shows wrong icon" end
            elseif tex:find("Prismatic") then
                return false, "plain gem shows prism icon"
            end
            if f.lineH._shown ~= (gem.special == "lineH") then return false, "lineH overlay mismatch" end
            if f.lineV._shown ~= (gem.special == "lineV") then return false, "lineV overlay mismatch" end
        end
    end
    return true
end

local function cellCenter(r, c)
    return (c - 0.5) * 36, -(r - 0.5) * 36
end

local function mouse(M, board, kind, r, c)
    local x, y = cellCenter(r, c)
    M.cursorX, M.cursorY = board._left + x, board._top + y
    board._scripts[kind](board, "LeftButton")
end

------------------------------------------------------------------------
-- Første økt
------------------------------------------------------------------------

local M, ns = bootstrap(nil)
require_frames = M.frames

check(type(GemcutterDB) == "table", "GemcutterDB created")
check(ns.board and ns.db and ns.db.profile.level == 1, "board and profile initialised")
local frame = GemcutterFrame
check(frame ~= nil and not frame._shown, "main frame exists and starts hidden")
check(UISpecialFrames[1] == "GemcutterFrame", "Escape closes the frame")

SlashCmdList.GEMCUTTER("")
check(frame._shown, "slash command opens the frame")

local board = findFrame(M, function(f) return f._clips end)
check(board ~= nil, "board frame found")
board._left, board._top = 0, 0

local ok, err = boardMatchesState(board, ns)
check(ok, "initial board drawn: " .. tostring(err))

local Core = ns.Core
local moves, invalids, combatHides = 0, 0, 0
local seed = 7
local function rand(n)
    seed = (seed * 16807) % 2147483647
    return seed % n + 1
end

for i = 1, 400 do
    local r1, c1, r2, c2 = Core.FindHint(ns.board)
    if i % 13 == 0 then
        -- ugyldig trekk: to naboer uten match (finn et par som ikke gir match)
        for r = 1, 8 do
            for c = 1, 7 do
                local a, b = ns.board.cells[r][c], ns.board.cells[r][c + 1]
                if not a.special and not b.special then
                    local copy = Core.Deserialize(Core.Serialize(ns.board))
                    if not Core.TrySwap(copy, r, c, r, c + 1).valid then
                        r1, c1, r2, c2 = r, c, r, c + 1
                        invalids = invalids + 1
                        goto found
                    end
                end
            end
        end
        ::found::
    end
    local scoreBefore = ns.board.score
    if i % 3 == 0 then
        -- klikk, klikk
        mouse(M, board, "OnMouseDown", r1, c1)
        mouse(M, board, "OnMouseUp", r1, c1)
        mouse(M, board, "OnMouseDown", r2, c2)
        mouse(M, board, "OnMouseUp", r2, c2)
    else
        -- dra
        mouse(M, board, "OnMouseDown", r1, c1)
        mouse(M, board, "OnMouseUp", r2, c2)
    end
    if i % 17 == 0 then
        -- kamp midt i animasjonen skjuler vinduet, så åpnes det igjen
        M.Tick(0.05)
        M.Fire("PLAYER_REGEN_DISABLED")
        check(not frame._shown, "combat hides the frame")
        combatHides = combatHides + 1
        M.Tick(0.05)
        SlashCmdList.GEMCUTTER("")
    end
    check(settle(M, board), "animation finishes (move " .. i .. ")")
    M.FinishAnimations()
    if i % 5 == 0 then M.RunTimers() end
    if ns.board.score > scoreBefore then moves = moves + 1 end
    ok, err = boardMatchesState(board, ns)
    if not ok then
        check(false, "board drawn correctly after move " .. i .. ": " .. err)
        break
    end
end
-- Dra som følger musen: gem + nabo flytter seg med pekeren, maks én rute
do
    local function cursorAt(lx, ly)
        M.cursorX, M.cursorY = board._left + lx, board._top - ly
    end
    local function gemAt(r, c)
        for _, f in ipairs(M.frames) do
            if f._parent == board and f._shown and f.icon then
                local _, _, _, x, y = f:GetPoint()
                if math.abs(x - (c - 1) * 36) < 0.01 and math.abs(-y - (r - 1) * 36) < 0.01 then return f end
            end
        end
    end
    local function offsetOf(f, r, c)
        local _, _, _, x, y = f:GetPoint()
        return x - (c - 1) * 36, -y - (r - 1) * 36
    end

    local hr1, hc1, hr2, hc2 = Core.FindHint(ns.board)
    local dr, dc = hr2 - hr1, hc2 - hc1
    local sx, sy = (hc1 - 0.5) * 36, (hr1 - 0.5) * 36
    local ga, gb = gemAt(hr1, hc1), gemAt(hr2, hc2)
    check(ga ~= nil and gb ~= nil, "drag test finds both gem frames")

    -- Under 4 px er fortsatt et klikk: ingenting flytter seg
    M.mouseDown = true
    cursorAt(sx, sy)
    board._scripts.OnMouseDown(board, "LeftButton")
    cursorAt(sx + dc * 3, sy + dr * 3)
    M.Tick(0.016)
    local ox, oy = offsetOf(ga, hr1, hc1)
    check(ox == 0 and oy == 0, "movement under 4 px does not drag")

    -- Gem følger pekeren, naboen går motsatt vei
    cursorAt(sx + dc * 10, sy + dr * 10)
    M.Tick(0.016)
    ox, oy = offsetOf(ga, hr1, hc1)
    check(math.abs(ox - dc * 10) < 0.01 and math.abs(oy - dr * 10) < 0.01, "dragged gem follows the cursor")
    ox, oy = offsetOf(gb, hr2, hc2)
    check(math.abs(ox + dc * 10) < 0.01 and math.abs(oy + dr * 10) < 0.01, "neighbour moves the opposite way")

    -- Aldri mer enn én rute, også når pekeren går langt forbi
    cursorAt(sx + dc * 90, sy + dr * 90)
    M.Tick(0.016)
    ox, oy = offsetOf(ga, hr1, hc1)
    check(math.abs(ox - dc * 36) < 0.01 and math.abs(oy - dr * 36) < 0.01, "drag is clamped to one cell")

    -- Slipper under terskelen: ingenting skjer, gem fjærer tilbake
    local movesBefore, scoreBefore2 = ns.board.moves, ns.board.score
    cursorAt(sx + dc * 8, sy + dr * 8)
    M.Tick(0.016)
    M.mouseDown = false
    board._scripts.OnMouseUp(board, "LeftButton")
    check(settle(M, board), "spring-back finishes")
    M.FinishAnimations()
    check(ns.board.moves == movesBefore and ns.board.score == scoreBefore2, "release under threshold changes nothing")
    ox, oy = offsetOf(ga, hr1, hc1)
    check(ox == 0 and oy == 0, "gem is back in place after spring-back")
    ok, err = boardMatchesState(board, ns)
    check(ok, "board intact after spring-back: " .. tostring(err))

    -- Slipper forbi terskelen utenfor brettet: byttet gjennomføres
    M.mouseDown = true
    cursorAt(sx, sy)
    board._scripts.OnMouseDown(board, "LeftButton")
    cursorAt(sx + dc * 20, sy + dr * 20)
    M.Tick(0.016)
    ox, oy = offsetOf(ga, hr1, hc1)
    check(math.abs(ox - dc * 20) < 0.01 and math.abs(oy - dr * 20) < 0.01, "second drag follows the cursor")
    M.mouseDown = false
    M.Tick(0.016)
    check(ns.board.moves == movesBefore + 1, "release past threshold commits the swap")
    check(settle(M, board), "committed drag finishes")
    M.FinishAnimations()
    ok, err = boardMatchesState(board, ns)
    check(ok, "board correct after drag commit: " .. tostring(err))
end

check(moves > 300, "most moves scored (" .. moves .. ")")
check(invalids > 10, "invalid swaps exercised (" .. invalids .. ")")
check(combatHides > 10, "combat hide exercised")
check(ns.db.profile.stats.moves == ns.board.moves, "profile counted every move")
check(ns.db.profile.level > 1, "player levelled up (level " .. ns.db.profile.level .. ")")
local levelMsgs = 0
for _, msg in ipairs(M.chat) do if msg:find("You reached level") then levelMsgs = levelMsgs + 1 end end
check(levelMsgs > 0, "level-up announced in chat")

-- Flytur telles én gang per flytur
M.onTaxi = true
local flightsBefore = ns.db.profile.stats.flights
for _ = 1, 3 do
    local r1, c1, r2, c2 = Core.FindHint(ns.board)
    mouse(M, board, "OnMouseDown", r1, c1)
    mouse(M, board, "OnMouseUp", r2, c2)
    settle(M, board)
end
check(ns.db.profile.stats.flights == flightsBefore + 1, "one flight counted for several moves in the air")
M.onTaxi = false
M.Fire("PLAYER_CONTROL_GAINED")
M.onTaxi = true
local r1, c1, r2, c2 = Core.FindHint(ns.board)
mouse(M, board, "OnMouseDown", r1, c1)
mouse(M, board, "OnMouseUp", r2, c2)
settle(M, board)
check(ns.db.profile.stats.flights == flightsBefore + 2, "new flight counted after landing")
M.onTaxi = false

-- Fremdriftspanel
local progressButton = findFrame(M, function(f) return f._text == "Progress" end)
check(progressButton ~= nil, "progress button found")
progressButton._scripts.OnClick(progressButton)
check(not board._parent._shown, "board hidden while progress panel shows")
check(progressButton._text == "Back to board", "progress button label changes")
progressButton._scripts.OnClick(progressButton)
check(board._parent._shown, "board back after closing progress panel")

-- Nytt brett
local newButton = findFrame(M, function(f) return f._text == "New board" end)
newButton._scripts.OnClick(newButton)
check(M.popups[#M.popups] == "GEMCUTTER_NEW_BOARD", "new board asks for confirmation")
StaticPopupDialogs.GEMCUTTER_NEW_BOARD.OnAccept()
check(ns.board.moves == 0 and ns.board.score == 0, "fresh board after confirm")
check(ns.db.profile.stats.boards == 1, "boards stat counted")
ok, err = boardMatchesState(board, ns)
check(ok, "new board drawn: " .. tostring(err))

-- Nytt brett midt i en animasjon
r1, c1, r2, c2 = Core.FindHint(ns.board)
mouse(M, board, "OnMouseDown", r1, c1)
mouse(M, board, "OnMouseUp", r2, c2)
M.Tick(0.05)
ns.NewBoard()
check(settle(M, board), "no animation left after board replaced")
ok, err = boardMatchesState(board, ns)
check(ok, "board correct after replacing mid-animation: " .. tostring(err))

-- Minimapknapp
local mm = GemcutterMinimapButton
check(mm ~= nil and mm._shown, "minimap button shown")
mm._scripts.OnClick(mm, "LeftButton")
check(not frame._shown, "minimap click closes the board")
mm._scripts.OnClick(mm, "LeftButton")
check(frame._shown, "minimap click opens the board")
M.cursorX, M.cursorY = 1000, 900
mm._scripts.OnDragStart(mm)
M.Tick(0.05)
mm._scripts.OnDragStop(mm)
check(math.abs(ns.db.minimap.angle - 90) < 0.01, "dragging stores minimap angle (" .. ns.db.minimap.angle .. ")")
SlashCmdList.GEMCUTTER("minimap")
check(not mm._shown and ns.db.minimap.hide, "slash command hides minimap button")
SlashCmdList.GEMCUTTER("minimap")
check(mm._shown, "slash command shows minimap button again")

-- Flytte vinduet lagrer posisjonen i DB
frame._scripts.OnDragStart(frame, "LeftButton")
frame:ClearAllPoints()
frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -60)
frame._scripts.OnDragStop(frame)
check(ns.db.window.point == "TOPLEFT" and ns.db.window.x == 40 and ns.db.window.y == -60, "window position saved")

-- Andre slash-kommandoer
SlashCmdList.GEMCUTTER("scale 1.25")
check(ns.db.window.scale == 1.25, "scale stored")
SlashCmdList.GEMCUTTER("scale 9")
check(ns.db.window.scale == 1.25, "invalid scale ignored")
SlashCmdList.GEMCUTTER("sound")
check(ns.db.sound == false, "sound toggled off")
local soundsBefore = M.sounds
r1, c1, r2, c2 = Core.FindHint(ns.board)
mouse(M, board, "OnMouseDown", r1, c1)
mouse(M, board, "OnMouseUp", r2, c2)
settle(M, board)
check(M.sounds == soundsBefore, "no sound while muted")
SlashCmdList.GEMCUTTER("sound")
SlashCmdList.GEMCUTTER("help")

-- Addon-kompartement
Gemcutter_OnAddonCompartmentClick()
check(not frame._shown, "compartment click toggles the board")
Gemcutter_OnAddonCompartmentEnter(ADDON, mm)
Gemcutter_OnAddonCompartmentLeave()

-- Lagring ved utlogging
local savedProfile = ns.db.profile
local levelBefore = savedProfile.level
M.Fire("PLAYER_LOGOUT")
check(type(GemcutterDB.board) == "table", "board saved at logout")
local savedBoard = Core.Serialize(ns.board)

------------------------------------------------------------------------
-- Ny økt med lagrede data
------------------------------------------------------------------------

local saved = GemcutterDB
local M2, ns2 = bootstrap(saved)
require_frames = M2.frames
check(ns2.db.profile.level == levelBefore, "level survives reload")
local reloaded = Core.Serialize(ns2.board)
local same = reloaded.score == savedBoard.score and reloaded.moves == savedBoard.moves and reloaded.nextId == savedBoard.nextId
check(same, "board survives reload")

-- Ødelagte lagrede data gir nytt brett, ikke feil
local M3, ns3 = bootstrap({ board = { v = 1, cells = "garbage" }, profile = { level = "x", stats = 5 }, minimap = 3, window = {} })
check(ns3.board ~= nil and ns3.db.profile.level == 1, "corrupt saved data recovers")

-- Nullstilling
SlashCmdList.GEMCUTTER("reset")
StaticPopupDialogs.GEMCUTTER_RESET_PROGRESS.OnAccept()
check(ns3.db.profile.level == 1 and ns3.db.profile.totalXP == 0, "reset clears progress")

print(("ui_smoke: %d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
