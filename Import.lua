-- Build links pasted in game: decoded offline (the link carries the whole build) and kept per account.
-- Same formats as tools/update_builds.py reads.
local _, ns = ...

local TF_CODE_VERSION = "6"
local TF_SYMS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz056789"
-- Icy Veins numbers the talents across the trees in grid order, the same order as our talent lists
local IV_SYMS = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-._~[]()"

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
    if not classData then error("clase desconocida: " .. slug, 0) end
    return token, classData
end

-- talentsforever.com/<class>/<level>/<tree1>-<tree2>-<tree3>[-legacy x3][-order]-<version>
local function decodeTalentsForever(code)
    local slug, level, body = code:match("^(%a+)/(%d+)/([%w%-]*)$")
    if not slug then error("enlace de Talents Forever no válido", 0) end
    local token, classData = classFromSlug(slug)
    local nt, parts = #classData.trees, split(body, "-")
    if not (#parts > nt and parts[#parts] == TF_CODE_VERSION) then
        error("enlace de una versión antigua de Talents Forever; ábrelo en la web y cópialo de nuevo", 0)
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

-- icy-veins.com/wow-forever/<class>-talent-calculator#tc-<one symbol per point, in order>
local function decodeIcyVeins(slug, points)
    local token, classData = classFromSlug(slug)
    local flat, ranks, order = flatTalents(classData), emptyRanks(classData), {}
    for k = 1, #points do
        local f = IV_SYMS:find(points:sub(k, k), 1, true)
        local spot = f and flat[f]
        if not spot then error("el enlace de Icy Veins tiene un talento desconocido", 0) end
        ranks[spot[1]][spot[2]] = ranks[spot[1]][spot[2]] + 1
        order[#order + 1] = { spot[1], spot[2] }
    end
    return token, classData, ranks, order, nil
end

-- Returns a build table, or nil, error message.
function ns.DecodeLink(url, name, category)
    url = strtrim(url or "")
    local ok, token, classData, ranks, order, level = pcall(function()
        local tf = url:match("talentsforever%.com/([^?#]+)")
        if tf then return decodeTalentsForever(tf) end
        local slug, points = url:match("wow%-forever/(%a+)%-talent%-calculator#tc%-(.+)$")
        if slug then return decodeIcyVeins(slug, points) end
        error("pega un enlace de build de talentsforever.com o de la calculadora de Icy Veins (con #tc-)", 0)
    end)
    if not ok then return nil, token end

    local strings, points, total = {}, {}, 0
    for t, tree in ipairs(classData.trees) do
        local digits, sum = {}, 0
        for i, tal in ipairs(tree.talents) do
            if ranks[t][i] > tal.max then
                return nil, ("%s tiene %d de %d rangos: el enlace es de otra versión del árbol"):format(tal.name, ranks[t][i], tal.max)
            end
            digits[i], sum = tostring(ranks[t][i]), sum + ranks[t][i]
        end
        strings[t], points[t], total = table.concat(digits), sum, total + sum
    end
    if total == 0 then return nil, "el enlace no tiene ningún punto" end

    local lead = 1
    for t = 2, #points do if points[t] > points[lead] then lead = t end end
    return {
        class = token, name = (name and name ~= "") and name or "Build importada", category = category,
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
