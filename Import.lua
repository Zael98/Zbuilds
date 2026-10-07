-- Build links pasted in game: decoded offline (the link carries the whole build) and kept per account.
-- Same formats as tools/update_builds.py reads.
local _, ns = ...
local L = ns.L

local TF_CODE_VERSION = "6"
local TF_SYMS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz056789"

local function split(s, sep)
    local out, start = {}, 1
    while true do
        local i = s:find(sep, start, true)
        if not i then out[#out + 1] = s:sub(start) return out end
        out[#out + 1] = s:sub(start, i - 1)
        start = i + 1
    end
end

local function flatTalents(classData)
    local flat = {}
    for t, tree in ipairs(classData.trees) do
        for i in ipairs(tree.talents) do flat[#flat + 1] = { t, i } end
    end
    return flat
end

local function emptyRanks(classData)
    local ranks = {}
    for t, tree in ipairs(classData.trees) do
        ranks[t] = {}
        for i in ipairs(tree.talents) do ranks[t][i] = 0 end
    end
    return ranks
end

local function classFromSlug(slug)
    local token = slug:upper()
    local classData = ns.ClassData(token)
    if not classData then error(L.ERR_UNKNOWN_CLASS:format(slug), 0) end
    return token, classData
end

-- talentsforever.com/<class>/<level>/<tree1>-<tree2>-<tree3>[-legacy x3][-order]-<version>
local function decodeTalentsForever(code)
    local slug, level, body = code:match("^(%a+)/(%d+)/([%w%-]*)$")
    if not slug then error(L.ERR_TF_INVALID, 0) end
    local token, classData = classFromSlug(slug)
    local nt, parts = #classData.trees, split(body, "-")
    if not (#parts > nt and parts[#parts] == TF_CODE_VERSION) then
        error(L.ERR_TF_OLD, 0)
    end
    parts[#parts] = nil

    local ranks = emptyRanks(classData)
    for t = 1, nt do
        local seg = parts[t] or ""
        for i = 1, #seg do
            if ranks[t][i] then ranks[t][i] = tonumber(seg:sub(i, i)) or 0 end
        end
    end

    local extra = #parts - nt
    local orderSeg = (extra >= 4 and parts[nt + 4]) or (extra == 1 and parts[nt + 1]) or ""
    local flat, order, taken, k = flatTalents(classData), {}, {}, 1
    while k <= #orderSeg do
        local f = TF_SYMS:find(orderSeg:sub(k, k), 1, true)
        local spot = f and flat[f]
        if spot then
            local key = spot[1] * 100 + spot[2]
            local n = ranks[spot[1]][spot[2]] - (taken[key] or 0)
            local run = orderSeg:sub(k + 1, k + 1)
            if run:match("^[1-4]$") then
                n = math.min(n, tonumber(run))
                k = k + 1
            end
            for _ = 1, n do order[#order + 1] = { spot[1], spot[2] } end
            taken[key] = (taken[key] or 0) + math.max(n, 0)
        end
        k = k + 1
    end
    return token, classData, ranks, order, tonumber(level)
end

-- The other sites keep their own copy of the trees; the updater ships each site's symbols already
-- placed in ours (ZbuildsData.decoders.<site>[CLASS][symbol] = { tree, index }).
local function siteMap(site, token)
    local map = ZbuildsData.decoders and ZbuildsData.decoders[site] and ZbuildsData.decoders[site][token]
    if not map then error(L.ERR_LINK, 0) end
    return map
end

-- Points given one symbol each, in the order they are learned.
local function fromPoints(token, classData, map, symbols)
    local ranks, order = emptyRanks(classData), {}
    for _, key in ipairs(symbols) do
        local spot = map[key]
        if not spot then error(L.ERR_UNKNOWN_TALENT, 0) end
        ranks[spot[1]][spot[2]] = ranks[spot[1]][spot[2]] + 1
        order[#order + 1] = { spot[1], spot[2] }
    end
    return token, classData, ranks, order, nil
end

-- icy-veins.com/wow-forever/<class>-talent-calculator#tc-<one symbol per point, in order>
local function decodeIcyVeins(slug, points)
    local token, classData = classFromSlug(slug)
    local symbols = {}
    for k = 1, #points do symbols[k] = points:sub(k, k) end
    return fromPoints(token, classData, siteMap("iv", token), symbols)
end

-- warcrafttavern.com/forever/tools/talent-calculator/<class>#?t=A1111004466b: a tree letter, then a point per symbol
local function decodeTavern(slug, code)
    local token, classData = classFromSlug(slug)
    local symbols, tree = {}, nil
    for k = 1, #code do
        local ch = code:sub(k, k)
        if ch:match("[ABC]") then tree = ch elseif tree then symbols[#symbols + 1] = tree .. ch end
    end
    return fromPoints(token, classData, siteMap("tavern", token), symbols)
end

-- wowforeverbuilds.com/talents/<class>?b=<ranks per tree>&o=<order: tree digit + talent index in base 36>
local function decodeWfb(slug, query)
    local token, classData = classFromSlug(slug)
    local map = siteMap("wfb", token)
    local b, o = query:match("[?&]?b=([%d%-]*)"), query:match("[?&]o=(%w+)") or ""
    if not b then error(L.ERR_LINK, 0) end
    local total = 0
    for d in b:gmatch("%d") do total = total + tonumber(d) end
    if #o == 2 * total then
        local symbols = {}
        for k = 1, #o - 1, 2 do symbols[#symbols + 1] = o:sub(k, k) .. ":" .. tonumber(o:sub(k + 1, k + 1), 36) end
        return fromPoints(token, classData, map, symbols)
    end
    local ranks = emptyRanks(classData)
    local tree = 0
    for seg in (b .. "-"):gmatch("([%d]*)%-") do
        for i = 1, #seg do
            local rank = tonumber(seg:sub(i, i))
            if rank > 0 then
                local spot = map[tree .. ":" .. (i - 1)]
                if not spot then error(L.ERR_UNKNOWN_TALENT, 0) end
                ranks[spot[1]][spot[2]] = rank
            end
        end
        tree = tree + 1
    end
    return token, classData, ranks, {}, nil
end

-- Returns a build table, or nil, error message.
function ns.DecodeLink(url, name, category)
    url = strtrim(url or "")
    local ok, token, classData, ranks, order, level = pcall(function()
        local tf = url:match("talentsforever%.com/([^?#]+)")
        if tf then return decodeTalentsForever(tf) end
        local slug, points = url:match("wow%-forever/(%a+)%-talent%-calculator#tc%-(.+)$")
        if slug then return decodeIcyVeins(slug, points) end
        local tvSlug, tvCode = url:match("talent%-calculator/(%a+)#%?t=(%w+)")
        if tvSlug then return decodeTavern(tvSlug, tvCode) end
        local wfSlug, wfQuery = url:match("wowforeverbuilds%.com/talents/(%a+)%?(.+)$")
        if wfSlug then return decodeWfb(wfSlug, wfQuery) end
        error(L.ERR_LINK, 0)
    end)
    if not ok then return nil, token end

    local strings, points, total = {}, {}, 0
    for t, tree in ipairs(classData.trees) do
        local digits, sum = {}, 0
        for i, tal in ipairs(tree.talents) do
            if ranks[t][i] > tal.max then
                return nil, L.ERR_RANKS:format(tal.name, ranks[t][i], tal.max)
            end
            digits[i], sum = tostring(ranks[t][i]), sum + ranks[t][i]
        end
        strings[t], points[t], total = table.concat(digits), sum, total + sum
    end
    if total == 0 then return nil, L.ERR_EMPTY end

    local lead = 1
    for t = 2, #points do if points[t] > points[lead] then lead = t end end
    return {
        class = token, name = (name and name ~= "") and name or L.IMPORTED_DEFAULT, category = category,
        source = "Mis enlaces", spec = classData.trees[lead].name, url = url, level = level,
        ranks = strings, points = points, order = (#order == total) and order or nil, imported = true,
    }
end

function ns.Imports()
    ZbuildsDB = ZbuildsDB or {}
    ZbuildsDB.imports = ZbuildsDB.imports or {}
    return ZbuildsDB.imports
end

function ns.AddImport(build)
    table.insert(ns.Imports(), build)
end

function ns.RemoveImport(build)
    local list = ns.Imports()
    for i = #list, 1, -1 do
        if list[i] == build then table.remove(list, i) end
    end
end
