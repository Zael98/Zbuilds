-- Talent logic: maps the Forever trait tree onto the build data and spends points along a build.
-- Forever keeps the three classic trees as nodes of one C_Traits tree; nodes sit on a grid of
-- NODE_SPACING units, with a wide gap between the three trees.
local _, ns = ...

local NODE_SPACING = 600
local TREE_GAP = NODE_SPACING * 2

ns.PREFIX = "|cff33ff99ForeverBuilds|r: "

function ns.Print(msg)
    print(ns.PREFIX .. msg)
end

function ns.PlayerClass()
    return select(2, UnitClass("player"))
end

function ns.ClassData(classToken)
    return ForeverBuildsData and ForeverBuildsData.classes[classToken]
end

function ns.BuildsFor(classToken)
    local out = {}
    for _, build in ipairs(ForeverBuildsData and ForeverBuildsData.builds or {}) do
        if build.class == classToken then out[#out + 1] = build end
    end
    for _, build in ipairs(ns.Imports()) do -- links pasted in game
        if build.class == classToken then out[#out + 1] = build end
    end
    return out
end

function ns.TargetRank(build, tree, index)
    return tonumber(build.ranks[tree]:sub(index, index)) or 0
end

-- The build's point order, or one derived from its ranks: main tree first, then row by row,
-- which always satisfies the 5-points-per-row rule because the final build does.
function ns.Order(build, classData)
    if build.order then return build.order end
    local trees = {}
    for t = 1, #classData.trees do trees[t] = t end
    table.sort(trees, function(a, b) return build.points[a] > build.points[b] end)
    local order = {}
    for _, t in ipairs(trees) do
        local talents = {}
        for i in ipairs(classData.trees[t].talents) do talents[#talents + 1] = i end
        table.sort(talents, function(a, b)
            local ta, tb = classData.trees[t].talents[a], classData.trees[t].talents[b]
            if ta.row ~= tb.row then return ta.row < tb.row end
            return ta.col < tb.col
        end)
        for _, i in ipairs(talents) do
            for _ = 1, ns.TargetRank(build, t, i) do order[#order + 1] = { t, i } end
        end
    end
    build.order = order
    return order
end

local function nodeSpell(configID, node)
    local entryID = node.entryIDs and node.entryIDs[1]
    local entry = entryID and C_Traits.GetEntryInfo(configID, entryID)
    local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
    return def and def.spellID
end

-- Returns { configID, treeID, node[t][i], spell[t][i], rank[t][i], mismatches } or nil, error.
function ns.ReadTree(classData)
    if not (C_ClassTalents and C_Traits) then return nil, "este cliente no tiene la API de talentos C_Traits" end
    local configID = C_ClassTalents.GetActiveConfigID()
    local config = configID and C_Traits.GetConfigInfo(configID)
    local treeID = config and config.treeIDs and config.treeIDs[1]
    if not treeID then return nil, "no hay árbol de talentos activo (¿nivel < 10?)" end

    local nodes = {}
    for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID)) do
        local n = C_Traits.GetNodeInfo(configID, nodeID)
        if n and n.isVisible ~= false and (n.maxRanks or 0) > 0 and n.entryIDs and #n.entryIDs > 0 then
            nodes[#nodes + 1] = n
        end
    end
    table.sort(nodes, function(a, b) return a.posX < b.posX end)

    local clusters, last = {}, nil
    for _, n in ipairs(nodes) do
        if not last or n.posX - last > TREE_GAP then clusters[#clusters + 1] = {} end
        table.insert(clusters[#clusters], n)
        last = n.posX
    end
    if #clusters ~= #classData.trees then
        return nil, ("el juego tiene %d árboles y los datos %d; actualiza Data.lua"):format(#clusters, #classData.trees)
    end

    local result = { configID = configID, treeID = treeID, node = {}, spell = {}, rank = {}, mismatches = {}, edges = {} }
    local where, nodeEdges = {}, {}
    for t, cluster in ipairs(clusters) do
        local talents = classData.trees[t].talents
        local byPos, minRow, minCol = {}, math.huge, math.huge
        for i, tal in ipairs(talents) do
            byPos[tal.row * 100 + tal.col] = i
            minRow, minCol = math.min(minRow, tal.row), math.min(minCol, tal.col)
        end
        local minX, minY = math.huge, math.huge
        for _, n in ipairs(cluster) do minX, minY = math.min(minX, n.posX), math.min(minY, n.posY) end

        result.node[t], result.spell[t], result.rank[t] = {}, {}, {}
        for i in ipairs(talents) do result.rank[t][i] = 0 end
        for _, n in ipairs(cluster) do
            local row = floor((n.posY - minY) / NODE_SPACING + 0.5) + minRow
            local col = floor((n.posX - minX) / NODE_SPACING + 0.5) + minCol
            local i = byPos[row * 100 + col]
            local spell = nodeSpell(configID, n)
            if i then
                result.node[t][i] = n.ID
                result.spell[t][i] = spell
                result.rank[t][i] = n.currentRank or 0
                where[n.ID] = { t, i }
                nodeEdges[n.ID] = n.visibleEdges
            end
            -- a talent the site data places elsewhere or with other ranks: the data lags a game patch
            if not i or talents[i].max ~= n.maxRanks then
                result.mismatches[#result.mismatches + 1] = C_Spell.GetSpellName(spell or 0) or ("nodo " .. n.ID)
            end
        end
    end
    -- prerequisite arrows, as { fromTree, fromIndex, toTree, toIndex }
    for nodeID, edges in pairs(nodeEdges) do
        for _, edge in ipairs(edges or {}) do
            local from, to = where[nodeID], where[edge.targetNode]
            if from and to then result.edges[#result.edges + 1] = { from[1], from[2], to[1], to[2] } end
        end
    end
    return result
end

-- The character's current talents in build form, for comparing.
function ns.CurrentAsBuild(classData, tree)
    local ranks, points = {}, {}
    for t, data in ipairs(classData.trees) do
        local digits, sum = {}, 0
        for i in ipairs(data.talents) do
            digits[i] = tostring(tree.rank[t][i])
            sum = sum + tree.rank[t][i]
        end
        ranks[t], points[t] = table.concat(digits), sum
    end
    return { name = "Mi reparto actual", source = "Personaje", class = ns.PlayerClass(), ranks = ranks, points = points }
end

function ns.FreePoints(tree)
    local info = C_Traits.GetTreeCurrencyInfo(tree.configID, tree.treeID, false)
    return info and info[1] and info[1].quantity or 0
end

-- Talents where the character already has more points than the build wants.
function ns.Conflicts(build, classData, tree)
    local out = {}
    for t, data in ipairs(classData.trees) do
        for i, tal in ipairs(data.talents) do
            if tree.rank[t][i] > ns.TargetRank(build, t, i) then out[#out + 1] = tal.name end
        end
    end
    return out
end

-- Walks the build order against the current ranks; calls visit(t, i, rank) for each missing point.
local function missingSteps(build, classData, tree, visit)
    local seen = {}
    for _, step in ipairs(ns.Order(build, classData)) do
        local t, i = step[1], step[2]
        local key = t * 100 + i
        seen[key] = (seen[key] or 0) + 1
        if seen[key] > tree.rank[t][i] and visit(t, i, seen[key]) == false then return end
    end
end

-- First point of the build the character does not have yet: t, i, rank (or nil when complete).
function ns.NextStep(build, classData, tree)
    local nt, ni, nr
    missingSteps(build, classData, tree, function(t, i, rank)
        nt, ni, nr = t, i, rank
        return false
    end)
    return nt, ni, nr
end

-- Spends the free points following the build. Returns number of points learned, or nil, error.
function ns.Apply(build, classData)
    if InCombatLockdown() then return nil, "no se puede en combate" end
    local tree, err = ns.ReadTree(classData)
    if not tree then return nil, err end
    local conflicts = ns.Conflicts(build, classData, tree)
    if #conflicts > 0 then
        return nil, "tienes puntos que esta build no usa (" .. table.concat(conflicts, ", ") .. "). Reinicia los talentos primero."
    end

    local bought, failure = 0, nil
    missingSteps(build, classData, tree, function(t, i)
        local nodeID = tree.node[t][i]
        if not nodeID then
            failure = classData.trees[t].talents[i].name .. " no existe en el árbol del juego"
            return false
        end
        if not C_Traits.PurchaseRank(tree.configID, nodeID) then return false end -- out of points
        bought = bought + 1
    end)

    if bought > 0 then
        local committed = C_Traits.CommitConfig(tree.configID)
        if not committed and C_ClassTalents.CommitConfig then committed = C_ClassTalents.CommitConfig() end
        if not committed then
            C_Traits.RollbackConfig(tree.configID)
            return nil, "el juego rechazó los cambios"
        end
    end
    if failure then return nil, failure end
    return bought
end

-- Selected build per character, remembered by its link.
function ns.SelectedBuild(classToken)
    local url = ForeverBuildsCharDB and ForeverBuildsCharDB.selected
    for _, build in ipairs(ns.BuildsFor(classToken)) do
        if build.url == url then return build end
    end
end

function ns.Select(build)
    ForeverBuildsCharDB = ForeverBuildsCharDB or {}
    ForeverBuildsCharDB.selected = build and build.url
end

local function announceNext()
    local classToken = ns.PlayerClass()
    local build, classData = ns.SelectedBuild(classToken), ns.ClassData(classToken)
    if not (build and classData) then return end
    local tree = ns.ReadTree(classData)
    if not tree then return end
    local t, i, rank = ns.NextStep(build, classData, tree)
    if t and ns.FreePoints(tree) > 0 then
        ns.Print(("siguiente talento de \"%s\": |cffffd100%s|r (rango %d). Escribe /fb para aplicarlo.")
            :format(build.name, classData.trees[t].talents[i].name, rank))
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("TRAIT_CONFIG_UPDATED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LEVEL_UP" then
        C_Timer.After(1, announceNext) -- the new point shows up a moment after the event
    end
    if ns.Refresh then ns.Refresh() end
end)

SLASH_FOREVERBUILDS1 = "/fb"
SLASH_FOREVERBUILDS2 = "/foreverbuilds"
SlashCmdList.FOREVERBUILDS = function()
    ns.Toggle()
end
