local addonName, ns = ...
local Core, Progression = ns.Core, ns.Progression

local UI = {}
ns.UI = UI

local SIZE = 8
local CELL = 36
local GEM = 32
local BOARD_PX = CELL * SIZE
local PAD = 18
local BOARD_TOP = 80
local FRAME_W = BOARD_PX + PAD * 2
local FRAME_H = BOARD_TOP + BOARD_PX + 48
local HINT_DELAY = 8

-- Vanilla-ikoner med tydelig forskjellig farge og form
local GEM_ICONS = {
    "Interface\\Icons\\INV_Misc_Gem_Ruby_03",     -- rød
    "Interface\\Icons\\INV_Misc_Gem_Opal_01",     -- oransje
    "Interface\\Icons\\INV_Misc_Gem_Topaz_02",    -- gul
    "Interface\\Icons\\INV_Misc_Gem_Emerald_01",  -- grønn
    "Interface\\Icons\\INV_Misc_Gem_Sapphire_02", -- blå
    "Interface\\Icons\\INV_Misc_Gem_Amethyst_01", -- lilla
    "Interface\\Icons\\INV_Misc_Gem_Diamond_02",  -- hvit
}
local PRISM_ICON = "Interface\\Icons\\INV_Enchant_ShardPrismaticLarge"
local XP_COLOR = { 0.58, 0.0, 0.55 }
-- Gnistfarger per steinfarge (indeks = Core-farge), prismet får egen
local GEM_COLORS = {
    { 1, 0.25, 0.25 }, { 1, 0.6, 0.15 }, { 1, 0.9, 0.25 }, { 0.3, 1, 0.4 },
    { 0.35, 0.6, 1 }, { 0.75, 0.45, 1 }, { 1, 1, 1 },
}
local PRISM_COLOR = { 0.8, 0.9, 1 }

local SWAP_TIME = 0.16
local SWAP_GROW = 0.1
local COMMIT = 0.35
local CLICK_PX = 4
local SEL_SCALE = 1.1
local SHAKE_TIME = 0.15
local SCORE_TIME = 0.35
local BAR_TIME = 0.6

local SOUNDS = {
    select = { "IG_MAINMENU_OPTION_CHECKBOX_ON" },
    invalid = { "IG_MAINMENU_OPTION_CHECKBOX_OFF" },
    clear = { "U_CHAT_SCROLL_BUTTON" },
    chain = { "LOOT_WINDOW_COIN_SOUND", "U_CHAT_SCROLL_BUTTON" },
    shuffle = { "IG_ABILITY_PAGE_TURN" },
    levelup = { "LFG_REWARDS", "IG_QUEST_LIST_COMPLETE" },
    achievement = { "IG_QUEST_LIST_COMPLETE" },
    open = { "IG_CHARACTER_INFO_OPEN" },
    close = { "IG_CHARACTER_INFO_CLOSE" },
}

local Fmt = BreakUpLargeNumbers or tostring

local frame, board, overlay, progressPanel
local hud = {}
local gemFrames, gemPool = {}, {}
local busy = false
local selR, selC
local hintTimer
local hintFrames = {}
local scoreTarget, scoreShown, scoreFrom, scoreT, scoreActive = 0, 0, 0, 0, false
local shownText
local barLevel, barValue, barTargetLevel, barTargetXP, barActive
local hoverGem, tracker, trackerOn, hovering
local downR, downC, downX, downY
local dragging, dragAmt, dragNR, dragNC, dragGa, dragGb

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Gemcutter:|r " .. msg)
end

local function PlaySFX(name)
    if not ns.db.sound or not SOUNDKIT then return end
    local keys = SOUNDS[name]
    for i = 1, #keys do
        local id = SOUNDKIT[keys[i]]
        if id then
            PlaySound(id, "SFX")
            return
        end
    end
end

local function EaseOut(k) return 1 - (1 - k) * (1 - k) end
local function EaseIn(k) return k * k end
local function EaseInOut(k)
    if k < 0.5 then return 2 * k * k end
    return 1 - 2 * (1 - k) * (1 - k)
end

-- Lange kjeder går fortere: 10 % kortere per kjedetrinn fra kjede 3, ned til 70 %
local function Pace(chain)
    if chain < 3 then return 1 end
    return math.max(0.7, 1 - 0.1 * (chain - 2))
end

----------------------------------------------------------------------
-- Animasjonskø: faser kjøres etter hverandre i én OnUpdate på brettet
----------------------------------------------------------------------

local phases = {}
local phaseIndex, phaseTime = 1, 0
local onPhasesDone

local function AddPhase(duration, start, update, finish)
    phases[#phases + 1] = { duration = duration, start = start, update = update, finish = finish }
end

local function PhaseOnUpdate(self, elapsed)
    while true do
        local p = phases[phaseIndex]
        if not p then break end
        if not p.started then
            p.started = true
            phaseTime = 0
            if p.start then p.start() end
        end
        phaseTime = phaseTime + elapsed
        elapsed = 0
        local k = p.duration > 0 and math.min(1, phaseTime / p.duration) or 1
        if p.update then p.update(k) end
        if k < 1 then return end
        if p.finish then p.finish() end
        phaseIndex = phaseIndex + 1
    end
    wipe(phases)
    phaseIndex = 1
    self:SetScript("OnUpdate", nil)
    busy = false
    local done = onPhasesDone
    onPhasesDone = nil
    if done then done() end
end

local function RunPhases(done)
    busy = true
    if hoverGem then
        hoverGem.hover:Hide()
        hoverGem = nil
    end
    onPhasesDone = done
    phaseIndex = 1
    board:SetScript("OnUpdate", PhaseOnUpdate)
end

local function StopPhases()
    wipe(phases)
    phaseIndex = 1
    onPhasesDone = nil
    board:SetScript("OnUpdate", nil)
    busy = false
end

----------------------------------------------------------------------
-- Steiner
----------------------------------------------------------------------

local function PlaceGem(g, r, c)
    g.r, g.c = r, c
    g:ClearAllPoints()
    g:SetPoint("TOPLEFT", board, "TOPLEFT", (c - 1) * CELL, -(r - 1) * CELL)
end

local function CreateGemFrame()
    local g = CreateFrame("Frame", nil, board)
    g:SetSize(CELL, CELL)
    g.baseLevel = g:GetFrameLevel()

    g.icon = g:CreateTexture(nil, "ARTWORK")
    g.icon:SetPoint("CENTER")
    g.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Effektlaget pulserer for spesialsteiner
    g.fx = CreateFrame("Frame", nil, g)
    g.fx:SetAllPoints()
    g.glow = g.fx:CreateTexture(nil, "OVERLAY")
    g.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    g.glow:SetBlendMode("ADD")
    g.glow:SetSize(CELL * 1.8, CELL * 1.8)
    g.glow:SetPoint("CENTER")
    g.lineV = g.fx:CreateTexture(nil, "OVERLAY")
    g.lineV:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    g.lineV:SetBlendMode("ADD")
    g.lineV:SetSize(14, GEM + 6)
    g.lineV:SetPoint("CENTER")
    g.lineH = g.fx:CreateTexture(nil, "OVERLAY")
    g.lineH:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    g.lineH:SetBlendMode("ADD")
    -- Roter gnisten 90 grader via teksturkoordinatene
    g.lineH:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0)
    g.lineH:SetSize(GEM + 6, 14)
    g.lineH:SetPoint("CENTER")
    g.pulse = g.fx:CreateAnimationGroup()
    g.pulse:SetLooping("BOUNCE")
    local a = g.pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.35)
    a:SetDuration(0.7)

    g.sel = g:CreateTexture(nil, "OVERLAY")
    g.sel:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    g.sel:SetBlendMode("ADD")
    g.sel:SetVertexColor(1, 0.82, 0)
    g.sel:SetSize(GEM + 2, GEM + 2)
    g.sel:SetPoint("CENTER")
    g.sel:Hide()
    g.selPulse = g.sel:CreateAnimationGroup()
    g.selPulse:SetLooping("BOUNCE")
    local sp = g.selPulse:CreateAnimation("Alpha")
    sp:SetFromAlpha(1)
    sp:SetToAlpha(0.4)
    sp:SetDuration(0.6)

    g.hover = g:CreateTexture(nil, "OVERLAY")
    g.hover:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    g.hover:SetBlendMode("ADD")
    g.hover:SetAlpha(0.45)
    g.hover:SetSize(GEM + 2, GEM + 2)
    g.hover:SetPoint("CENTER")
    g.hover:Hide()

    g.flash = g:CreateTexture(nil, "OVERLAY")
    g.flash:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    g.flash:SetBlendMode("ADD")
    g.flash:SetVertexColor(1, 1, 1)
    g.flash:SetSize(GEM + 4, GEM + 4)
    g.flash:SetPoint("CENTER")
    g.flash:Hide()

    g.hint = g:CreateTexture(nil, "OVERLAY")
    g.hint:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    g.hint:SetBlendMode("ADD")
    g.hint:SetSize(GEM + 2, GEM + 2)
    g.hint:SetPoint("CENTER")
    g.hint:Hide()
    g.hintPulse = g.hint:CreateAnimationGroup()
    g.hintPulse:SetLooping("BOUNCE")
    local h = g.hintPulse:CreateAnimation("Alpha")
    h:SetFromAlpha(0.15)
    h:SetToAlpha(0.9)
    h:SetDuration(0.6)
    return g
end

local function AcquireGem()
    local g = table.remove(gemPool) or CreateGemFrame()
    g:SetAlpha(1)
    g.icon:SetSize(GEM, GEM)
    g:SetFrameLevel(g.baseLevel)
    g:Show()
    return g
end

local function ReleaseGem(g)
    g:Hide()
    g.pulse:Stop()
    g.hintPulse:Stop()
    g.selPulse:Stop()
    g.sel:Hide()
    g.hint:Hide()
    g.hover:Hide()
    g.flash:Hide()
    if hoverGem == g then hoverGem = nil end
    gemPool[#gemPool + 1] = g
end

local function StyleGem(g, gem)
    local special = gem.special
    if special == "prism" then
        g.icon:SetTexture(PRISM_ICON)
    else
        g.icon:SetTexture(GEM_ICONS[gem.color] or GEM_ICONS[1])
    end
    g.glow:SetShown(special == "volatile" or special == "prism")
    if special == "volatile" then
        g.glow:SetVertexColor(1, 0.45, 0.1)
    elseif special == "prism" then
        g.glow:SetVertexColor(0.8, 0.9, 1)
    end
    g.lineH:SetShown(special == "lineH")
    g.lineV:SetShown(special == "lineV")
    if special then
        if not g.pulse:IsPlaying() then g.pulse:Play() end
    else
        g.pulse:Stop()
    end
end

-- Får rammene til å stemme nøyaktig med brettet, uansett hva animasjonene gjorde
local seen = {}
local function SyncBoard()
    wipe(seen)
    local cells = ns.board.cells
    for r = 1, SIZE do
        for c = 1, SIZE do
            local gem = cells[r][c]
            local g = gemFrames[gem.id]
            if not g then
                g = AcquireGem()
                gemFrames[gem.id] = g
            end
            StyleGem(g, gem)
            g:SetAlpha(1)
            local size = (selR == r and selC == c) and GEM * SEL_SCALE or GEM
            g.icon:SetSize(size, size)
            if g:GetFrameLevel() ~= g.baseLevel then g:SetFrameLevel(g.baseLevel) end
            g.flash:Hide()
            PlaceGem(g, r, c)
            seen[gem.id] = true
        end
    end
    for id, g in pairs(gemFrames) do
        if not seen[id] then
            ReleaseGem(g)
            gemFrames[id] = nil
        end
    end
end

----------------------------------------------------------------------
-- Tilbakemelding: poeng, kjede, nivå og achievements
----------------------------------------------------------------------

local popupPool = {}

local function ShowPopup(text, r, c, large, chain)
    local p = table.remove(popupPool)
    if not p then
        p = CreateFrame("Frame", nil, overlay)
        p:SetSize(160, 30)
        p.text = p:CreateFontString(nil, "OVERLAY")
        p.text:SetPoint("CENTER")
        p.anim = p:CreateAnimationGroup()
        local move = p.anim:CreateAnimation("Translation")
        move:SetOffset(0, 22)
        move:SetDuration(0.9)
        local fade = p.anim:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0)
        fade:SetStartDelay(0.45)
        fade:SetDuration(0.45)
        p.anim:SetScript("OnFinished", function()
            p:Hide()
            popupPool[#popupPool + 1] = p
        end)
    end
    p.text:SetFontObject(large and GameFontNormalLarge or GameFontHighlight)
    p.text:SetText(text)
    if chain and chain >= 3 then
        p.text:SetTextColor(1, 0.5, 0.1)
    elseif chain == 2 then
        p.text:SetTextColor(1, 0.82, 0)
    else
        p.text:SetTextColor(1, 1, 1)
    end
    p:ClearAllPoints()
    p:SetPoint("CENTER", overlay, "TOPLEFT", (c - 0.5) * CELL, -(r - 0.5) * CELL)
    p:Show()
    p.anim:Stop()
    p.anim:Play()
end

local function CreateBanner()
    local b = CreateFrame("Frame", nil, overlay, "BackdropTemplate")
    b:SetSize(BOARD_PX - 40, 72)
    b:SetPoint("CENTER")
    b:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    b:SetBackdropColor(0, 0, 0, 0.85)
    b:SetBackdropBorderColor(1, 0.82, 0, 0.9)
    b.title = b:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    b.title:SetPoint("TOP", 0, -14)
    b.sub = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.sub:SetPoint("TOP", b.title, "BOTTOM", 0, -6)
    b.anim = b:CreateAnimationGroup()
    local fadeIn = b.anim:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.15)
    fadeIn:SetOrder(1)
    local fadeOut = b.anim:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetStartDelay(2)
    fadeOut:SetDuration(0.4)
    fadeOut:SetOrder(2)
    b.anim:SetScript("OnFinished", function() b:Hide() end)
    b:Hide()
    return b
end

local levelBanner

local function ShowLevelBanner(level, newRank)
    levelBanner.title:SetText("Level " .. level)
    levelBanner.sub:SetText(newRank and ("New rank: " .. Progression.Rank(level)) or Progression.Rank(level))
    levelBanner:Show()
    levelBanner.anim:Stop()
    levelBanner.anim:Play()
end

local toast
local toastQueue = {}

local function ShowNextToast()
    local def = table.remove(toastQueue, 1)
    if not def then return end
    toast.text:SetText(def.xp > 0 and ("%s  |cffffffff+%s XP|r"):format(def.name, Fmt(def.xp)) or def.name)
    toast:Show()
    toast.anim:Stop()
    toast.anim:Play()
    PlaySFX("achievement")
end

local function QueueToast(def)
    toastQueue[#toastQueue + 1] = def
    if not toast:IsShown() then ShowNextToast() end
end

local function CreateToast()
    local t = CreateFrame("Frame", nil, overlay, "BackdropTemplate")
    t:SetSize(BOARD_PX - 24, 40)
    t:SetPoint("TOP", 0, -10)
    t:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    t:SetBackdropColor(0.05, 0.04, 0.02, 0.92)
    t:SetBackdropBorderColor(1, 0.82, 0, 0.8)
    t.label = t:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    t.label:SetPoint("TOP", 0, -6)
    t.label:SetText("Achievement earned")
    t.text = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t.text:SetPoint("TOP", t.label, "BOTTOM", 0, -2)
    t.anim = t:CreateAnimationGroup()
    local fadeIn = t.anim:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.2)
    fadeIn:SetOrder(1)
    local fadeOut = t.anim:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetStartDelay(2.2)
    fadeOut:SetDuration(0.4)
    fadeOut:SetOrder(2)
    t.anim:SetScript("OnFinished", function()
        t:Hide()
        ShowNextToast()
    end)
    t:Hide()
    return t
end

local StartFx

local function ShowScore()
    local v = math.floor(scoreShown + 0.5)
    if v ~= shownText then
        shownText = v
        hud.score:SetText(Fmt(v))
    end
end

-- snap = true setter tallet rett på, ellers telles det opp
local function SetScore(v, snap)
    scoreTarget = v
    if snap or not overlay or not overlay:IsVisible() then
        scoreShown, scoreActive = v, false
        ShowScore()
    elseif v ~= scoreShown then
        scoreFrom, scoreT, scoreActive = scoreShown, 0, true
        StartFx()
    end
end

local function DrawBar(level, value)
    if level >= Progression.MAX_LEVEL then
        hud.xpBar:SetMinMaxValues(0, 1)
        hud.xpBar:SetValue(1)
    else
        hud.xpBar:SetMinMaxValues(0, Progression.XPToNext(level))
        hud.xpBar:SetValue(value)
    end
end

local function UpdateHUD(smooth)
    local p = ns.db.profile
    hud.level:SetText("Level " .. p.level)
    hud.rank:SetText(Progression.Rank(p.level))
    if p.level >= Progression.MAX_LEVEL then
        hud.xpText:SetText("Max level")
    else
        hud.xpText:SetText(("%s / %s XP"):format(Fmt(p.xp), Fmt(Progression.XPToNext(p.level))))
    end
    barTargetLevel, barTargetXP = p.level, p.xp
    if smooth and barLevel and barLevel <= p.level and overlay:IsVisible() then
        barActive = true
        StartFx()
    else
        barLevel, barValue, barActive = p.level, p.xp, false
        DrawBar(p.level, p.xp)
    end
    if not smooth then SetScore(scoreTarget, true) end
end

----------------------------------------------------------------------
-- Effekter: teksturer på overleggsrammen, én OnUpdate mens noe pågår
----------------------------------------------------------------------

local fxPool, fxActive = {}, {}
local fxRunning = false
local shakeT, shaking = 0, false

local function SetBoardOffset(dx, dy)
    board:ClearAllPoints()
    board:SetPoint("TOPLEFT", 1 + dx, -1 + dy)
end

local function FxOnUpdate(self, elapsed)
    for i = #fxActive, 1, -1 do
        local e = fxActive[i]
        e.t = e.t + elapsed
        local k = e.t / e.dur
        if k >= 1 then
            e.tex:Hide()
            table.remove(fxActive, i)
            fxPool[#fxPool + 1] = e
        else
            local ek = EaseOut(k)
            e.tex:SetSize(e.w0 + (e.w1 - e.w0) * ek, e.h0 + (e.h1 - e.h0) * ek)
            e.tex:SetAlpha(e.a * (1 - k))
            if e.rot ~= 0 then e.tex:SetRotation(e.rot * k) end
        end
    end

    if shaking then
        shakeT = shakeT + elapsed
        if shakeT >= SHAKE_TIME then
            shaking = false
            SetBoardOffset(0, 0)
        else
            local f = 1 - shakeT / SHAKE_TIME
            SetBoardOffset(2 * f * math.sin(shakeT * 110), 2 * f * math.cos(shakeT * 130))
        end
    end

    if scoreActive then
        scoreT = scoreT + elapsed
        local k = math.min(1, scoreT / SCORE_TIME)
        scoreShown = scoreFrom + (scoreTarget - scoreFrom) * EaseOut(k)
        if k >= 1 then
            scoreShown, scoreActive = scoreTarget, false
        end
        ShowScore()
    end

    if barActive then
        if barLevel >= Progression.MAX_LEVEL then
            barActive = false
            DrawBar(barLevel, 0)
        else
            local need = Progression.XPToNext(barLevel)
            local wraps = barLevel < barTargetLevel
            local goal = wraps and need or barTargetXP
            barValue = barValue + need * elapsed / BAR_TIME
            if barValue >= goal then
                if wraps then
                    barLevel, barValue = barLevel + 1, 0
                else
                    barValue, barActive = goal, false
                end
            end
            DrawBar(barLevel, barValue)
        end
    end

    if #fxActive == 0 and not shaking and not scoreActive and not barActive then
        fxRunning = false
        self:SetScript("OnUpdate", nil)
    end
end

function StartFx()
    if fxRunning then return end
    fxRunning = true
    overlay:SetScript("OnUpdate", FxOnUpdate)
end

local function AddFx(path, cr, cg, cb, x, y, w0, h0, w1, h1, dur, alpha, rot)
    local e = table.remove(fxPool)
    if not e then
        e = { tex = overlay:CreateTexture(nil, "OVERLAY") }
        e.tex:SetBlendMode("ADD")
    end
    if path then
        e.tex:SetTexture(path)
        e.tex:SetVertexColor(cr, cg, cb)
    else
        e.tex:SetColorTexture(cr, cg, cb, 1)
        e.tex:SetVertexColor(1, 1, 1)
    end
    e.tex:SetRotation(0)
    e.tex:SetSize(w0, h0)
    e.tex:SetAlpha(alpha)
    e.tex:ClearAllPoints()
    e.tex:SetPoint("CENTER", overlay, "TOPLEFT", x, y)
    e.tex:Show()
    e.t, e.dur, e.a, e.rot = 0, dur, alpha, rot or 0
    e.w0, e.h0, e.w1, e.h1 = w0, h0, w1, h1
    fxActive[#fxActive + 1] = e
    StartFx()
end

local function CellX(c) return (c - 0.5) * CELL end
local function CellY(r) return -(r - 0.5) * CELL end

local function FxSpark(r, c, color)
    local col = GEM_COLORS[color] or PRISM_COLOR
    AddFx("Interface\\Cooldown\\star4", col[1], col[2], col[3], CellX(c), CellY(r),
        8, 8, CELL * 1.3, CELL * 1.3, 0.35, 1, 1.6)
end

local function FxBeam(horizontal, r, c)
    if horizontal then
        AddFx(nil, 1, 0.97, 0.8, BOARD_PX / 2, CellY(r), BOARD_PX, 4, BOARD_PX, 12, 0.3, 1)
        AddFx(nil, 1, 0.85, 0.4, BOARD_PX / 2, CellY(r), BOARD_PX, 10, BOARD_PX, CELL, 0.3, 0.45)
    else
        AddFx(nil, 1, 0.97, 0.8, CellX(c), -BOARD_PX / 2, 4, BOARD_PX, 12, BOARD_PX, 0.3, 1)
        AddFx(nil, 1, 0.85, 0.4, CellX(c), -BOARD_PX / 2, 10, BOARD_PX, CELL, BOARD_PX, 0.3, 0.45)
    end
end

local function FxRing(r, c)
    AddFx("Interface\\Cooldown\\ping4", 1, 0.6, 0.2, CellX(c), CellY(r),
        CELL * 0.6, CELL * 0.6, CELL * 3.4, CELL * 3.4, 0.35, 0.9)
    shakeT, shaking = 0, true
    StartFx()
end

local function FxBoardFlash()
    AddFx(nil, 0.9, 0.95, 1, BOARD_PX / 2, -BOARD_PX / 2, BOARD_PX, BOARD_PX, BOARD_PX, BOARD_PX, 0.25, 0.5)
end

local function StopFx()
    for i = #fxActive, 1, -1 do
        local e = fxActive[i]
        e.tex:Hide()
        fxPool[#fxPool + 1] = e
        fxActive[i] = nil
    end
    if shaking then
        shaking = false
        SetBoardOffset(0, 0)
    end
    scoreActive, barActive, fxRunning = false, false, false
    overlay:SetScript("OnUpdate", nil)
end

function UI.ShowReport(report)
    if not report then return end
    local ups = report.levelUps
    if ups and #ups > 0 then
        local level = ups[#ups]
        local before = level - #ups
        ShowLevelBanner(level, Progression.Rank(level) ~= Progression.Rank(before))
        PlaySFX("levelup")
        ns.Print(("You reached level %d (%s)."):format(level, Progression.Rank(level)))
    end
    if report.achievements then
        for i = 1, #report.achievements do QueueToast(report.achievements[i]) end
    end
    UpdateHUD(true)
end

----------------------------------------------------------------------
-- Hint og markering
----------------------------------------------------------------------

local function HideHint()
    for i = #hintFrames, 1, -1 do
        local g = hintFrames[i]
        g.hintPulse:Stop()
        g.hint:Hide()
        hintFrames[i] = nil
    end
end

local function CancelHint()
    if hintTimer then
        hintTimer:Cancel()
        hintTimer = nil
    end
    HideHint()
end

local function ShowHint()
    hintTimer = nil
    if busy or not frame:IsShown() or progressPanel:IsShown() then return end
    local r1, c1, r2, c2 = Core.FindHint(ns.board)
    if not r1 then return end
    local cells = ns.board.cells
    for _, rc in ipairs({ { r1, c1 }, { r2, c2 } }) do
        local g = gemFrames[cells[rc[1]][rc[2]].id]
        if g then
            g.hint:Show()
            g.hintPulse:Play()
            hintFrames[#hintFrames + 1] = g
        end
    end
end

local function ScheduleHint()
    CancelHint()
    hintTimer = C_Timer.NewTimer(HINT_DELAY, ShowHint)
end

local function ClearSelection()
    if selR then
        local g = gemFrames[ns.board.cells[selR][selC].id]
        if g then
            g.sel:Hide()
            g.selPulse:Stop()
            g.icon:SetSize(GEM, GEM)
        end
    end
    selR, selC = nil, nil
end

local function Select(r, c)
    ClearSelection()
    local g = gemFrames[ns.board.cells[r][c].id]
    if g then
        g.sel:Show()
        g.selPulse:Play()
        g.icon:SetSize(GEM * SEL_SCALE, GEM * SEL_SCALE)
    end
    selR, selC = r, c
    PlaySFX("select")
end

----------------------------------------------------------------------
-- Trekk
----------------------------------------------------------------------

-- Står gem a og b amt (0..1) av veien mellom rute 1 og rute 2
local function PlaceSwapped(ga, gb, r1, c1, r2, c2, amt)
    PlaceGem(ga, r1 + (r2 - r1) * amt, c1 + (c2 - c1) * amt)
    PlaceGem(gb, r2 + (r1 - r2) * amt, c2 + (c1 - c2) * amt)
    local p = math.min(1, math.max(0, amt))
    local size = GEM * (1 + SWAP_GROW * math.sin(math.pi * p))
    ga.icon:SetSize(size, size)
    gb.icon:SetSize(size, size)
end

-- Går fra amt "from" til "to"; wobble gir en dempet svingning rundt målet
local function AddSwapPhase(ga, gb, r1, c1, r2, c2, from, to, duration, ease, wobble)
    AddPhase(duration, nil, function(k)
        local e = from + (to - from) * ease(k)
        if wobble then e = e - wobble * math.sin(k * 2 * math.pi) * (1 - k) end
        PlaceSwapped(ga, gb, r1, c1, r2, c2, e)
    end, function()
        PlaceSwapped(ga, gb, r1, c1, r2, c2, to)
        ga.icon:SetSize(GEM, GEM)
        gb.icon:SetSize(GEM, GEM)
        ga:SetFrameLevel(ga.baseLevel)
        gb:SetFrameLevel(gb.baseLevel)
    end)
end

local function AddClearStep(step, flashBoard)
    local pace = Pace(step.chain)
    local dying, born = {}, {}
    AddPhase(0.22 * pace, function()
        local sumR, sumC = 0, 0
        for i = 1, #step.cleared do
            local cl = step.cleared[i]
            local g = gemFrames[cl.id]
            if g then
                gemFrames[cl.id] = nil
                dying[#dying + 1] = g
                g.flash:SetAlpha(1)
                g.flash:Show()
            end
            FxSpark(cl.r, cl.c, cl.color)
            if cl.special == "prism" then flashBoard = true end
            sumR, sumC = sumR + cl.r, sumC + cl.c
        end
        for i = 1, #step.triggered do
            local tr = step.triggered[i]
            if tr.special == "lineH" then
                FxBeam(true, tr.r, tr.c)
            elseif tr.special == "lineV" then
                FxBeam(false, tr.r, tr.c)
            elseif tr.special == "volatile" then
                FxRing(tr.r, tr.c)
            elseif tr.special == "prism" then
                flashBoard = true
            end
        end
        if flashBoard then FxBoardFlash() end
        for i = 1, #step.created do
            local cr = step.created[i]
            local g = AcquireGem()
            gemFrames[cr.id] = g
            StyleGem(g, cr)
            PlaceGem(g, cr.r, cr.c)
            g:SetAlpha(0)
            born[#born + 1] = g
        end
        SetScore(scoreTarget + step.score)
        local n = #step.cleared
        if n > 0 then ShowPopup("+" .. Fmt(step.score), sumR / n, sumC / n, false, step.chain) end
        if step.chain >= 2 then ShowPopup("Chain x" .. step.chain, 1.2, 4.5, true, step.chain) end
        PlaySFX(step.chain >= 2 and "chain" or "clear")
    end, function(k)
        -- Først et raskt hvitt glimt, så krymper og toner steinen ut
        local kk = math.max(0, (k - 0.25) / 0.75)
        local shrink = GEM * (1 - 0.6 * kk)
        local flash = math.max(0, 1 - k / 0.3)
        for i = 1, #dying do
            local g = dying[i]
            g:SetAlpha(1 - kk)
            g.icon:SetSize(shrink, shrink)
            g.flash:SetAlpha(flash)
        end
        local grow = GEM * (1.5 - 0.5 * EaseOut(k))
        for i = 1, #born do
            born[i]:SetAlpha(k)
            born[i].icon:SetSize(grow, grow)
        end
    end, function()
        for i = 1, #dying do ReleaseGem(dying[i]) end
    end)

    -- Fall: tyngdekraft-ease med liten sprett i landingen. Nye steiner starter forskjøvet.
    local movers = {}
    local bounce = 0.1 * pace
    local total = 0
    local function AddMover(id, from, to, c, delay, spawn)
        local fall = (0.07 + 0.055 * math.sqrt(to - from)) * pace
        movers[#movers + 1] = { id = id, from = from, to = to, c = c, delay = delay * pace, fall = fall, spawn = spawn }
        total = math.max(total, delay * pace + fall + bounce)
    end
    for i = 1, #step.falls do
        local f = step.falls[i]
        AddMover(f.id, f.fromR, f.toR, f.c, 0)
    end
    for i = 1, #step.spawns do
        local sp = step.spawns[i]
        AddMover(sp.id, sp.fromR, sp.r, sp.c, 0.03 * math.max(0, -sp.fromR), sp)
    end
    if #movers == 0 then return end

    AddPhase(total, function()
        for i = 1, #movers do
            local m = movers[i]
            if m.spawn then
                local g = AcquireGem()
                gemFrames[m.id] = g
                StyleGem(g, m.spawn)
                PlaceGem(g, m.from, m.c)
                m.g = g
            else
                m.g = gemFrames[m.id]
            end
        end
    end, function(k)
        local t = k * total
        for i = 1, #movers do
            local m = movers[i]
            local g = m.g
            if g then
                local u = t - m.delay
                local row
                if u <= 0 then
                    row = m.from
                elseif u < m.fall then
                    local q = u / m.fall
                    row = m.from + (m.to - m.from) * q * q
                elseif u < m.fall + bounce then
                    row = m.to - 0.06 * math.sin(math.pi * (u - m.fall) / bounce)
                else
                    row = m.to
                end
                PlaceGem(g, row, m.c)
            end
        end
    end, function()
        for i = 1, #movers do
            local m = movers[i]
            if m.g then PlaceGem(m.g, m.to, m.c) end
        end
    end)
end

local function AddShuffleStep(step)
    local movers = {}
    AddPhase(0.45, function()
        ShowPopup("No moves left. Shuffling.", 4.5, 4.5, true)
        PlaySFX("shuffle")
        for i = 1, #step.moves do
            local mv = step.moves[i]
            local g = gemFrames[mv.id]
            if g then movers[#movers + 1] = { g = g, fr = g.r, fc = g.c, tr = mv.r, tc = mv.c } end
        end
    end, function(k)
        local e = EaseOut(k)
        for i = 1, #movers do
            local m = movers[i]
            PlaceGem(m.g, m.fr + (m.tr - m.fr) * e, m.fc + (m.tc - m.fc) * e)
        end
    end)
end

local function TryMove(r1, c1, r2, c2, startAmt)
    if busy or not Core.AreAdjacent(r1, c1, r2, c2) then return end
    if r2 < 1 or r2 > SIZE or c2 < 1 or c2 > SIZE then return end
    CancelHint()
    ClearSelection()

    local cells = ns.board.cells
    local a, b = cells[r1][c1], cells[r2][c2]
    local ga, gb = gemFrames[a.id], gemFrames[b.id]
    if not ga or not gb then
        SyncBoard()
        return
    end
    local prismMove = a.special == "prism" or b.special == "prism"
    local from = startAmt or 0

    local result = Core.TrySwap(ns.board, r1, c1, r2, c2)
    if not result.valid then
        PlaySFX("invalid")
        AddSwapPhase(ga, gb, r1, c1, r2, c2, from, 0.35, 0.08, EaseOut)
        AddSwapPhase(ga, gb, r1, c1, r2, c2, 0.35, 0, 0.22, EaseOut, 0.08)
        RunPhases(ScheduleHint)
        return
    end

    local report = Progression.RecordMove(ns.db.profile, result, ns.GetMoveContext())

    if prismMove then
        -- Prismet bytter ikke plass, det tømmer brettet for en farge der det står
        AddSwapPhase(ga, gb, r1, c1, r2, c2, from, 0.35, 0.08, EaseOut)
        AddSwapPhase(ga, gb, r1, c1, r2, c2, 0.35, 0, 0.08, EaseIn)
    else
        local dur = math.max(0.06, SWAP_TIME * (1 - from))
        AddSwapPhase(ga, gb, r1, c1, r2, c2, from, 1, dur, from > 0 and EaseOut or EaseInOut)
    end

    for i = 1, #result.steps do
        local step = result.steps[i]
        if step.kind == "shuffle" then
            AddShuffleStep(step)
        else
            AddClearStep(step, i == 1 and prismMove)
        end
    end

    RunPhases(function()
        SyncBoard()
        SetScore(ns.board.score)
        UI.ShowReport(report)
        ScheduleHint()
    end)
end

local function SpringBack(ga, gb, r1, c1, r2, c2, amt)
    if not ga or not gb or amt <= 0 then
        SyncBoard()
        ScheduleHint()
        return
    end
    AddSwapPhase(ga, gb, r1, c1, r2, c2, amt, 0, 0.12, EaseOut)
    RunPhases(ScheduleHint)
end

----------------------------------------------------------------------
-- Mus
----------------------------------------------------------------------

-- Musepekeren i brettets koordinater (også utenfor brettet)
local function CursorLocal()
    local x, y = GetCursorPosition()
    local s = board:GetEffectiveScale()
    local left, top = board:GetLeft(), board:GetTop()
    if not left then return end
    return x / s - left, top - y / s
end

local function CursorCell()
    local x, y = CursorLocal()
    if not x then return end
    return math.floor(y / CELL) + 1, math.floor(x / CELL) + 1
end

local function InBoard(r, c)
    return r and r >= 1 and r <= SIZE and c >= 1 and c <= SIZE
end

local function SetHover(g)
    if hoverGem == g then return end
    if hoverGem then hoverGem.hover:Hide() end
    hoverGem = g
    if g then g.hover:Show() end
end

local TrackerOnUpdate

local function RefreshTracker()
    local want = hovering or downR
    if want and not trackerOn then
        trackerOn = true
        tracker:SetScript("OnUpdate", TrackerOnUpdate)
    elseif not want and trackerOn then
        trackerOn = false
        tracker:SetScript("OnUpdate", nil)
        SetHover(nil)
    end
end

local function ResetPress()
    downR, downC, downX, downY = nil, nil, nil, nil
    dragging, dragAmt, dragNR, dragNC, dragGa, dragGb = false, 0, nil, nil, nil, nil
end

-- Avbryter et dratt uten å bytte noe (vindu skjult, brett byttet)
local function CancelDrag()
    if dragging and dragGa then
        dragGa:SetFrameLevel(dragGa.baseLevel)
        if dragGb then
            PlaceSwapped(dragGa, dragGb, downR, downC, dragNR, dragNC, 0)
            dragGa.icon:SetSize(GEM, GEM)
            dragGb.icon:SetSize(GEM, GEM)
        end
    end
    ResetPress()
    if tracker then RefreshTracker() end
end

-- Flytter steinen med musen langs den dominerende aksen, maks én rute
local function UpdateDrag()
    if not downR then return end
    local x, y = CursorLocal()
    if not x then return end
    local dx, dy = x - downX, y - downY
    if not dragging then
        if dx * dx + dy * dy < CLICK_PX * CLICK_PX then return end
        dragging = true
        CancelHint()
        ClearSelection()
        SetHover(nil)
        dragGa = gemFrames[ns.board.cells[downR][downC].id]
        if dragGa then dragGa:SetFrameLevel(dragGa.baseLevel + 2) end
    end
    local dr, dc, d = 0, 0, 0
    if math.abs(dx) >= math.abs(dy) then
        dc, d = dx > 0 and 1 or -1, math.abs(dx)
    else
        dr, d = dy > 0 and 1 or -1, math.abs(dy)
    end
    local nr, nc = downR + dr, downC + dc
    local amt = math.min(1, d / CELL)
    if not InBoard(nr, nc) then amt = 0 end
    if nr ~= dragNR or nc ~= dragNC then
        if dragGb then
            PlaceGem(dragGb, dragNR, dragNC)
            dragGb.icon:SetSize(GEM, GEM)
        end
        dragNR, dragNC = nr, nc
        dragGb = InBoard(nr, nc) and gemFrames[ns.board.cells[nr][nc].id] or nil
    end
    dragAmt = amt
    if dragGa and dragGb then PlaceSwapped(dragGa, dragGb, downR, downC, nr, nc, amt) end
end

local function EndPress()
    if not downR then return end
    UpdateDrag()
    local fromR, fromC = downR, downC
    local wasDrag, amt, nr, nc, ga, gb = dragging, dragAmt, dragNR, dragNC, dragGa, dragGb
    ResetPress()
    RefreshTracker()
    if busy then return end
    if wasDrag then
        if amt >= COMMIT and InBoard(nr, nc) then
            TryMove(fromR, fromC, nr, nc, amt)
        else
            SpringBack(ga, gb, fromR, fromC, nr, nc, amt)
        end
        return
    end
    if selR then
        if selR == fromR and selC == fromC then
            ClearSelection()
            return
        end
        if Core.AreAdjacent(selR, selC, fromR, fromC) then
            TryMove(selR, selC, fromR, fromC)
            return
        end
    end
    Select(fromR, fromC)
    ScheduleHint()
end

function TrackerOnUpdate()
    if downR then
        -- Slippes knappen utenfor brettet er det ikke sikkert OnMouseUp kommer
        if not IsMouseButtonDown("LeftButton") then
            EndPress()
        else
            UpdateDrag()
        end
        return
    end
    if busy then
        SetHover(nil)
        return
    end
    local r, c = CursorCell()
    if InBoard(r, c) then
        SetHover(gemFrames[ns.board.cells[r][c].id])
    else
        SetHover(nil)
    end
end

local function OnBoardMouseDown(_, button)
    if button ~= "LeftButton" then
        ClearSelection()
        return
    end
    if busy then return end
    local r, c = CursorCell()
    if InBoard(r, c) then
        local x, y = CursorLocal()
        downR, downC, downX, downY = r, c, x, y
        dragging, dragAmt, dragNR, dragNC, dragGa, dragGb = false, 0, nil, nil, nil, nil
        RefreshTracker()
    end
end

local function OnBoardMouseUp(_, button)
    if button ~= "LeftButton" then return end
    EndPress()
end

----------------------------------------------------------------------
-- Fremdriftspanel
----------------------------------------------------------------------

local STAT_ROWS = {
    { "Moves", "moves" }, { "Gems cleared", "gems" },
    { "Best move", "bestMove" }, { "Longest chain", "bestChain" },
    { "Specials made", "specialsMade" }, { "Boards started", "boards" },
    { "Flights played", "flights" }, { "Total XP", "totalXP" },
}

local function CountAchievements(profile)
    local earned = 0
    for _, def in ipairs(Progression.ACHIEVEMENTS) do
        if profile.achievements[def.id] then earned = earned + 1 end
    end
    return earned, #Progression.ACHIEVEMENTS
end

local function NextRankText(level)
    if level >= Progression.MAX_LEVEL then return "Highest rank reached." end
    local target = math.min(Progression.MAX_LEVEL, (math.floor(level / 10) + 1) * 10)
    return ("Next rank at level %d: %s"):format(target, Progression.Rank(target))
end

local function CreateProgressPanel()
    local p = CreateFrame("Frame", nil, frame)
    p:SetSize(BOARD_PX, BOARD_PX)
    p:SetPoint("TOPLEFT", PAD, -BOARD_TOP)
    p:Hide()

    p.next = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.next:SetPoint("TOPLEFT", 4, -4)

    p.stats = {}
    local colW = BOARD_PX / 2
    for i, row in ipairs(STAT_ROWS) do
        local col = (i - 1) % 2
        local line = math.floor((i - 1) / 2)
        local label = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        label:SetPoint("TOPLEFT", 4 + col * colW, -26 - line * 16)
        label:SetText(row[1])
        local value = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        value:SetPoint("TOPRIGHT", p, "TOPLEFT", (col + 1) * colW - 10, -26 - line * 16)
        p.stats[i] = value
    end

    p.achHeader = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.achHeader:SetPoint("TOPLEFT", 4, -100)

    p.rows = {}
    local defs = Progression.ACHIEVEMENTS
    local perCol = math.ceil(#defs / 2)
    local rowH = math.min(16, math.floor((BOARD_PX - 124) / perCol))
    for i, def in ipairs(defs) do
        local col = math.floor((i - 1) / perCol)
        local line = (i - 1) % perCol
        local row = CreateFrame("Frame", nil, p)
        row:SetSize(colW - 6, rowH)
        row:SetPoint("TOPLEFT", 4 + col * colW, -122 - line * rowH)
        row.check = row:CreateTexture(nil, "ARTWORK")
        row.check:SetSize(12, 12)
        row.check:SetPoint("LEFT")
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
        row.text:SetPoint("RIGHT")
        row.text:SetJustifyH("LEFT")
        row.text:SetText(def.name)
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(def.name)
            GameTooltip:AddLine(def.desc, 1, 1, 1, true)
            if def.xp > 0 then GameTooltip:AddLine(("Reward: %s XP"):format(Fmt(def.xp)), 0.8, 0.8, 0.8) end
            if ns.db.profile.achievements[def.id] then
                GameTooltip:AddLine("Earned", 0.25, 1, 0.25)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.def = def
        p.rows[i] = row
    end
    return p
end

local function RefreshProgressPanel()
    local profile = ns.db.profile
    progressPanel.next:SetText(NextRankText(profile.level))
    for i, row in ipairs(STAT_ROWS) do
        local v = row[2] == "totalXP" and profile.totalXP or profile.stats[row[2]]
        progressPanel.stats[i]:SetText(Fmt(v or 0))
    end
    local earned, total = CountAchievements(profile)
    progressPanel.achHeader:SetText(("Achievements  %d / %d"):format(earned, total))
    for _, row in ipairs(progressPanel.rows) do
        if profile.achievements[row.def.id] then
            row.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
            row.check:SetDesaturated(false)
            row.text:SetFontObject(GameFontHighlightSmall)
        else
            row.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Waiting")
            row.check:SetDesaturated(true)
            row.text:SetFontObject(GameFontDisableSmall)
        end
    end
end

local function SetProgressShown(show)
    if show then
        CancelHint()
        ClearSelection()
        RefreshProgressPanel()
        board:GetParent():Hide()
        overlay:Hide()
        progressPanel:Show()
        hud.progressButton:SetText("Back to board")
    else
        progressPanel:Hide()
        board:GetParent():Show()
        overlay:Show()
        hud.progressButton:SetText("Progress")
        if not busy then ScheduleHint() end
    end
end

----------------------------------------------------------------------
-- Vindu
----------------------------------------------------------------------

StaticPopupDialogs["GEMCUTTER_NEW_BOARD"] = {
    text = "Start a new board?\nYour board score resets. Level, XP and achievements are kept.",
    button1 = "New board",
    button2 = CANCEL,
    OnAccept = function() ns.NewBoard() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function SavePosition()
    local point, _, relPoint, x, y = frame:GetPoint()
    local w = ns.db.window
    w.point, w.relPoint, w.x, w.y = point, relPoint, x, y
end

function UI.AddProgressTooltipLines(tooltip)
    local p = ns.db.profile
    tooltip:AddLine("Gemcutter")
    tooltip:AddLine(("Level %d  %s"):format(p.level, Progression.Rank(p.level)), 1, 1, 1)
    if p.level < Progression.MAX_LEVEL then
        tooltip:AddLine(("%s / %s XP"):format(Fmt(p.xp), Fmt(Progression.XPToNext(p.level))), 0.8, 0.8, 0.8)
    end
    local earned, total = CountAchievements(p)
    tooltip:AddLine(("Achievements: %d / %d"):format(earned, total), 0.8, 0.8, 0.8)
end

function UI.Create()
    if frame then return end
    frame = CreateFrame("Frame", "GemcutterFrame", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Vi lagrer posisjonen selv, så WoW skal ikke også gjøre det i layout-local.txt
        self:SetUserPlaced(false)
        SavePosition()
    end)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    frame:SetScale(ns.db.window.scale)
    local w = ns.db.window
    if w.point then
        frame:SetPoint(w.point, UIParent, w.relPoint or w.point, w.x or 0, w.y or 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 260, 40)
    end
    frame:Hide()
    tinsert(UISpecialFrames, "GemcutterFrame")

    local header = frame:CreateTexture(nil, "ARTWORK")
    header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    header:SetSize(220, 56)
    header:SetPoint("TOP", 0, 12)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", header, "TOP", 0, -12)
    title:SetText("Gemcutter")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)

    hud.level = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hud.level:SetPoint("TOPLEFT", PAD, -30)
    hud.rank = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hud.rank:SetPoint("TOPLEFT", hud.level, "BOTTOMLEFT", 0, -3)
    hud.score = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    hud.score:SetPoint("TOPRIGHT", -PAD, -30)
    hud.xpText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hud.xpText:SetPoint("TOPRIGHT", hud.score, "BOTTOMRIGHT", 0, -3)

    local xpBar = CreateFrame("StatusBar", nil, frame)
    xpBar:SetSize(BOARD_PX, 8)
    xpBar:SetPoint("TOPLEFT", PAD, -66)
    xpBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    xpBar:SetStatusBarColor(XP_COLOR[1], XP_COLOR[2], XP_COLOR[3])
    local xpBg = xpBar:CreateTexture(nil, "BACKGROUND")
    xpBg:SetAllPoints()
    xpBg:SetColorTexture(0, 0, 0, 0.6)
    xpBar:EnableMouse(true)
    xpBar:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        UI.AddProgressTooltipLines(GameTooltip)
        GameTooltip:AddLine(NextRankText(ns.db.profile.level), 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    xpBar:SetScript("OnLeave", function() GameTooltip:Hide() end)
    hud.xpBar = xpBar

    -- Brettet klipper bort steiner som faller inn ovenfra
    local holder = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    holder:SetSize(BOARD_PX + 2, BOARD_PX + 2)
    holder:SetPoint("TOPLEFT", PAD - 1, -BOARD_TOP + 1)
    holder:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    holder:SetBackdropColor(0, 0, 0, 0.5)
    holder:SetBackdropBorderColor(0.45, 0.38, 0.22, 1)

    board = CreateFrame("Frame", nil, holder)
    board:SetSize(BOARD_PX, BOARD_PX)
    board:SetPoint("TOPLEFT", 1, -1)
    board:SetClipsChildren(true)
    board:EnableMouse(true)
    board:SetScript("OnMouseDown", OnBoardMouseDown)
    board:SetScript("OnMouseUp", OnBoardMouseUp)
    board:SetScript("OnEnter", function()
        hovering = true
        RefreshTracker()
    end)
    board:SetScript("OnLeave", function()
        hovering = false
        RefreshTracker()
    end)
    tracker = CreateFrame("Frame", nil, frame)
    for r = 1, SIZE do
        for c = 1, SIZE do
            local t = board:CreateTexture(nil, "BACKGROUND")
            t:SetSize(CELL, CELL)
            t:SetPoint("TOPLEFT", (c - 1) * CELL, -(r - 1) * CELL)
            local shade = ((r + c) % 2 == 0) and 0.07 or 0.12
            t:SetColorTexture(shade, shade * 0.9, shade * 0.75, 0.6)
        end
    end

    overlay = CreateFrame("Frame", nil, frame)
    overlay:SetSize(BOARD_PX, BOARD_PX)
    overlay:SetPoint("TOPLEFT", PAD, -BOARD_TOP)
    overlay:SetFrameLevel(holder:GetFrameLevel() + 20)

    levelBanner = CreateBanner()
    toast = CreateToast()
    progressPanel = CreateProgressPanel()

    local newButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    newButton:SetSize(120, 22)
    newButton:SetPoint("BOTTOMLEFT", PAD, 16)
    newButton:SetText("New board")
    newButton:SetScript("OnClick", function()
        if ns.board.moves > 0 then
            StaticPopup_Show("GEMCUTTER_NEW_BOARD")
        else
            ns.NewBoard()
        end
    end)

    local progressButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    progressButton:SetSize(120, 22)
    progressButton:SetPoint("BOTTOMRIGHT", -PAD, 16)
    progressButton:SetText("Progress")
    progressButton:SetScript("OnClick", function()
        SetProgressShown(not progressPanel:IsShown())
    end)
    hud.progressButton = progressButton

    frame:SetScript("OnShow", function()
        PlaySFX("open")
        if not busy then
            SyncBoard()
            scoreTarget = ns.board.score
        end
        UpdateHUD(false)
        if progressPanel:IsShown() then RefreshProgressPanel() elseif not busy then ScheduleHint() end
    end)
    frame:SetScript("OnHide", function()
        PlaySFX("close")
        CancelHint()
        ClearSelection()
        hovering = false
        CancelDrag()
    end)

    scoreTarget, scoreShown = ns.board.score, ns.board.score
end

function UI.Show() if frame then frame:Show() end end
function UI.Hide() if frame then frame:Hide() end end

-- Venstreklikk: brettet. Høyreklikk: fremdriftspanelet. Et nytt klikk på det som vises, lukker.
function UI.Toggle()
    if not frame then return end
    if frame:IsShown() then
        frame:Hide()
        return
    end
    if progressPanel:IsShown() then SetProgressShown(false) end
    frame:Show()
end

function UI.ToggleProgress()
    if not frame then return end
    if frame:IsShown() and progressPanel:IsShown() then
        frame:Hide()
        return
    end
    frame:Show()
    SetProgressShown(true)
end

function UI.SetScale(scale)
    ns.db.window.scale = scale
    if frame then frame:SetScale(scale) end
end

-- Kalles når brettet byttes ut (nytt brett eller nullstilling)
function UI.OnBoardReplaced()
    if not frame then return end
    CancelDrag()
    StopPhases()
    StopFx()
    CancelHint()
    selR, selC = nil, nil
    for id, g in pairs(gemFrames) do
        ReleaseGem(g)
        gemFrames[id] = nil
    end
    SyncBoard()
    scoreTarget = ns.board.score
    UpdateHUD(false)
    if progressPanel:IsShown() then RefreshProgressPanel() end
    if frame:IsShown() and not progressPanel:IsShown() then ScheduleHint() end
end
