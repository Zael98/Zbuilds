-- Talent logic: maps the Forever trait tree onto the build data and spends points along a build.
-- Forever keeps the three classic trees as nodes of one C_Traits tree; nodes sit on a grid of
-- NODE_SPACING units, with a wide gap between the three trees.
local _, ns = ...
local L = ns.L

local NODE_SPACING = 600
local TREE_GAP = NODE_SPACING * 2

ns.PREFIX = "|cff33ff99Zbuilds|r: "

function ns.Print(msg)
    print(ns.PREFIX .. msg)
end

function ns.PlayerClass()
    return select(2, UnitClass("player"))
end

function ns.ClassData(classToken)
    return ZbuildsData and ZbuildsData.classes[classToken]
end

function ns.BuildsFor(classToken)
    local out = {}
    for _, build in ipairs(ZbuildsData and ZbuildsData.builds or {}) do
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
    build.order, build.orderEstimated = order, true
    return order
end

local function nodeSpell(configID, node)
    local entryID = node.entryIDs and node.entryIDs[1]
    local entry = entryID and C_Traits.GetEntryInfo(configID, entryID)
    local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
    return def and def.spellID
end

-- Returns { configID, treeID, node[t][i], spell[t][i], rank[t][i], mismatches, edges } or nil, error.
function ns.ReadTree(classData)
    if not (C_ClassTalents and C_Traits) then return nil, L.NO_API end
    local configID = C_ClassTalents.GetActiveConfigID()
    local config = configID and C_Traits.GetConfigInfo(configID)
    local treeID = config and config.treeIDs and config.treeIDs[1]
    if not treeID then return nil, L.NO_TREE end

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
        return nil, L.TREE_COUNT:format(#clusters, #classData.trees)
    end

    local result = { configID = configID, treeID = treeID, node = {}, spell = {}, rank = {}, mismatches = {},
        edges = {} }
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
                result.mismatches[#result.mismatches + 1] = C_Spell.GetSpellName(spell or 0) or L.NODE:format(n.ID)
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
    return { name = L.MY_TALENTS, source = "Personaje", class = ns.PlayerClass(), ranks = ranks, points = points }
end

-- The talent's spell: read from the game for your class, else the id the data carries (any class).
function ns.TalentSpell(classData, tree, t, i)
    return (tree and tree.spell[t] and tree.spell[t][i]) or classData.trees[t].talents[i].spell
end

-- The talent's name in the game's language when the game knows its spell, else the data's English name.
function ns.TalentName(classData, tree, t, i)
    local spell = ns.TalentSpell(classData, tree, t, i)
    return (spell and C_Spell.GetSpellName(spell)) or classData.trees[t].talents[i].name
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
            if tree.rank[t][i] > ns.TargetRank(build, t, i) then out[#out + 1] = ns.TalentName(classData, tree, t, i) end
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

-- The next `count` points the build wants, free points or not: { t, i, rank, level } each.
-- The ones your free points cover have no level (they can be learned now); the rest come one per
-- level from your current one.
function ns.UpcomingSteps(build, classData, tree, count)
    local free, level = ns.FreePoints(tree), UnitLevel("player")
    local out = {}
    missingSteps(build, classData, tree, function(t, i, rank)
        local k = #out + 1
        out[k] = { t = t, i = i, rank = rank, level = k > free and level + k - free or nil }
        if k >= count then return false end
    end)
    return out
end

-- Spends the free points following the build. Returns number of points learned, or nil, error.
function ns.Apply(build, classData)
    if InCombatLockdown() then return nil, L.IN_COMBAT end
    local tree, err = ns.ReadTree(classData)
    if not tree then return nil, err end
    local conflicts = ns.Conflicts(build, classData, tree)
    if #conflicts > 0 then
        return nil, L.CONFLICTS:format(table.concat(conflicts, ", "))
    end

    local bought, failure = 0, nil
    missingSteps(build, classData, tree, function(t, i)
        local nodeID = tree.node[t][i]
        if not nodeID then
            failure = L.NOT_IN_TREE:format(classData.trees[t].talents[i].name)
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
            return nil, L.REJECTED
        end
    end
    if failure then return nil, failure end
    return bought
end

-- Selected build per character, remembered by its link.
function ns.SelectedBuild(classToken)
    local url = ZbuildsCharDB and ZbuildsCharDB.selected
    for _, build in ipairs(ns.BuildsFor(classToken)) do
        if build.url == url then return build end
    end
end

function ns.Select(build)
    ZbuildsCharDB = ZbuildsCharDB or {}
    ZbuildsCharDB.selected = build and build.url
    if ns.RefreshTalentBar then ns.RefreshTalentBar() end
end

-- Loadouts: builds the character keeps at hand to rotate between on the talent window, each with
-- an optional name of its own. Saved per character as { url = link, name = custom name or nil }.
local function loadoutEntries()
    ZbuildsCharDB = ZbuildsCharDB or {}
    ZbuildsCharDB.loadouts = ZbuildsCharDB.loadouts or {}
    local entries = ZbuildsCharDB.loadouts
    for k, entry in ipairs(entries) do
        if type(entry) == "string" then entries[k] = { url = entry } end -- saved before loadouts had names
    end
    return entries
end

local function loadoutEntry(build)
    for k, entry in ipairs(loadoutEntries()) do
        if entry.url == build.url then return entry, k end
    end
end

local function changed()
    if ns.RefreshTalentBar then ns.RefreshTalentBar() end
    if ns.Refresh then ns.Refresh() end
end

function ns.Loadouts(classToken)
    local byLink = {}
    for _, build in ipairs(ns.BuildsFor(classToken)) do byLink[build.url] = byLink[build.url] or build end
    local out = {}
    for _, entry in ipairs(loadoutEntries()) do
        if byLink[entry.url] then out[#out + 1] = byLink[entry.url] end -- a build a site dropped is skipped
    end
    return out
end

function ns.IsLoadout(build)
    return loadoutEntry(build) ~= nil
end

-- The name to show: the loadout's own name when it has one, else the build's.
function ns.DisplayName(build)
    local entry = loadoutEntry(build)
    return entry and entry.name or build.name
end

-- Empty or blank names go back to the build's own name.
function ns.RenameLoadout(build, name)
    local entry = loadoutEntry(build)
    if not entry then return end
    name = strtrim(name or "")
    entry.name = name ~= "" and name or nil
    changed()
end

-- Adds the build to the loadouts or takes it out; returns whether it is one now.
function ns.ToggleLoadout(build)
    local entries = loadoutEntries()
    local _, k = loadoutEntry(build)
    if k then table.remove(entries, k) else entries[#entries + 1] = { url = build.url } end
    if ns.RefreshTalentBar then ns.RefreshTalentBar() end
    return k == nil
end

-- Selects the next (step 1) or previous (step -1) loadout after the selected build.
function ns.CycleLoadout(step)
    local classToken = ns.PlayerClass()
    local list, selected = ns.Loadouts(classToken), ns.SelectedBuild(classToken)
    if #list == 0 then return end
    local at = 0
    for k, build in ipairs(list) do if build == selected then at = k end end
    if at == 0 and step < 0 then at = 1 end
    ns.Select(list[(at - 1 + step) % #list + 1])
    if ns.Refresh then ns.Refresh() end
end

-- Learns the free points of a build and says what happened in the chat.
function ns.LearnAndReport(build, classData)
    local learned, err = ns.Apply(build, classData)
    if learned then
        ns.Print(learned > 0 and L.LEARNED_N:format(learned, build.name) or L.NOTHING_TO_LEARN)
    else
        ns.Print("|cffff5050" .. err .. "|r")
    end
end

local function announceNext()
    local classToken = ns.PlayerClass()
    local build, classData = ns.SelectedBuild(classToken), ns.ClassData(classToken)
    if not (build and classData) then return end
    local tree = ns.ReadTree(classData)
    if not tree then return end
    local t, i, rank = ns.NextStep(build, classData, tree)
    if t and ns.FreePoints(tree) > 0 then
        ns.Print(L.NEXT_ANNOUNCE:format(build.name, ns.TalentName(classData, tree, t, i), rank))
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
    if ns.RefreshTalentBar then ns.RefreshTalentBar() end
end)

-- /zb diag: what this client lets the addon do, to check a new game build quickly.
local function diagnose()
    local lines = {}
    local function add(label, value) lines[#lines + 1] = ("%s: |cffffffff%s|r"):format(label, tostring(value)) end
    local version, build, _, interface = GetBuildInfo()
    add("Client", ("%s (%s), interface %s, %s"):format(version, build, interface, GetLocale()))
    add("Data", ZbuildsData and ZbuildsData.generated or "missing")
    for _, fn in ipairs({ "PurchaseRank", "CommitConfig", "RollbackConfig", "GetNodeInfo" }) do
        add("C_Traits." .. fn, C_Traits and C_Traits[fn] and "yes" or "NO")
    end
    local classData = ns.ClassData(ns.PlayerClass())
    if classData then
        local tree, err = ns.ReadTree(classData)
        if tree then
            local mapped, total = 0, 0
            for t, data in ipairs(classData.trees) do
                for i in ipairs(data.talents) do
                    total = total + 1
                    if tree.node[t][i] then mapped = mapped + 1 end
                end
            end
            add("Talent tree", ("%d/%d talents found, %d outdated, %d free points"):format(mapped, total,
                #tree.mismatches, ns.FreePoints(tree)))
        else
            add("Talent tree", err)
        end
        add("Builds for your class", #ns.BuildsFor(ns.PlayerClass()))
    end
    ns.Print("diagnostics")
    for _, line in ipairs(lines) do print("   " .. line) end
end

SLASH_ZBUILDS1 = "/zb"
SLASH_ZBUILDS2 = "/zbuilds"
SlashCmdList.ZBUILDS = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "diag" then
        diagnose()
    elseif msg == "legacy" then
        ns.LegacyDump()
    elseif msg == "trainer" then
        ns.TrainerReminder(true)
    elseif msg == "trainerdump" then
        ns.TrainerDump()
    elseif msg == "minimap" then
        ns.ToggleMinimapButton()
    else
        ns.Toggle()
    end
end
