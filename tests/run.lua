-- Kjøres fra repo-roten: luajit tests/run.lua
local ns = {}
assert(loadfile("Gemcutter/Core.lua"))("Gemcutter", ns)
assert(loadfile("Gemcutter/Progression.lua"))("Gemcutter", ns)
local Core, Prog = ns.Core, ns.Progression

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. name .. "\n  " .. tostring(err))
    end
end
local function eq(a, b, msg)
    if a ~= b then error((msg or "eq") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
local function truthy(v, msg)
    if not v then error(msg or "expected truthy", 2) end
end

local function deepEqual(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do
        if k ~= "rng" and not deepEqual(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end
local function snapshot(board)
    local s = { score = board.score, moves = board.moves, nextId = board.nextId, rng = board.rng.state, cells = {} }
    for r = 1, 8 do
        s.cells[r] = {}
        for c = 1, 8 do
            local g = board.cells[r][c]
            s.cells[r][c] = { id = g.id, color = g.color, special = g.special }
        end
    end
    return s
end

-- Bygger et testbrett. Bakgrunn bruker farge 4..7 uten treff, overlay-tegn '1'..'3' er
-- testbrikker, 'P' er prisme, '.' er bakgrunn. specials: { ["r,c"] = kind } gjør gem om til spesial.
local function stubRng()
    local n = 0
    return {
        state = 1,
        Next = function() return 0 end,
        Int = function(_, k)
            n = n + 1
            return (n % math.min(k, 7)) + 1
        end,
    }
end
local function build(overlay, specials)
    local board = { size = 8, cells = {}, rng = stubRng(), nextId = 1, score = 0, moves = 0 }
    for r = 1, 8 do
        board.cells[r] = {}
        local row = overlay[r] or "........"
        for c = 1, 8 do
            local ch = row:sub(c, c)
            local color
            if ch == "." then color = 4 + ((r + 2 * c) % 4)
            elseif ch == "P" then color = 0
            else color = tonumber(ch) end
            local special = specials and specials[r .. "," .. c]
            if ch == "P" then special = "prism" end
            board.cells[r][c] = { id = board.nextId, color = color, special = special }
            board.nextId = board.nextId + 1
        end
    end
    assert(not Core.HasMatches(board), "testbrett har treff fra start")
    return board
end
local function blank() return { "........", "........", "........", "........", "........", "........", "........", "........" } end
local function ov(t)
    local o = blank()
    for r, s in pairs(t) do o[r] = s end
    return o
end

local function checkScores(result)
    local sum = 0
    for _, st in ipairs(result.steps) do
        if st.kind == "clear" then
            local pts = #st.cleared * 10
            for _, g in ipairs(st.created) do
                pts = pts + ({ lineH = 30, lineV = 30, volatile = 50, prism = 100 })[g.special]
            end
            eq(st.score, pts * st.chain, "step score")
            sum = sum + st.score
        end
    end
    eq(result.score, sum, "total score")
end

----------------------------------------------------------------------
-- RNG
----------------------------------------------------------------------
test("rng deterministic and in range", function()
    local a, b = Core.NewRNG(42), Core.NewRNG(42)
    for _ = 1, 1000 do
        local x, y = a:Next(), b:Next()
        eq(x, y)
        truthy(x >= 0 and x < 1)
    end
    local r = Core.NewRNG(7)
    local seen = {}
    for _ = 1, 2000 do
        local v = r:Int(7)
        truthy(v >= 1 and v <= 7 and v == math.floor(v))
        seen[v] = true
    end
    for i = 1, 7 do truthy(seen[i], "value " .. i .. " never seen") end
    eq(Core.NewRNG(42).state, 42)
end)
test("rng seed edge cases", function()
    for _, s in ipairs({ 0, -5, -2147483647, 2147483647, 2147483648, 1.5, 1e15, 0/0, math.huge }) do
        local r = Core.NewRNG(s)
        truthy(r.state >= 1 and r.state <= 2147483646, "state for seed " .. tostring(s))
        for _ = 1, 50 do truthy(r:Int(8) >= 1) end
    end
    truthy(Core.NewRNG(nil).state >= 1)
    local t = Core.AttachRNG({ state = 99 })
    eq(t:Int(1), 1)
end)

----------------------------------------------------------------------
-- Brett og ugyldige trekk
----------------------------------------------------------------------
local function boardOk(board)
    local ids = {}
    for r = 1, 8 do
        for c = 1, 8 do
            local g = board.cells[r][c]
            truthy(g, "tom celle " .. r .. "," .. c)
            truthy(not ids[g.id], "dupe id")
            ids[g.id] = true
            truthy(g.color >= 0 and g.color <= 7)
        end
    end
    truthy(not Core.HasMatches(board), "stabilt brett har treff")
    truthy(Core.HasMoves(board), "ingen trekk")
    return ids
end

test("NewBoard valid for 200 seeds", function()
    for seed = 1, 200 do boardOk(Core.NewBoard(seed)) end
    boardOk(Core.NewBoard(0))
    boardOk(Core.NewBoard(-3))
end)

test("invalid swaps leave board unchanged", function()
    local board = Core.NewBoard(5)
    local before = snapshot(board)
    local function check(r1, c1, r2, c2)
        local res = Core.TrySwap(board, r1, c1, r2, c2)
        eq(res.valid, false)
        truthy(deepEqual(before, snapshot(board)), "brettet endret")
    end
    check(1, 1, 3, 3)
    check(1, 1, 1, 1)
    check(0, 1, 1, 1)
    check(8, 8, 9, 8)
    check(1, 9, 1, 8)
    check(1.5, 1, 2, 1)
    -- finn et adjacent par uten treff
    local found = 0
    for r = 1, 8 do
        for c = 1, 7 do
            local b2 = Core.NewBoard(5)
            local res = Core.TrySwap(b2, r, c, r, c + 1)
            if not res.valid then
                check(r, c, r, c + 1)
                found = found + 1
            end
        end
    end
    truthy(found > 0)
end)

----------------------------------------------------------------------
-- Håndbygde brett
----------------------------------------------------------------------
test("simple 3-match", function()
    local b = build(ov({ [5] = "11.1...." }))
    -- 1 flyttes fra (5,4) til (5,3) gir 11 1 -> bare 3 hvis (5,4) blir bakgrunn
    local res = Core.TrySwap(b, 5, 3, 5, 4)
    -- 1 . 1 etter bytte: (5,3)=1,(5,4)=bg -> 3 på rad
    eq(res.valid, true)
    local s = res.steps[1]
    eq(#s.cleared, 3)
    eq(#s.created, 0)
    eq(s.matches[1].length, 3)
    eq(s.matches[1].shape, "line")
    eq(s.matches[1].color, 1)
    eq(s.score, 30)
    checkScores(res)
end)

test("4-line horizontal makes lineH at moved-into cell", function()
    local b = build(ov({ [5] = "11.1....", [6] = "..1....." }))
    local res = Core.TrySwap(b, 6, 3, 5, 3)
    eq(res.valid, true)
    local s = res.steps[1]
    eq(#s.created, 1)
    eq(s.created[1].r, 5); eq(s.created[1].c, 3)
    eq(s.created[1].special, "lineH"); eq(s.created[1].color, 1)
    eq(#s.cleared, 4)
    eq(s.score, 40 + 30)
    local ids = {}
    for _, c in ipairs(s.cleared) do ids[c.id] = true end
    truthy(not ids[s.created[1].id])
    checkScores(res)
end)

test("4-line vertical makes lineV at moved-into cell", function()
    local b = build(ov({ [3] = "....1...", [4] = "....1...", [5] = ".....1..", [6] = "....1..." }))
    local res = Core.TrySwap(b, 5, 6, 5, 5)
    eq(res.valid, true)
    local s = res.steps[1]
    eq(s.created[1].r, 5); eq(s.created[1].c, 5)
    eq(s.created[1].special, "lineV")
    checkScores(res)
end)

test("5-line makes prism", function()
    local b = build(ov({ [5] = "11.11...", [6] = "..1....." }))
    local res = Core.TrySwap(b, 6, 3, 5, 3)
    eq(res.valid, true)
    local s = res.steps[1]
    eq(s.created[1].special, "prism"); eq(s.created[1].color, 0)
    eq(s.created[1].r, 5); eq(s.created[1].c, 3)
    eq(s.score, 50 + 100)
    checkScores(res)
end)

test("L shape makes volatile at intersection", function()
    local b = build(ov({ [4] = "..1.....", [5] = "11......", [6] = "..1.....", [7] = "..1....." }))
    local res = Core.TrySwap(b, 4, 3, 5, 3)
    eq(res.valid, true)
    local s = res.steps[1]
    eq(s.matches[1].shape, "cross"); eq(s.matches[1].length, 5)
    eq(s.created[1].special, "volatile"); eq(s.created[1].color, 1)
    eq(s.created[1].r, 5); eq(s.created[1].c, 3)
    eq(s.score, 50 + 50)
    checkScores(res)
end)

test("T shape makes volatile", function()
    local b = build(ov({ [4] = ".1......", [5] = "1.1.....", [6] = ".1......", [7] = ".1......" }))
    local res = Core.TrySwap(b, 4, 2, 5, 2)
    eq(res.valid, true)
    local s = res.steps[1]
    eq(s.matches[1].shape, "cross")
    eq(s.created[1].special, "volatile")
    eq(s.created[1].r, 5); eq(s.created[1].c, 2)
    checkScores(res)
end)

test("lineH clears its row", function()
    local b = build(ov({ [5] = "..1.....", [6] = "..1.....", [7] = "...1...." }), { ["5,3"] = "lineH" })
    local res = Core.TrySwap(b, 7, 3, 7, 4)
    eq(res.valid, true)
    local s = res.steps[1]
    eq(#s.cleared, 10)
    eq(#s.triggered, 1)
    eq(s.triggered[1].special, "lineH")
    local n = 0
    for _, c in ipairs(s.cleared) do if c.r == 5 then n = n + 1 end end
    eq(n, 8)
    checkScores(res)
end)

test("lineV clears its column", function()
    local b = build(ov({ [5] = "..11....", [6] = ".....1.." }), { ["5,3"] = "lineV" })
    local res = Core.TrySwap(b, 6, 6, 5, 6)
    -- 1 flyttes opp i (5,6): rad 5 = 1 1 . . . 1 -> ikke match. Bruk (6,5) i stedet:
    eq(res.valid, false)
    b = build(ov({ [5] = "..11....", [6] = "....1..." }), { ["5,3"] = "lineV" })
    res = Core.TrySwap(b, 6, 5, 5, 5)
    eq(res.valid, true)
    local s = res.steps[1]
    eq(#s.cleared, 10)
    local n = 0
    for _, c in ipairs(s.cleared) do if c.c == 3 then n = n + 1 end end
    eq(n, 8)
    checkScores(res)
end)

test("volatile clears 3x3", function()
    local b = build(ov({ [5] = "..1.....", [6] = "..1.....", [7] = "...1...." }), { ["5,3"] = "volatile" })
    local res = Core.TrySwap(b, 7, 3, 7, 4)
    eq(res.valid, true)
    eq(#res.steps[1].cleared, 10)
    checkScores(res)
end)

test("chain reaction of specials in one step", function()
    local b = build(ov({ [5] = "..1.....", [6] = "..1.....", [7] = "...1...." }),
        { ["5,3"] = "lineH", ["5,7"] = "volatile" })
    local res = Core.TrySwap(b, 7, 3, 7, 4)
    eq(res.valid, true)
    local s = res.steps[1]
    eq(#s.triggered, 2)
    eq(#s.cleared, 16)
    checkScores(res)
end)

test("prism cleared by special fires random color", function()
    local b = build(ov({ [5] = "..1....P", [6] = "..1.....", [7] = "...1...." }), { ["5,3"] = "lineH" })
    local res = Core.TrySwap(b, 7, 3, 7, 4)
    eq(res.valid, true)
    local s = res.steps[1]
    eq(#s.triggered, 2)
    truthy(#s.cleared > 11)
    checkScores(res)
end)

test("prism + color", function()
    local b = build(ov({ [5] = "..P....." }))
    local target = b.cells[5][4].color
    local count = 0
    for r = 1, 8 do for c = 1, 8 do if b.cells[r][c].color == target then count = count + 1 end end end
    local res = Core.TrySwap(b, 5, 3, 5, 4)
    eq(res.valid, true)
    eq(#res.steps[1].cleared, count + 1)
    eq(res.steps[1].score, (count + 1) * 10)
    -- prisme mot prisme-side fungerer også motsatt vei
    local b2 = build(ov({ [5] = "..P....." }))
    eq(Core.TrySwap(b2, 5, 4, 5, 3).valid, true)
end)

test("prism + special of color X fires specials", function()
    local b = build(ov({ [5] = "..P1....", [2] = "1......." }), { ["5,4"] = "lineH" })
    local res = Core.TrySwap(b, 5, 3, 5, 4)
    eq(res.valid, true)
    local s = res.steps[1]
    eq(#s.triggered, 1)
    truthy(#s.cleared >= 8)
    checkScores(res)
end)

test("prism + prism clears board", function()
    local b = build(ov({ [5] = "..PP...." }))
    local res = Core.TrySwap(b, 5, 3, 5, 4)
    eq(res.valid, true)
    eq(#res.steps[1].cleared, 64)
    eq(res.steps[1].score, 640)
    eq(res.steps[1].doublePrism, true)
    eq(#res.steps[1].spawns, 64)
    boardOk(b)
end)

test("cascade chain index and multiplier", function()
    -- vertikal 1-match i kolonne 3 rad 6-8; X (farge 2) i (5,3) faller 3 ned og møter 2 2 på rad 8
    local b = build(ov({
        [5] = "..2.....",
        [6] = "..3.....",
        [7] = "..1.....",
        [8] = "221.....",
    }))
    -- (6,3) er 3, (6,4) skal være 1 for bytte
    b.cells[6][4].color = 1
    truthy(not Core.HasMatches(b))
    local res = Core.TrySwap(b, 6, 3, 6, 4)
    eq(res.valid, true)
    truthy(res.chain >= 2)
    eq(res.steps[1].chain, 1)
    eq(res.steps[2].chain, 2)
    eq(res.steps[1].score, 30)
    eq(res.steps[2].score % 2, 0)
    eq(res.steps[2].matches[1].color, 2)
    checkScores(res)
    boardOk(b)
end)

test("shuffle when no moves remain", function()
    local b = Core.NewBoard(3)
    for r = 1, 8 do for c = 1, 8 do b.cells[r][c].color = ((r + c) % 7) + 1 end end
    truthy(not Core.HasMatches(b)); truthy(not Core.HasMoves(b))
    local ids = {}
    for r = 1, 8 do for c = 1, 8 do ids[b.cells[r][c].id] = true end end
    b.cells[3][3].special = "volatile"
    local step = Core.Shuffle(b)
    eq(step.kind, "shuffle")
    eq(#step.moves, 64)
    local after = boardOk(b)
    for id in pairs(ids) do truthy(after[id], "id borte") end
    local sp = 0
    for r = 1, 8 do for c = 1, 8 do if b.cells[r][c].special == "volatile" then sp = sp + 1 end end end
    eq(sp, 1)
    for _, m in ipairs(step.moves) do eq(b.cells[m.r][m.c].id, m.id) end
end)

test("shuffle with stuck rng still terminates", function()
    local b = Core.NewBoard(3)
    for r = 1, 8 do for c = 1, 8 do b.cells[r][c].color = ((r + c) % 7) + 1 end end
    b.rng = { state = 1, Next = function() return 0 end, Int = function() return 1 end }
    Core.Shuffle(b)
    truthy(not Core.HasMatches(b)); truthy(Core.HasMoves(b))
end)

test("FindHint is pure and valid", function()
    local b = Core.NewBoard(11)
    local before = snapshot(b)
    local r1, c1, r2, c2 = Core.FindHint(b)
    truthy(r1)
    truthy(deepEqual(before, snapshot(b)))
    eq(Core.TrySwap(b, r1, c1, r2, c2).valid, true)
    local b2 = build(ov({ [5] = "..P....." }))
    local a, bb, c, d = Core.FindHint(b2)
    truthy(a)
end)

test("FindHint prefers an ordinary match over the prism", function()
    local b = build(ov({ [2] = "11.1....", [5] = "..P....." }))
    local r1, c1, r2, c2 = Core.FindHint(b)
    truthy(r1)
    truthy(not (r1 == 5 and c1 == 3) and not (r2 == 5 and c2 == 3), "hint should not use the prism")
    eq(Core.TrySwap(b, r1, c1, r2, c2).valid, true)
end)

test("FindHint falls back to the prism when nothing else moves", function()
    local b = Core.NewBoard(5)
    -- Rutemønster i tre farger uten trekk, med ett prisme
    for r = 1, 8 do
        for c = 1, 8 do b.cells[r][c] = { id = r * 8 + c, color = (r + 2 * c) % 3 + 1 } end
    end
    truthy(not Core.HasMoves(b), "pattern should have no moves")
    b.cells[4][4] = { id = 1000, color = 0, special = "prism" }
    local r1, c1, r2, c2 = Core.FindHint(b)
    truthy(r1)
    truthy((r1 == 4 and c1 == 4) or (r2 == 4 and c2 == 4), "hint should use the prism")
end)

----------------------------------------------------------------------
-- Lang tilfeldig spilling med invarianter
----------------------------------------------------------------------
local function checkMove(board, before, result)
    local present = {}
    for id in pairs(before) do present[id] = true end
    for _, st in ipairs(result.steps) do
        if st.kind == "clear" then
            for _, cl in ipairs(st.cleared) do
                truthy(present[cl.id], "cleared id fantes ikke")
                present[cl.id] = nil
            end
            for _, g in ipairs(st.created) do
                truthy(not present[g.id], "created id duplikat")
                present[g.id] = true
            end
            for _, f in ipairs(st.falls) do
                truthy(present[f.id], "fall på ukjent id")
                truthy(f.toR > f.fromR, "fall oppover")
            end
            for _, sp in ipairs(st.spawns) do
                truthy(not present[sp.id], "spawn id duplikat")
                truthy(sp.fromR <= 0, "spawn fromR")
                present[sp.id] = true
            end
            for _, t in ipairs(st.triggered) do truthy(t.special) end
        else
            eq(st.kind, "shuffle")
            local n = 0
            for _, m in ipairs(st.moves) do
                truthy(present[m.id]); n = n + 1
            end
            eq(n, 64)
        end
    end
    checkScores(result)
    local after = boardOk(board)
    for id in pairs(after) do truthy(present[id], "id på brettet mangler i stegene") end
    for id in pairs(present) do truthy(after[id], "id i stegene mangler på brettet") end
    return after
end

local function randomValidMove(board, rng)
    local moves = {}
    for r = 1, 8 do
        for c = 1, 8 do
            for _, d in ipairs({ { 0, 1 }, { 1, 0 } }) do
                local r2, c2 = r + d[1], c + d[2]
                if r2 <= 8 and c2 <= 8 then
                    -- tørrkjør på en kopi er dyrt; bruk hint-logikken via ekte TrySwap på kloning
                    moves[#moves + 1] = { r, c, r2, c2 }
                end
            end
        end
    end
    return moves
end

test("random play invariants", function()
    local totalMoves, shuffles, specials = 0, 0, 0
    for _, seed in ipairs({ 1, 2, 3, 12345, 99999 }) do
        local board = Core.NewBoard(seed)
        local pick = Core.NewRNG(seed + 1000)
        local before = boardOk(board)
        for i = 1, 1000 do
            local r1, c1, r2, c2
            if i % 2 == 0 then
                r1, c1, r2, c2 = Core.FindHint(board)
            else
                -- tilfeldig kandidat; fall tilbake til hint hvis ugyldig
                local m = randomValidMove(board, pick)
                local cand = m[pick:Int(#m)]
                local snap = Core.Serialize(board)
                local copy = Core.Deserialize(snap)
                if copy and Core.TrySwap(copy, cand[1], cand[2], cand[3], cand[4]).valid then
                    r1, c1, r2, c2 = cand[1], cand[2], cand[3], cand[4]
                else
                    r1, c1, r2, c2 = Core.FindHint(board)
                end
            end
            local res = Core.TrySwap(board, r1, c1, r2, c2)
            eq(res.valid, true)
            before = checkMove(board, before, res)
            totalMoves = totalMoves + 1
            if res.shuffled then shuffles = shuffles + 1 end
            for _, st in ipairs(res.steps) do specials = specials + (st.created and #st.created or 0) end
        end
        eq(board.moves, 1000)
    end
    print(string.format("  random play: %d moves, %d shuffles, %d specials created", totalMoves, shuffles, specials))
end)

----------------------------------------------------------------------
-- Serialize
----------------------------------------------------------------------
test("serialize roundtrip continues identically", function()
    local a = Core.NewBoard(77)
    for _ = 1, 30 do Core.TrySwap(a, Core.FindHint(a)) end
    local data = Core.Serialize(a)
    local b = Core.Deserialize(data)
    truthy(b)
    truthy(deepEqual(snapshot(a), snapshot(b)))
    for _ = 1, 50 do
        local ra = Core.TrySwap(a, Core.FindHint(a))
        local rb = Core.TrySwap(b, Core.FindHint(b))
        eq(ra.score, rb.score); eq(ra.chain, rb.chain)
    end
    truthy(deepEqual(snapshot(a), snapshot(b)))
end)

test("deserialize rejects garbage", function()
    eq(Core.Deserialize(nil), nil)
    eq(Core.Deserialize("x"), nil)
    eq(Core.Deserialize(5), nil)
    eq(Core.Deserialize({}), nil)
    local function fresh() return Core.Serialize(Core.NewBoard(8)) end
    local d = fresh(); d.size = 7; eq(Core.Deserialize(d), nil)
    d = fresh(); d.cells[64] = nil; eq(Core.Deserialize(d), nil)
    d = fresh(); d.cells[5][2] = 9; eq(Core.Deserialize(d), nil)
    d = fresh(); d.cells[5] = "no"; eq(Core.Deserialize(d), nil)
    d = fresh(); d.cells[5][1] = d.cells[6][1]; eq(Core.Deserialize(d), nil)
    d = fresh(); d.cells[5][3] = 4; eq(Core.Deserialize(d), nil)
    d = fresh(); d.rng = nil; eq(Core.Deserialize(d), nil)
    d = fresh(); d.rng = 0; eq(Core.Deserialize(d), nil)
    d = fresh(); d.nextId = "a"; eq(Core.Deserialize(d), nil)
    d = fresh(); d.score = nil; eq(Core.Deserialize(d), nil)
    d = fresh(); d.cells = nil; eq(Core.Deserialize(d), nil)
    d = fresh(); d.v = 2; eq(Core.Deserialize(d), nil)
    d = fresh(); d.cells[1][2] = 0/0; eq(Core.Deserialize(d), nil)
    -- treff på brettet
    d = fresh()
    for i = 1, 3 do d.cells[i][2] = 1 end
    eq(Core.Deserialize(d), nil)
end)

----------------------------------------------------------------------
-- Progression
----------------------------------------------------------------------
test("XPToNext, ranks, clamp", function()
    eq(Prog.XPToNext(1), 100)
    eq(Prog.XPToNext(2), 140)
    eq(Prog.XPToNext(59), 100 + 40 * 58)
    eq(Prog.XPToNext(60), math.huge)
    eq(Prog.Rank(1), "Novice Gemcutter"); eq(Prog.Rank(9), "Novice Gemcutter")
    eq(Prog.Rank(10), "Apprentice Gemcutter"); eq(Prog.Rank(19), "Apprentice Gemcutter")
    eq(Prog.Rank(20), "Journeyman Gemcutter"); eq(Prog.Rank(30), "Expert Gemcutter")
    eq(Prog.Rank(40), "Artisan Gemcutter"); eq(Prog.Rank(59), "Master Gemcutter")
    eq(Prog.Rank(60), "Grand Master Gemcutter")
    eq(Prog.XPForMove({ valid = true, score = 95 }), 10)
    eq(Prog.XPForMove({ valid = false }), 0)
end)

local function fakeMove(score, chain, created, extra)
    local step = { kind = "clear", chain = 1, cleared = { 1, 2, 3 }, created = created or {}, triggered = {} }
    if extra then for k, v in pairs(extra) do step[k] = v end end
    return { valid = true, score = score, chain = chain or 1, steps = { step } }
end

test("multi-level jump and max clamp", function()
    local p = Prog.NewProfile()
    local rep = Prog.AddXP(p, 100 + 140 + 180 + 5)
    eq(p.level, 4); eq(p.xp, 5)
    eq(#rep.levelUps, 3); eq(rep.levelUps[1], 2); eq(rep.levelUps[3], 4)
    Prog.AddXP(p, 10 ^ 7)
    eq(p.level, 60); eq(p.xp, 0)
    local total = p.totalXP
    Prog.AddXP(p, 500)
    eq(p.level, 60); eq(p.xp, 0); eq(p.totalXP, total + 500)
    truthy(p.achievements.level_10 and p.achievements.level_30 and p.achievements.level_60)
end)

test("RecordMove stats and xp", function()
    local p = Prog.NewProfile()
    local rep = Prog.RecordMove(p, fakeMove(95, 1), { newFlight = true })
    eq(p.stats.moves, 1); eq(p.stats.gems, 3); eq(p.stats.bestMove, 95); eq(p.stats.flights, 1)
    eq(rep.xp, 10 + 25)
    eq(#rep.achievements, 1); eq(rep.achievements[1].id, "first_match")
    local rep2 = Prog.RecordMove(p, fakeMove(30, 1), nil)
    eq(rep2.xp, 4); eq(#rep2.achievements, 0)
    eq(p.stats.flights, 1)
    local before = p.totalXP
    local none = Prog.RecordMove(p, { valid = false })
    eq(none.xp, 0); eq(p.totalXP, before)
    local b = Prog.RecordNewBoard(p)
    eq(p.stats.boards, 1); eq(b.xp, 0)
end)

test("each achievement triggers once", function()
    local p = Prog.NewProfile()
    local created = { { special = "lineH" }, { special = "volatile" }, { special = "prism" } }
    local r = Prog.RecordMove(p, fakeMove(2500, 8, created, { doublePrism = true }), { newFlight = true })
    local got = {}
    for _, d in ipairs(r.achievements) do got[d.id] = (got[d.id] or 0) + 1 end
    for _, id in ipairs({ "first_match", "chain_3", "chain_5", "chain_8", "make_line", "make_volatile",
        "make_prism", "double_prism", "move_500", "move_2000" }) do
        eq(got[id], 1, id)
    end
    eq(p.stats.specialsMade, 3); eq(p.stats.doublePrisms, 1); eq(p.stats.linesMade, 1)
    local r2 = Prog.RecordMove(p, fakeMove(2500, 8, created, { doublePrism = true }), nil)
    eq(#r2.achievements, 0)
    -- gems, flights og nivå
    p.stats.gems = 100000; p.stats.flights = 50
    local r3 = Prog.RecordMove(p, fakeMove(10, 1), nil)
    local g3 = {}
    for _, d in ipairs(r3.achievements) do g3[d.id] = true end
    for _, id in ipairs({ "gems_1k", "gems_10k", "gems_100k", "flights_10", "flights_50" }) do truthy(g3[id], id) end
    -- XP fra achievements kan utløse nivå-achievements
    truthy(p.level > 1)
    local seen = {}
    for _, d in ipairs(Prog.ACHIEVEMENTS) do
        truthy(not seen[d.id], "duplisert id"); seen[d.id] = true
        truthy(d.name and d.desc and d.xp and d.check)
    end
end)

test("level achievements fire after xp", function()
    local p = Prog.NewProfile()
    p.level = 9; p.xp = 0
    local r = Prog.RecordMove(p, fakeMove(5000, 1), nil)
    truthy(p.level >= 10)
    truthy(p.achievements.level_10)
    local has = false
    for _, d in ipairs(r.achievements) do if d.id == "level_10" then has = true end end
    truthy(has)
end)

test("Upgrade partial/old tables", function()
    local p = Prog.Upgrade({})
    eq(p.level, 1); eq(p.stats.moves, 0); truthy(type(p.achievements) == "table")
    p = Prog.Upgrade({ level = 5, stats = { moves = 7, gems = "x" }, achievements = 3 })
    eq(p.level, 5); eq(p.stats.moves, 7); eq(p.stats.gems, 0); truthy(type(p.achievements) == "table")
    eq(Prog.Upgrade(nil).level, 1)
    eq(Prog.Upgrade("junk").level, 1)
    eq(Prog.Upgrade({ level = 999 }).level, 60)
    eq(Prog.Upgrade({ level = -3, xp = -1 }).level, 1)
    local q = Prog.NewProfile(); q.stats.moves = 4
    eq(Prog.Upgrade(q).stats.moves, 4)
end)

----------------------------------------------------------------------
-- Simulering (rapport, ingen asserts)
----------------------------------------------------------------------
do
    local MOVES_PER_MIN = 10
    local profile = Prog.NewProfile()
    local board = Core.NewBoard(2024)
    local totalScore, totalXP, n = 0, 0, 0
    local reached, targets = {}, { 5, 10, 20, 30, 60 }
    local maxMoves = 40000
    while n < maxMoves and profile.level < 60 do
        local res = Core.TrySwap(board, Core.FindHint(board))
        n = n + 1
        totalScore = totalScore + res.score
        local rep = Prog.RecordMove(profile, res, nil)
        totalXP = totalXP + rep.xp
        for _, lv in ipairs(rep.levelUps) do
            if not reached[lv] then reached[lv] = n end
        end
    end
    print(string.format("Simulation: %d moves, avg score/move %.1f, avg xp/move %.2f (incl. achievements)",
        n, totalScore / n, totalXP / n))
    for _, lv in ipairs(targets) do
        local m = reached[lv]
        if m then
            print(string.format("  level %2d after %5d moves = %6.1f min (%.1f h)", lv, m, m / MOVES_PER_MIN, m / MOVES_PER_MIN / 60))
        else
            print(string.format("  level %2d not reached in %d moves", lv, n))
        end
    end
end

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
