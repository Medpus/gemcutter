local addonName, ns = ...

-- Permanent progresjon for hele kontoen. Ingen WoW-globaler her.
local Progression = {}
ns.Progression = Progression

local floor = math.floor

Progression.MAX_LEVEL = 60
local MAX_LEVEL = Progression.MAX_LEVEL

local STAT_KEYS = {
    "moves", "gems", "bestMove", "bestChain", "specialsMade", "prismsMade",
    "volatilesMade", "linesMade", "doublePrisms", "boards", "flights",
}

function Progression.NewProfile()
    local stats = {}
    for _, k in ipairs(STAT_KEYS) do stats[k] = 0 end
    return { v = 1, level = 1, xp = 0, totalXP = 0, stats = stats, achievements = {} }
end

local function num(x, default)
    if type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge then return x end
    return default
end

function Progression.Upgrade(profile)
    if type(profile) ~= "table" then return Progression.NewProfile() end
    profile.v = 1
    profile.level = floor(num(profile.level, 1))
    if profile.level < 1 then profile.level = 1 end
    if profile.level > MAX_LEVEL then profile.level = MAX_LEVEL end
    profile.xp = num(profile.xp, 0)
    if profile.xp < 0 then profile.xp = 0 end
    profile.totalXP = num(profile.totalXP, 0)
    if type(profile.stats) ~= "table" then profile.stats = {} end
    for _, k in ipairs(STAT_KEYS) do profile.stats[k] = num(profile.stats[k], 0) end
    if type(profile.achievements) ~= "table" then profile.achievements = {} end
    if profile.level >= MAX_LEVEL then profile.xp = 0 end
    return profile
end

function Progression.XPToNext(level)
    if level >= MAX_LEVEL then return math.huge end
    if level < 1 then level = 1 end
    return 100 + 40 * (level - 1)
end

local RANKS = {
    { 60, "Grand Master Gemcutter" },
    { 50, "Master Gemcutter" },
    { 40, "Artisan Gemcutter" },
    { 30, "Expert Gemcutter" },
    { 20, "Journeyman Gemcutter" },
    { 10, "Apprentice Gemcutter" },
    { 1, "Novice Gemcutter" },
}

function Progression.Rank(level)
    for _, e in ipairs(RANKS) do
        if level >= e[1] then return e[2] end
    end
    return RANKS[#RANKS][2]
end

function Progression.XPForMove(result)
    if type(result) ~= "table" or not result.valid then return 0 end
    return floor((result.score or 0) / 10) + 1
end

-- Legger til XP, kan krysse flere nivåer. Nye nivåer føres i levelUps.
local function addXP(profile, amount, levelUps)
    if amount <= 0 then return end
    profile.totalXP = profile.totalXP + amount
    if profile.level >= MAX_LEVEL then
        profile.xp = 0
        return
    end
    profile.xp = profile.xp + amount
    while profile.level < MAX_LEVEL do
        local need = Progression.XPToNext(profile.level)
        if profile.xp < need then break end
        profile.xp = profile.xp - need
        profile.level = profile.level + 1
        levelUps[#levelUps + 1] = profile.level
    end
    if profile.level >= MAX_LEVEL then profile.xp = 0 end
end

-- Alle sjekker leser bare stats/level, så de kan kjøres om igjen uten bivirkninger.
local function def(id, name, desc, xp, check)
    return { id = id, name = name, desc = desc, xp = xp, check = check }
end

local function stat(key, n)
    return function(p) return p.stats[key] >= n end
end

Progression.ACHIEVEMENTS = {
    def("first_match", "First Cut", "Make a match.", 25, stat("moves", 1)),
    def("chain_3", "Chain Reaction", "Trigger a 3-step cascade in one move.", 50, stat("bestChain", 3)),
    def("chain_5", "Avalanche", "Trigger a 5-step cascade in one move.", 150, stat("bestChain", 5)),
    def("chain_8", "Landslide", "Trigger an 8-step cascade in one move.", 400, stat("bestChain", 8)),
    def("make_line", "Charged", "Create a line gem.", 50, stat("linesMade", 1)),
    def("make_volatile", "Volatile Compound", "Create a volatile gem.", 75, stat("volatilesMade", 1)),
    def("make_prism", "Prismatic", "Create a prism gem.", 100, stat("prismsMade", 1)),
    def("double_prism", "Blinding Light", "Swap two prisms.", 300, stat("doublePrisms", 1)),
    def("move_500", "Big Move", "Score 500 points in one move.", 100, stat("bestMove", 500)),
    def("move_2000", "Shatterstorm", "Score 2,000 points in one move.", 400, stat("bestMove", 2000)),
    def("gems_1k", "Rockhound", "Clear 1,000 gems.", 100, stat("gems", 1000)),
    def("gems_10k", "Quarry Boss", "Clear 10,000 gems.", 300, stat("gems", 10000)),
    def("gems_100k", "Mountain Mover", "Clear 100,000 gems.", 1000, stat("gems", 100000)),
    def("flights_10", "Frequent Flyer", "Play during 10 different flights.", 200, stat("flights", 10)),
    def("flights_50", "Sky Gem", "Play during 50 different flights.", 500, stat("flights", 50)),
    def("level_10", "Apprentice", "Reach level 10.", 0, function(p) return p.level >= 10 end),
    def("level_30", "Expert", "Reach level 30.", 0, function(p) return p.level >= 30 end),
    def("level_60", "Grand Master", "Reach level 60.", 0, function(p) return p.level >= MAX_LEVEL end),
}

-- Kjører passes til ingenting nytt låses opp (nivå-achievements kan komme etter XP fra andre).
local function awardAchievements(profile, result, report)
    local earnedAny = true
    while earnedAny do
        earnedAny = false
        for _, d in ipairs(Progression.ACHIEVEMENTS) do
            if not profile.achievements[d.id] and d.check(profile, result) then
                profile.achievements[d.id] = true
                report.achievements[#report.achievements + 1] = d
                report.xp = report.xp + d.xp
                addXP(profile, d.xp, report.levelUps)
                earnedAny = true
            end
        end
    end
end

local function newReport()
    return { xp = 0, levelUps = {}, achievements = {} }
end

function Progression.RecordMove(profile, result, ctx)
    local report = newReport()
    if type(result) ~= "table" or not result.valid then return report end
    local s = profile.stats

    s.moves = s.moves + 1
    if result.score > s.bestMove then s.bestMove = result.score end
    if result.chain > s.bestChain then s.bestChain = result.chain end
    for i, step in ipairs(result.steps) do
        if step.kind == "clear" then
            s.gems = s.gems + #step.cleared
            for _, g in ipairs(step.created) do
                s.specialsMade = s.specialsMade + 1
                if g.special == "prism" then
                    s.prismsMade = s.prismsMade + 1
                elseif g.special == "volatile" then
                    s.volatilesMade = s.volatilesMade + 1
                else
                    s.linesMade = s.linesMade + 1
                end
            end
            if i == 1 and step.doublePrism then s.doublePrisms = s.doublePrisms + 1 end
        end
    end
    if ctx and ctx.newFlight then s.flights = s.flights + 1 end

    local xp = Progression.XPForMove(result)
    report.xp = xp
    addXP(profile, xp, report.levelUps)
    awardAchievements(profile, result, report)
    return report
end

function Progression.RecordNewBoard(profile)
    local report = newReport()
    profile.stats.boards = profile.stats.boards + 1
    awardAchievements(profile, nil, report)
    return report
end

Progression.AddXP = function(profile, amount)
    local report = newReport()
    report.xp = amount
    addXP(profile, amount, report.levelUps)
    awardAchievements(profile, nil, report)
    return report
end
