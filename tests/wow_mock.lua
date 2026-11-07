-- Streng mock av den delen av WoW-API-et GemFlight bruker.
-- Ukjente metoder (stor forbokstav) og ukjente globaler gir feil, så skrivefeil blir fanget.

local M = {}

local frames = {}
local timers = {}
local playingGroups = {}
M.frames = frames
M.chat = {}
M.popups = {}
M.sounds = 0
M.cursorX, M.cursorY = 0, 0

local function strictIndex(methods, kind)
    return function(obj, key)
        local m = methods[key]
        if m then return m end
        if type(key) == "string" and key:match("^%u") then
            error(("%s has no method '%s'"):format(kind, key), 2)
        end
        return nil
    end
end

local function noop() end

local function addMethods(target, names, impl)
    for name in names:gmatch("%S+") do
        target[name] = (impl and impl[name]) or noop
    end
end

-- Felles for alt som kan plasseres
local regionImpl = {
    SetPoint = function(self, point, rel, relPoint, x, y)
        if type(rel) == "number" then
            x, y = rel, relPoint
            rel, relPoint = nil, point
        end
        self._points = self._points or {}
        self._points[#self._points + 1] = { point, rel, relPoint, x or 0, y or 0 }
    end,
    ClearAllPoints = function(self) self._points = {} end,
    GetPoint = function(self)
        local p = self._points and self._points[1]
        if p then return p[1], p[2], p[3], p[4], p[5] end
    end,
    Show = function(self)
        local was = self._shown
        self._shown = true
        if not was and self._scripts and self._scripts.OnShow and M.IsVisible(self) then self._scripts.OnShow(self) end
    end,
    Hide = function(self)
        local was = self._shown
        self._shown = false
        if was and self._scripts and self._scripts.OnHide then self._scripts.OnHide(self) end
    end,
    IsShown = function(self) return self._shown end,
    IsVisible = function(self) return M.IsVisible(self) end,
    SetShown = function(self, v) if v then self:Show() else self:Hide() end end,
    SetAlpha = function(self, a)
        assert(type(a) == "number", "SetAlpha needs a number")
        self._alpha = a
    end,
    GetAlpha = function(self) return self._alpha or 1 end,
    SetSize = function(self, w, h)
        assert(type(w) == "number" and type(h) == "number", "SetSize needs numbers")
        self._w, self._h = w, h
    end,
    GetWidth = function(self) return self._w or 0 end,
    GetHeight = function(self) return self._h or 0 end,
    GetParent = function(self) return self._parent end,
    CreateAnimationGroup = function(self) return M.NewAnimGroup(self) end,
    SetText = function(self, t) self._text = t end,
    GetText = function(self) return self._text end,
    SetTexture = function(self, t) self._texture = t end,
}

local REGION = "SetPoint ClearAllPoints GetPoint SetAllPoints Show Hide IsShown IsVisible SetShown SetAlpha GetAlpha SetSize SetWidth SetHeight GetWidth GetHeight GetParent CreateAnimationGroup"

local textureMethods = {}
addMethods(textureMethods, REGION .. " SetTexture SetColorTexture SetBlendMode SetVertexColor SetTexCoord SetDesaturated SetRotation", regionImpl)
local fontMethods = {}
addMethods(fontMethods, REGION .. " SetFontObject SetText GetText SetJustifyH SetJustifyV SetTextColor", regionImpl)

local frameImpl = setmetatable({
    SetScript = function(self, name, fn)
        self._scripts = self._scripts or {}
        self._scripts[name] = fn
    end,
    GetScript = function(self, name) return self._scripts and self._scripts[name] end,
    CreateTexture = function(self)
        return setmetatable({ _parent = self, _shown = true, _kind = "Texture" }, { __index = strictIndex(textureMethods, "Texture") })
    end,
    CreateFontString = function(self)
        return setmetatable({ _parent = self, _shown = true, _kind = "FontString" }, { __index = strictIndex(fontMethods, "FontString") })
    end,
    RegisterEvent = function(self, e)
        self._events = self._events or {}
        self._events[e] = true
    end,
    UnregisterEvent = function(self, e) if self._events then self._events[e] = nil end end,
    GetEffectiveScale = function(self) return 1 end,
    GetLeft = function(self) return self._left end,
    GetTop = function(self) return self._top end,
    GetCenter = function(self) return self._cx or 0, self._cy or 0 end,
    SetClipsChildren = function(self, v) self._clips = v end,
    GetFrameLevel = function(self) return self._level or 1 end,
    SetFrameLevel = function(self, l) self._level = l end,
    SetText = function(self, t) self._text = t end,
}, { __index = regionImpl })

local FRAME = REGION .. " SetScript GetScript HookScript CreateTexture CreateFontString RegisterEvent UnregisterEvent"
    .. " SetFrameStrata SetFrameLevel GetFrameLevel SetToplevel SetClampedToScreen SetMovable EnableMouse RegisterForDrag"
    .. " StartMoving StopMovingOrSizing SetUserPlaced GetEffectiveScale SetScale GetLeft GetTop GetCenter SetClipsChildren"
local BUTTON = FRAME .. " RegisterForClicks SetHighlightTexture LockHighlight UnlockHighlight SetText GetText Enable Disable"
local STATUSBAR = FRAME .. " SetStatusBarTexture SetStatusBarColor SetMinMaxValues SetValue"
local BACKDROP = " SetBackdrop SetBackdropColor SetBackdropBorderColor"

local classMethods = {}
local function classFor(frameType, template)
    local key = frameType .. "|" .. (template or "")
    if classMethods[key] then return classMethods[key] end
    local names = FRAME
    if frameType == "Button" then names = BUTTON elseif frameType == "StatusBar" then names = STATUSBAR end
    if template and template:find("BackdropTemplate") then names = names .. BACKDROP end
    if template and (template:find("UIPanelButtonTemplate") or template:find("UIPanelCloseButton")) then names = BUTTON end
    local t = {}
    addMethods(t, names, frameImpl)
    classMethods[key] = t
    return t
end

function M.IsVisible(obj)
    while obj do
        if not obj._shown then return false end
        obj = obj._parent
    end
    return true
end

function M.CreateFrame(frameType, name, parent, template)
    assert(frameType == "Frame" or frameType == "Button" or frameType == "StatusBar", "unexpected frame type " .. tostring(frameType))
    local f = setmetatable({ _type = frameType, _name = name, _parent = parent, _shown = true, _template = template },
        { __index = strictIndex(classFor(frameType, template), frameType) })
    frames[#frames + 1] = f
    if name then rawset(_G, name, f) end
    return f
end

function M.NewAnimGroup(owner)
    local g = { _owner = owner, _anims = {} }
    local animMethods = {}
    addMethods(animMethods, "SetFromAlpha SetToAlpha SetDuration SetStartDelay SetOrder SetOffset SetSmoothing")
    local groupMethods = {}
    addMethods(groupMethods, "CreateAnimation SetLooping Play Stop IsPlaying SetScript SetToFinalAlpha", {
        CreateAnimation = function(self, kind)
            assert(kind == "Alpha" or kind == "Translation" or kind == "Scale", "bad animation type " .. tostring(kind))
            local a = setmetatable({}, { __index = strictIndex(animMethods, "Animation") })
            self._anims[#self._anims + 1] = a
            return a
        end,
        SetLooping = function(self, mode)
            assert(mode == "BOUNCE" or mode == "REPEAT" or mode == "NONE", "bad loop mode")
            self._loop = mode
        end,
        Play = function(self)
            self._playing = true
            playingGroups[self] = true
        end,
        Stop = function(self)
            self._playing = false
            playingGroups[self] = nil
        end,
        IsPlaying = function(self) return self._playing end,
        SetScript = function(self, name, fn)
            assert(name == "OnFinished" or name == "OnPlay" or name == "OnStop", "bad anim script " .. name)
            self["_" .. name] = fn
        end,
    })
    return setmetatable(g, { __index = strictIndex(groupMethods, "AnimationGroup") })
end

-- Fullfører alle ikke-loopende animasjoner (som om tiden har gått)
function M.FinishAnimations()
    for _ = 1, 10 do
        local any = false
        for g in pairs(playingGroups) do
            if g._loop ~= "BOUNCE" and g._loop ~= "REPEAT" then
                playingGroups[g] = nil
                g._playing = false
                any = true
                if g._OnFinished then g._OnFinished(g) end
            end
        end
        if not any then return end
    end
end

function M.Tick(dt)
    for i = 1, #frames do
        local f = frames[i]
        local fn = f._scripts and f._scripts.OnUpdate
        if fn and M.IsVisible(f) then fn(f, dt) end
    end
end

function M.Fire(event, ...)
    for i = 1, #frames do
        local f = frames[i]
        if f._events and f._events[event] and f._scripts and f._scripts.OnEvent then
            f._scripts.OnEvent(f, event, ...)
        end
    end
end

function M.RunTimers()
    local list = timers
    timers = {}
    for _, t in ipairs(list) do
        if not t.cancelled then t.fn() end
    end
end

local fontNames = {
    "GameFontNormal", "GameFontNormalSmall", "GameFontNormalLarge", "GameFontNormalHuge",
    "GameFontHighlight", "GameFontHighlightSmall", "GameFontHighlightLarge", "GameFontDisableSmall",
}

function M.Install()
    local env = {
        CreateFrame = M.CreateFrame,
        GetCursorPosition = function() return M.cursorX, M.cursorY end,
        UnitOnTaxi = function() return M.onTaxi end,
        PlaySound = function(id, channel)
            assert(type(id) == "number", "PlaySound needs a numeric kit id")
            assert(channel == nil or channel == "SFX" or channel == "Master", "bad channel")
            M.sounds = M.sounds + 1
        end,
        SOUNDKIT = {
            IG_MAINMENU_OPTION_CHECKBOX_ON = 856, IG_MAINMENU_OPTION_CHECKBOX_OFF = 857,
            U_CHAT_SCROLL_BUTTON = 1115, IG_ABILITY_PAGE_TURN = 836, LFG_REWARDS = 17316,
            IG_QUEST_LIST_COMPLETE = 878, IG_CHARACTER_INFO_OPEN = 839, IG_CHARACTER_INFO_CLOSE = 840,
        },
        C_Timer = {
            NewTimer = function(d, fn)
                assert(type(d) == "number" and type(fn) == "function")
                local t = { fn = fn }
                t.Cancel = function(self) self.cancelled = true end
                timers[#timers + 1] = t
                return t
            end,
            After = function(d, fn)
                assert(type(d) == "number" and type(fn) == "function")
                timers[#timers + 1] = { fn = fn }
            end,
        },
        DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) M.chat[#M.chat + 1] = msg end },
        GameTooltip = setmetatable({}, { __index = strictIndex((function()
            local t = {}
            addMethods(t, "SetOwner AddLine Show Hide ClearLines")
            return t
        end)(), "GameTooltip") }),
        StaticPopupDialogs = {},
        StaticPopup_Show = function(name)
            assert(rawget(_G, "StaticPopupDialogs")[name], "unknown popup " .. name)
            M.popups[#M.popups + 1] = name
        end,
        CANCEL = "Cancel",
        UISpecialFrames = {},
        SlashCmdList = {},
        tinsert = table.insert,
        wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
        BreakUpLargeNumbers = function(n) return tostring(math.floor(n)) end,
    }
    for _, n in ipairs(fontNames) do env[n] = { font = n } end
    for k, v in pairs(env) do rawset(_G, k, v) end
    rawset(_G, "UIParent", M.CreateFrame("Frame", "UIParent"))
    local minimap = M.CreateFrame("Frame", "Minimap", _G.UIParent)
    minimap:SetSize(140, 140)
    minimap._cx, minimap._cy = 1000, 700
end

-- Globaler som addonet har lov til å lage
M.allowedGlobals = {
    GemFlightDB = true, SLASH_GEMFLIGHT1 = true, SLASH_GEMFLIGHT2 = true,
    GemFlightFrame = true, GemFlightMinimapButton = true,
    GemFlight_OnAddonCompartmentClick = true, GemFlight_OnAddonCompartmentEnter = true,
    GemFlight_OnAddonCompartmentLeave = true,
}

-- Globaler som er nil i et vanlig WoW-oppsett, men som addonet sjekker for
M.optionalGlobals = { GetMinimapShape = true }

-- Fra nå av: lesing av ukjente globaler med stor forbokstav og skriving av nye globaler gir feil
function M.Lockdown()
    setmetatable(_G, {
        __index = function(_, k)
            if M.allowedGlobals[k] or M.optionalGlobals[k] then return nil end
            if type(k) == "string" and k:match("^%u") then error("unknown global read: " .. k, 2) end
        end,
        __newindex = function(t, k, v)
            if not M.allowedGlobals[k] then error("addon leaked global: " .. tostring(k), 2) end
            rawset(t, k, v)
        end,
    })
end

return M
