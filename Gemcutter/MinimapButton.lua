local addonName, ns = ...

-- Minimapknappen går via LibDataBroker og LibDBIcon, så knappesamlere (Leatrix Plus,
-- MinimapButtonButton o.l.) og broker-linjer (Titan Panel, ChocolateBar) kan ta den.
local MinimapButton = {}
ns.MinimapButton = MinimapButton

MinimapButton.ICON = "Interface\\AddOns\\" .. addonName .. "\\Media\\Icon"

local DBIcon

function MinimapButton.AddTooltipLines(tooltip)
    ns.UI.AddProgressTooltipLines(tooltip)
    tooltip:AddLine(" ")
    tooltip:AddLine("Left-click: open or close the board", 0.8, 0.8, 0.8)
    tooltip:AddLine("Right-click: your progress and achievements", 0.8, 0.8, 0.8)
end

function MinimapButton.OnClick(button)
    if button == "RightButton" then
        ns.UI.ToggleProgress()
    else
        ns.UI.Toggle()
    end
end

-- Brukes av addon-menyen ved minimap (TOC: AddonCompartmentFuncOnEnter)
function MinimapButton.ShowTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    MinimapButton.AddTooltipLines(GameTooltip)
    GameTooltip:Show()
end

function MinimapButton.Create()
    local LDB = LibStub("LibDataBroker-1.1")
    DBIcon = LibStub("LibDBIcon-1.0")
    local launcher = LDB:NewDataObject(addonName, {
        type = "launcher",
        label = addonName,
        icon = MinimapButton.ICON,
        OnClick = function(_, button) MinimapButton.OnClick(button) end,
        OnTooltipShow = function(tooltip) MinimapButton.AddTooltipLines(tooltip) end,
    })
    DBIcon:Register(addonName, launcher, ns.db.minimap)
end

function MinimapButton.Toggle()
    ns.db.minimap.hide = not ns.db.minimap.hide
    if ns.db.minimap.hide then
        DBIcon:Hide(addonName)
    else
        DBIcon:Show(addonName)
    end
    return not ns.db.minimap.hide
end
