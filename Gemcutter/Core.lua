local addonName, ns = ...

-- Ren spill-logikk for Gemcutter. Ingen WoW-globaler her.
local Core = {}
ns.Core = Core

local floor, abs = math.floor, math.abs
local type, setmetatable, ipairs = type, setmetatable, ipairs

local SIZE = 8
local NUM_COLORS = 7
local PRISM = 0
local MODULUS = 2147483647

Core.SIZE = SIZE
Core.NUM_COLORS = NUM_COLORS
Core.PRISM = PRISM

----------------------------------------------------------------------
-- RNG (Park-Miller)
----------------------------------------------------------------------

local RNG = {}
RNG.__index = RNG

function RNG:Next()
    self.state = (self.state * 16807) % MODULUS
    return self.state / MODULUS
end

function RNG:Int(n)
    return floor(self:Next() * n) + 1
end

local function normSeed(seed)
    if type(seed) ~= "number" or seed ~= seed or seed == math.huge or seed == -math.huge then
        return 1
    end
    local s = floor(abs(seed)) % MODULUS
    if s == 0 then s = 1 end
    return s
end

function Core.NewRNG(seed)
    return setmetatable({ state = normSeed(seed) }, RNG)
end

-- Gir metodene tilbake til en deserialisert { state = x }
function Core.AttachRNG(t)
    t.state = normSeed(t.state)
    return setmetatable(t, RNG)
end

----------------------------------------------------------------------
-- Hjelpere for brettet
----------------------------------------------------------------------

local function inRange(r, c)
    return type(r) == "number" and type(c) == "number"
        and r >= 1 and r <= SIZE and c >= 1 and c <= SIZE
        and r == floor(r) and c == floor(c)
end

local function newGem(board, color, special)
    local id = board.nextId
    board.nextId = id + 1
    return { id = id, color = color, special = special }
end

local function swapCells(cells, r1, c1, r2, c2)
    cells[r1][c1], cells[r2][c2] = cells[r2][c2], cells[r1][c1]
end

local function runLen(cells, r, c, dr, dc, color)
    local n = 0
    r, c = r + dr, c + dc
    while r >= 1 and r <= SIZE and c >= 1 and c <= SIZE and cells[r][c].color == color do
        n = n + 1
        r, c = r + dr, c + dc
    end
    return n
end

-- Summen av lengdene på linjer (>= 3) gjennom cellen
local function lineScore(cells, r, c)
    local color = cells[r][c].color
    if color == PRISM then return 0 end
    local s = 0
    local h = 1 + runLen(cells, r, c, 0, -1, color) + runLen(cells, r, c, 0, 1, color)
    if h >= 3 then s = s + h end
    local v = 1 + runLen(cells, r, c, -1, 0, color) + runLen(cells, r, c, 1, 0, color)
    if v >= 3 then s = s + v end
    return s
end

local function moveScore(cells, r1, c1, r2, c2)
    local a, b = cells[r1][c1], cells[r2][c2]
    -- Prismet kan byttes med hva som helst, men et hint som peker på prismet og en tilfeldig nabo
    -- ser ut som et trekk uten treff. Prismetrekk teller derfor lavest og vises bare når ingenting
    -- annet finnes. Vanlige treff gir minst 3.
    if a.color == PRISM or b.color == PRISM then
        if a.color == PRISM and b.color == PRISM then return 2 end
        return 1
    end
    swapCells(cells, r1, c1, r2, c2)
    local s = lineScore(cells, r1, c1) + lineScore(cells, r2, c2)
    swapCells(cells, r1, c1, r2, c2)
    return s
end

local function hasMovesCells(cells)
    for r = 1, SIZE do
        for c = 1, SIZE do
            if c < SIZE and moveScore(cells, r, c, r, c + 1) > 0 then return true end
            if r < SIZE and moveScore(cells, r, c, r + 1, c) > 0 then return true end
        end
    end
    return false
end

-- Finner grupper av treff: vannrette og loddrette linjer som deler en celle slås sammen
local function findGroups(cells)
    local runs, n = {}, 0
    for r = 1, SIZE do
        local c = 1
        while c <= SIZE do
            local color = cells[r][c].color
            local e = c
            while e < SIZE and cells[r][e + 1].color == color do e = e + 1 end
            if color ~= PRISM and e - c + 1 >= 3 then
                n = n + 1
                runs[n] = { color = color, horiz = true, r = r, c = c, len = e - c + 1 }
            end
            c = e + 1
        end
    end
    for c = 1, SIZE do
        local r = 1
        while r <= SIZE do
            local color = cells[r][c].color
            local e = r
            while e < SIZE and cells[e + 1][c].color == color do e = e + 1 end
            if color ~= PRISM and e - r + 1 >= 3 then
                n = n + 1
                runs[n] = { color = color, horiz = false, r = r, c = c, len = e - r + 1 }
            end
            r = e + 1
        end
    end
    if n == 0 then return {} end

    local parent = {}
    for i = 1, n do parent[i] = i end
    local function find(x)
        while parent[x] ~= x do
            parent[x] = parent[parent[x]]
            x = parent[x]
        end
        return x
    end
    local function keyAt(run, k)
        if run.horiz then return (run.r - 1) * SIZE + run.c + k end
        return (run.r + k - 1) * SIZE + run.c
    end

    local owner = {}
    for i = 1, n do
        local run = runs[i]
        for k = 0, run.len - 1 do
            local key = keyAt(run, k)
            local o = owner[key]
            if o then
                local a, b = find(o), find(i)
                if a ~= b then parent[b] = a end
            else
                owner[key] = i
            end
        end
    end

    local groups, byRoot = {}, {}
    for i = 1, n do
        local root = find(i)
        local g = byRoot[root]
        if not g then
            g = { color = runs[i].color, runs = {}, keys = {}, set = {} }
            byRoot[root] = g
            groups[#groups + 1] = g
        end
        g.runs[#g.runs + 1] = runs[i]
        for k = 0, runs[i].len - 1 do
            local key = keyAt(runs[i], k)
            if not g.set[key] then
                g.set[key] = true
                g.keys[#g.keys + 1] = key
            end
        end
    end
    for _, g in ipairs(groups) do g.cross = #g.runs > 1 end
    return groups
end

local function placement(g, pref)
    if pref then
        for _, key in ipairs(pref) do
            if g.set[key] then return key end
        end
    end
    if g.cross then
        local hs = {}
        for _, run in ipairs(g.runs) do
            if run.horiz then
                for k = 0, run.len - 1 do hs[(run.r - 1) * SIZE + run.c + k] = true end
            end
        end
        for _, run in ipairs(g.runs) do
            if not run.horiz then
                for k = 0, run.len - 1 do
                    local key = (run.r + k - 1) * SIZE + run.c
                    if hs[key] then return key end
                end
            end
        end
    end
    local run = g.runs[1]
    local k = floor(run.len / 2)
    if run.horiz then return (run.r - 1) * SIZE + run.c + k end
    return (run.r + k - 1) * SIZE + run.c
end

local function keyRC(key)
    return floor((key - 1) / SIZE) + 1, (key - 1) % SIZE + 1
end

local BONUS = { lineH = 30, lineV = 30, volatile = 50, prism = 100 }

----------------------------------------------------------------------
-- Ett clear-steg: marker -> utløs spesialer -> fjern -> tyngdekraft -> spawn
----------------------------------------------------------------------

-- marked[key] = "match"|"special", order = nøkler i rekkefølge,
-- created = { {key, kind, color} }, noFire[key] = spesial som ikke skal utløses
local function clearStep(board, chain, marked, order, created, matches, noFire)
    local cells, rng = board.cells, board.rng
    local fired, triggered = {}, {}

    local function mark(r, c)
        if r < 1 or r > SIZE or c < 1 or c > SIZE then return end
        local key = (r - 1) * SIZE + c
        if not marked[key] then
            marked[key] = "special"
            order[#order + 1] = key
        end
    end

    local i = 1
    while i <= #order do
        local key = order[i]
        i = i + 1
        local r, c = keyRC(key)
        local gem = cells[r][c]
        local kind = gem.special
        if kind and not fired[key] and not (noFire and noFire[key]) then
            fired[key] = true
            triggered[#triggered + 1] = { r = r, c = c, id = gem.id, special = kind }
            if kind == "lineH" then
                for cc = 1, SIZE do mark(r, cc) end
            elseif kind == "lineV" then
                for rr = 1, SIZE do mark(rr, c) end
            elseif kind == "volatile" then
                for dr = -1, 1 do
                    for dc = -1, 1 do mark(r + dr, c + dc) end
                end
            elseif kind == "prism" then
                -- tilfeldig farge blant dem som fortsatt står igjen
                local present, list = {}, {}
                for rr = 1, SIZE do
                    for cc = 1, SIZE do
                        local g = cells[rr][cc]
                        if g.color ~= PRISM and not marked[(rr - 1) * SIZE + cc] then
                            present[g.color] = true
                        end
                    end
                end
                for col = 1, NUM_COLORS do
                    if present[col] then list[#list + 1] = col end
                end
                if #list > 0 then
                    local pick = list[rng:Int(#list)]
                    for rr = 1, SIZE do
                        for cc = 1, SIZE do
                            if cells[rr][cc].color == pick then mark(rr, cc) end
                        end
                    end
                end
            end
        end
    end

    local step = {
        kind = "clear", chain = chain,
        cleared = {}, triggered = triggered, created = {},
        falls = {}, spawns = {}, matches = matches or {},
    }
    local points = 0
    for _, key in ipairs(order) do
        local r, c = keyRC(key)
        local gem = cells[r][c]
        step.cleared[#step.cleared + 1] = {
            r = r, c = c, id = gem.id, color = gem.color, special = gem.special, cause = marked[key],
        }
        cells[r][c] = nil
        points = points + 10
    end

    for _, cr in ipairs(created) do
        local r, c = keyRC(cr.key)
        local gem = newGem(board, cr.color, cr.kind)
        cells[r][c] = gem
        step.created[#step.created + 1] = { r = r, c = c, id = gem.id, color = gem.color, special = gem.special }
        points = points + BONUS[cr.kind]
    end

    for c = 1, SIZE do
        local write = SIZE
        for r = SIZE, 1, -1 do
            local gem = cells[r][c]
            if gem then
                if r ~= write then
                    cells[write][c] = gem
                    cells[r][c] = nil
                    step.falls[#step.falls + 1] = { id = gem.id, c = c, fromR = r, toR = write }
                end
                write = write - 1
            end
        end
        local n = write
        for r = 1, n do
            local gem = newGem(board, rng:Int(NUM_COLORS), nil)
            cells[r][c] = gem
            step.spawns[#step.spawns + 1] = { id = gem.id, r = r, c = c, color = gem.color, fromR = r - n }
        end
    end

    step.score = points * chain
    return step
end

local function matchStep(board, chain, groups, pref)
    local marked, order, created, matches = {}, {}, {}, {}
    for _, g in ipairs(groups) do
        for _, key in ipairs(g.keys) do
            marked[key] = "match"
            order[#order + 1] = key
        end
        matches[#matches + 1] = { color = g.color, length = #g.keys, shape = g.cross and "cross" or "line" }
        local kind, color
        if g.cross then
            kind, color = "volatile", g.color
        elseif #g.keys == 4 then
            kind, color = g.runs[1].horiz and "lineH" or "lineV", g.color
        elseif #g.keys >= 5 then
            kind, color = "prism", PRISM
        end
        if kind then
            created[#created + 1] = { key = placement(g, pref), kind = kind, color = color }
        end
    end
    return clearStep(board, chain, marked, order, created, matches, nil)
end

----------------------------------------------------------------------
-- Brett
----------------------------------------------------------------------

local function formsMatch(cells, r, c, color)
    if c >= 3 and cells[r][c - 1].color == color and cells[r][c - 2].color == color then return true end
    if r >= 3 and cells[r - 1][c].color == color and cells[r - 2][c].color == color then return true end
    return false
end

function Core.HasMoves(board)
    return hasMovesCells(board.cells)
end

function Core.HasMatches(board)
    return #findGroups(board.cells) > 0
end

function Core.NewBoard(seed)
    local board = { size = SIZE, cells = {}, rng = Core.NewRNG(seed), nextId = 1, score = 0, moves = 0 }
    local rng = board.rng
    repeat
        board.nextId = 1
        local cells = {}
        board.cells = cells
        for r = 1, SIZE do
            cells[r] = {}
            for c = 1, SIZE do
                local color
                repeat
                    color = rng:Int(NUM_COLORS)
                until not formsMatch(cells, r, c, color)
                cells[r][c] = newGem(board, color, nil)
            end
        end
    until hasMovesCells(board.cells)
    return board
end

function Core.AreAdjacent(r1, c1, r2, c2)
    if type(r1) ~= "number" or type(c1) ~= "number" or type(r2) ~= "number" or type(c2) ~= "number" then
        return false
    end
    return abs(r1 - r2) + abs(c1 - c2) == 1
end

-- Stokker brikkene på nytt til brettet er stabilt og har et trekk. Feiler aldri.
function Core.Shuffle(board)
    local cells, rng = board.cells, board.rng
    local list = {}
    for r = 1, SIZE do
        for c = 1, SIZE do list[#list + 1] = cells[r][c] end
    end
    local n = #list
    local function place()
        for i = 1, n do
            cells[floor((i - 1) / SIZE) + 1][(i - 1) % SIZE + 1] = list[i]
        end
    end
    local function ok()
        return #findGroups(cells) == 0 and hasMovesCells(cells)
    end

    local done = false
    for _ = 1, 50 do
        for i = n, 2, -1 do
            local j = rng:Int(i)
            list[i], list[j] = list[j], list[i]
        end
        place()
        if ok() then done = true break end
    end
    local tries = 0
    while not done do
        tries = tries + 1
        for i = 1, n do
            local gem = list[i]
            if not gem.special then
                if tries > 1000 then
                    local r, c = floor((i - 1) / SIZE) + 1, (i - 1) % SIZE + 1
                    gem.color = (r + 2 * c) % NUM_COLORS + 1
                else
                    gem.color = rng:Int(NUM_COLORS)
                end
            end
        end
        place()
        if ok() or tries > 1000 then done = true end
    end

    local moves = {}
    for r = 1, SIZE do
        for c = 1, SIZE do
            moves[#moves + 1] = { id = cells[r][c].id, r = r, c = c }
        end
    end
    return { kind = "shuffle", moves = moves }
end

function Core.TrySwap(board, r1, c1, r2, c2)
    if not inRange(r1, c1) or not inRange(r2, c2) or not Core.AreAdjacent(r1, c1, r2, c2) then
        return { valid = false }
    end
    local cells = board.cells
    local a, b = cells[r1][c1], cells[r2][c2]
    local steps = {}
    local step

    if a.color == PRISM or b.color == PRISM then
        local marked, order, noFire = {}, {}, {}
        local function mark(r, c)
            local key = (r - 1) * SIZE + c
            if not marked[key] then
                marked[key] = "special"
                order[#order + 1] = key
            end
        end
        local doublePrism = a.color == PRISM and b.color == PRISM
        if doublePrism then
            for r = 1, SIZE do
                for c = 1, SIZE do
                    mark(r, c)
                    noFire[(r - 1) * SIZE + c] = true
                end
            end
        else
            local pr, pc, other = r1, c1, b
            if b.color == PRISM then pr, pc, other = r2, c2, a end
            mark(pr, pc)
            noFire[(pr - 1) * SIZE + pc] = true
            for r = 1, SIZE do
                for c = 1, SIZE do
                    if cells[r][c].color == other.color then mark(r, c) end
                end
            end
        end
        step = clearStep(board, 1, marked, order, {}, {}, noFire)
        if doublePrism then step.doublePrism = true end
    else
        swapCells(cells, r1, c1, r2, c2)
        local groups = findGroups(cells)
        if #groups == 0 then
            swapCells(cells, r1, c1, r2, c2)
            return { valid = false }
        end
        -- gemmen spilleren flyttet INN i (r2,c2) foretrekkes som plassering
        step = matchStep(board, 1, groups, { (r2 - 1) * SIZE + c2, (r1 - 1) * SIZE + c1 })
    end

    steps[1] = step
    local total = step.score
    local chain = 1
    while true do
        local groups = findGroups(cells)
        if #groups == 0 then break end
        chain = chain + 1
        step = matchStep(board, chain, groups, nil)
        steps[#steps + 1] = step
        total = total + step.score
    end

    local shuffled = false
    if not hasMovesCells(cells) then
        steps[#steps + 1] = Core.Shuffle(board)
        shuffled = true
    end

    board.score = board.score + total
    board.moves = board.moves + 1
    return { valid = true, steps = steps, score = total, chain = chain, shuffled = shuffled }
end

function Core.FindHint(board)
    local cells = board.cells
    local best, br1, bc1, br2, bc2 = 0
    for r = 1, SIZE do
        for c = 1, SIZE do
            if c < SIZE then
                local s = moveScore(cells, r, c, r, c + 1)
                if s > best then best, br1, bc1, br2, bc2 = s, r, c, r, c + 1 end
            end
            if r < SIZE then
                local s = moveScore(cells, r, c, r + 1, c)
                if s > best then best, br1, bc1, br2, bc2 = s, r, c, r + 1, c end
            end
        end
    end
    if best == 0 then return nil end
    return br1, bc1, br2, bc2
end

----------------------------------------------------------------------
-- Lagring
----------------------------------------------------------------------

local CODE_OF = { lineH = 1, lineV = 2, volatile = 3, prism = 4 }
local KIND_OF = { [1] = "lineH", [2] = "lineV", [3] = "volatile", [4] = "prism" }

function Core.Serialize(board)
    local flat = {}
    for r = 1, SIZE do
        for c = 1, SIZE do
            local g = board.cells[r][c]
            flat[#flat + 1] = { g.id, g.color, g.special and CODE_OF[g.special] or 0 }
        end
    end
    return {
        v = 1, size = SIZE, rng = board.rng.state, nextId = board.nextId,
        score = board.score, moves = board.moves, cells = flat,
    }
end

local function isInt(x)
    return type(x) == "number" and x == floor(x) and x > -9007199254740992 and x < 9007199254740992
end

local function deserialize(t)
    if type(t) ~= "table" or t.v ~= 1 or t.size ~= SIZE then return nil end
    if not isInt(t.rng) or t.rng < 1 or t.rng >= MODULUS then return nil end
    if not isInt(t.nextId) or t.nextId < 1 then return nil end
    if not isInt(t.score) or t.score < 0 or not isInt(t.moves) or t.moves < 0 then return nil end
    local flat = t.cells
    if type(flat) ~= "table" or #flat ~= SIZE * SIZE then return nil end

    local board = {
        size = SIZE, cells = {}, rng = setmetatable({ state = t.rng }, RNG),
        nextId = t.nextId, score = t.score, moves = t.moves,
    }
    local seen = {}
    for r = 1, SIZE do board.cells[r] = {} end
    for i = 1, SIZE * SIZE do
        local e = flat[i]
        if type(e) ~= "table" then return nil end
        local id, color, code = e[1], e[2], e[3]
        if not isInt(id) or id < 1 or id >= t.nextId or seen[id] then return nil end
        if not isInt(color) or color < 0 or color > NUM_COLORS then return nil end
        if not isInt(code) or code < 0 or code > 4 then return nil end
        if (color == PRISM) ~= (code == 4) then return nil end
        seen[id] = true
        board.cells[floor((i - 1) / SIZE) + 1][(i - 1) % SIZE + 1] =
            { id = id, color = color, special = KIND_OF[code] }
    end
    if #findGroups(board.cells) > 0 or not hasMovesCells(board.cells) then return nil end
    return board
end

function Core.Deserialize(t)
    local ok, board = pcall(deserialize, t)
    if ok then return board end
    return nil
end
