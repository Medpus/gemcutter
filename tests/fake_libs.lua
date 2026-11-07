-- Falske utgaver av LibStub, LibDataBroker-1.1 og LibDBIcon-1.0 for røyktesten.
-- De ekte bibliotekene bruker mye WoW-API som mocken ikke har; her sjekker vi bare
-- at addonet bruker bibliotekene riktig.

local F = {}

local ldb = { objects = {} }
function ldb:NewDataObject(name, obj)
    assert(type(name) == "string" and type(obj) == "table", "NewDataObject(name, table)")
    assert(not self.objects[name], "data object registered twice: " .. name)
    assert(obj.type == "launcher" or obj.type == "data source", "bad LDB type")
    self.objects[name] = obj
    return obj
end

local icon = { buttons = {} }
function icon:Register(name, obj, db)
    assert(type(obj) == "table" and obj.icon, "Register needs an LDB object with an icon")
    assert(type(db) == "table", "Register needs a saved db table")
    assert(not self.buttons[name], "icon registered twice: " .. name)
    self.buttons[name] = { obj = obj, db = db, shown = not db.hide }
end
function icon:Show(name) self.buttons[name].shown = true end
function icon:Hide(name) self.buttons[name].shown = false end

F.ldb, F.icon = ldb, icon
F.LibStub = setmetatable({}, {
    __call = function(_, name)
        if name == "LibDataBroker-1.1" then return ldb end
        if name == "LibDBIcon-1.0" then return icon end
        error("unexpected library " .. tostring(name))
    end,
})

-- Enkel tooltip som samler linjene
function F.NewTooltip()
    local t = { lines = {} }
    function t:AddLine(text) self.lines[#self.lines + 1] = text end
    return t
end

return F
