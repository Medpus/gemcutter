local addonName, ns = ...

local MinimapButton = {}
ns.MinimapButton = MinimapButton

local RADIUS_OFFSET = 5

-- Hvilke kvadranter som er runde for hver minimapform (samme tabell som LibDBIcon bruker)
local SHAPES = {
    ["ROUND"] = { true, true, true, true },
    ["SQUARE"] = { false, false, false, false },
    ["CORNER-TOPLEFT"] = { false, false, false, true },
    ["CORNER-TOPRIGHT"] = { false, false, true, false },
    ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
    ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
    ["SIDE-LEFT"] = { false, true, false, true },
    ["SIDE-RIGHT"] = { true, false, true, false },
    ["SIDE-TOP"] = { false, false, true, true },
    ["SIDE-BOTTOM"] = { true, true, false, false },
    ["TRICORNER-TOPLEFT"] = { false, true, true, true },
    ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
    ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
    ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

local button

local function UpdatePosition(angleDeg)
    local angle = math.rad(angleDeg or 200)
    local x, y, q = math.cos(angle), math.sin(angle), 1
    if x < 0 then q = q + 1 end
    if y > 0 then q = q + 2 end
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    local quads = SHAPES[shape] or SHAPES.ROUND
    local w = Minimap:GetWidth() / 2 + RADIUS_OFFSET
    local h = Minimap:GetHeight() / 2 + RADIUS_OFFSET
    if quads[q] then
        x, y = x * w, y * h
    else
        local dw = math.sqrt(2 * w * w) - 10
        local dh = math.sqrt(2 * h * h) - 10
        x = math.max(-w, math.min(x * dw, w))
        y = math.max(-h, math.min(y * dh, h))
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    px, py = px / scale, py / scale
    ns.db.minimap.angle = math.deg(math.atan2(py - my, px - mx)) % 360
    UpdatePosition(ns.db.minimap.angle)
end

function MinimapButton.ShowTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    ns.UI.AddProgressTooltipLines(GameTooltip)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click to open or close the board.", 0.8, 0.8, 0.8)
    if owner == button then
        GameTooltip:AddLine("Drag to move this button.", 0.8, 0.8, 0.8)
    end
    GameTooltip:Show()
end

function MinimapButton.Create()
    if button then return end
    button = CreateFrame("Button", "GemFlightMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture(136477) -- Interface\Minimap\UI-Minimap-ZoomButton-Highlight

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture(136467) -- Interface\Minimap\UI-Minimap-Background
    background:SetSize(24, 24)
    background:SetPoint("CENTER")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Gem_Sapphire_02")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    button.icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture(136430) -- Interface\Minimap\MiniMap-TrackingBorder
    border:SetSize(50, 50)
    border:SetPoint("TOPLEFT")

    button:SetScript("OnClick", function()
        ns.UI.Toggle()
    end)
    button:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self:SetScript("OnUpdate", OnDragUpdate)
        GameTooltip:Hide()
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self:UnlockHighlight()
    end)
    button:SetScript("OnMouseDown", function() icon:SetSize(16, 16) end)
    button:SetScript("OnMouseUp", function() icon:SetSize(18, 18) end)
    button:SetScript("OnEnter", function(self) MinimapButton.ShowTooltip(self) end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    UpdatePosition(ns.db.minimap.angle)
    -- Andre addons kan endre minimapformen etter innlasting, så plasser på nytt litt senere
    C_Timer.After(1, function() UpdatePosition(ns.db.minimap.angle) end)
    MinimapButton.UpdateVisibility()
end

function MinimapButton.UpdateVisibility()
    if not button then return end
    if ns.db.minimap.hide then button:Hide() else button:Show() end
end

function MinimapButton.Toggle()
    ns.db.minimap.hide = not ns.db.minimap.hide
    MinimapButton.UpdateVisibility()
    return not ns.db.minimap.hide
end
