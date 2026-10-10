-- Legacy: the account-wide trees (Professions, Adventure, Resources) and their challenges.
-- For now only a dump of what the client exposes, to learn whether C_Traits reads those trees:
-- /zb legacy (or /zbuildslegacydump) writes it to ZbuildsDB.legacyDump and sums it up in the chat.
local _, ns = ...

-- calls an API that may be missing or may error: nil when missing, { error = "..." } when it fails
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return { error = tostring(results[2]) } end
    return unpack(results, 2, table.maxn(results))
end

local function valid(value) return value ~= nil and not (type(value) == "table" and value.error) end

local function nodeDump(configID, nodeID)
    local n = call(C_Traits.GetNodeInfo, configID, nodeID)
    if not valid(n) then return n end
    local node = {
        id = nodeID, x = n.posX, y = n.posY, type = n.type, maxRanks = n.maxRanks, currentRank = n.currentRank,
        ranksPurchased = n.ranksPurchased, activeRank = n.activeRank, isAvailable = n.isAvailable,
        isVisible = n.isVisible, canPurchaseRank = n.canPurchaseRank, conditionIDs = n.conditionIDs,
        groupIDs = n.groupIDs, edges = n.visibleEdges, entries = {},
    }
    for _, entryID in ipairs(n.entryIDs or {}) do
        local e = call(C_Traits.GetEntryInfo, configID, entryID)
        local def = valid(e) and e.definitionID and call(C_Traits.GetDefinitionInfo, e.definitionID)
        local spellID = valid(def) and def.spellID or nil
        node.entries[#node.entries + 1] = {
            id = entryID, type = valid(e) and e.type or nil, maxRanks = valid(e) and e.maxRanks or nil,
            spellID = spellID, name = spellID and call(C_Spell.GetSpellName, spellID) or nil,
            overrideName = valid(def) and def.overrideName or nil,
            description = call(C_Traits.GetTraitDescription, entryID, math.max(1, n.currentRank or 1)),
        }
    end
    return node
end

local function configDump(configID, foundBy)
    local info = call(C_Traits.GetConfigInfo, configID)
    local config = { id = configID, foundBy = foundBy, info = info, trees = {}, conditions = {} }
    for _, treeID in ipairs(valid(info) and info.treeIDs or {}) do
        local tree = {
            id = treeID, info = call(C_Traits.GetTreeInfo, configID, treeID),
            systemID = call(C_Traits.GetSystemIDByTreeID, treeID),
            currency = call(C_Traits.GetTreeCurrencyInfo, configID, treeID, false), currencyInfo = {}, nodes = {},
        }
        for _, cur in ipairs(valid(tree.currency) and tree.currency or {}) do
            if cur.traitCurrencyID then
                tree.currencyInfo[cur.traitCurrencyID] = { call(C_Traits.GetTraitCurrencyInfo, cur.traitCurrencyID) }
            end
        end
        local nodeIDs = call(C_Traits.GetTreeNodes, treeID)
        for _, nodeID in ipairs(valid(nodeIDs) and nodeIDs or {}) do
            local node = nodeDump(configID, nodeID)
            tree.nodes[#tree.nodes + 1] = node
            -- what unlocks the nodes: may name the challenges (quests, achievements, currency spent)
            for _, conditionID in ipairs(valid(node) and node.conditionIDs or {}) do
                config.conditions[conditionID] = config.conditions[conditionID] or call(C_Traits.GetConditionInfo, configID, conditionID)
            end
        end
        config.trees[#config.trees + 1] = tree
    end
    return config
end

-- Every trait config the client lets this character read, and how it was found.
local function findConfigs()
    local found = {}
    local function add(configID, how)
        if type(configID) == "number" and configID > 0 and not found[configID] then found[configID] = how end
    end
    add(call(C_ClassTalents and C_ClassTalents.GetActiveConfigID), "class talents")
    for configType = 0, 12 do
        local ids = call(C_Traits.GetConfigsByType, configType)
        for _, id in ipairs(valid(ids) and ids or {}) do add(id, "type " .. configType) end
    end
    for systemID = 1, 300 do add(call(C_Traits.GetConfigIDBySystemID, systemID), "system " .. systemID) end
    for treeID = 1, 3000 do add(call(C_Traits.GetConfigIDByTreeID, treeID), "tree " .. treeID) end
    return found
end

local API_WORDS = { "Achiev", "Legacy", "Perk", "Challenge", "Criteria", "Trait", "Progress", "Journey", "Renown", "Season" }

local function matchesWords(name)
    for _, word in ipairs(API_WORDS) do
        if name:find(word) then return true end
    end
end

-- C_ namespaces and global functions that could track the Legacy challenges.
local function findApis()
    local namespaces, functions = {}, {}
    for name, value in pairs(_G) do
        if type(name) == "string" and matchesWords(name) then
            if type(value) == "table" and name:match("^C_") then
                local keys = {}
                for key in pairs(value) do keys[#keys + 1] = tostring(key) end
                table.sort(keys)
                namespaces[name] = keys
            elseif type(value) == "function" then
                functions[#functions + 1] = name
            end
        end
    end
    table.sort(functions)
    return namespaces, functions
end

-- Achievement categories, and the achievements (with criteria) of any that looks like Legacy or challenges.
local function findAchievements()
    if not GetCategoryList then return nil end
    local out = { categories = {}, matching = {} }
    for _, categoryID in ipairs(call(GetCategoryList) or {}) do
        local name, parentID = call(GetCategoryInfo, categoryID)
        out.categories[#out.categories + 1] = { id = categoryID, name = name, parent = parentID }
        if type(name) == "string" and (name:find("Legacy") or name:find("Challenge") or name:find("Legado")
            or name:find("Desaf")) then
            local list = {}
            for k = 1, (call(GetCategoryNumAchievements, categoryID, true) or 0) do
                local id, achName, points, completed, _, _, _, description = call(GetAchievementInfo, categoryID, k)
                local criteria = {}
                for c = 1, (id and call(GetAchievementNumCriteria, id) or 0) do
                    local text, _, done, quantity, required = call(GetAchievementCriteriaInfo, id, c)
                    criteria[#criteria + 1] = { text = text, done = done, quantity = quantity, required = required }
                end
                list[#list + 1] = { id = id, name = achName, points = points, completed = completed,
                    description = description, criteria = criteria }
            end
            out.matching[name] = list
        end
    end
    return out
end

-- What the query functions (Get...) of a namespace return with no arguments: the Legacy challenges
-- may live in one of these (C_PerksActivities is the retail API for lists of challenges with progress).
local PROBED = { "C_PerksActivities", "C_PerksProgram", "C_SeasonInfo" }

local function probeNamespaces()
    local out = {}
    for _, name in ipairs(PROBED) do
        local space = _G[name]
        if type(space) == "table" then
            out[name] = {}
            for key, fn in pairs(space) do
                if type(fn) == "function" and tostring(key):match("^Get") then
                    out[name][key] = { call(fn) }
                end
            end
        end
    end
    return out
end

function ns.LegacyDump()
    local version, build, _, interface = GetBuildInfo()
    local dump = { time = date("%Y-%m-%d %H:%M:%S"), client = { version, build, interface, GetLocale() },
        level = UnitLevel("player"), class = ns.PlayerClass(), configs = {} }
    for configID, how in pairs(findConfigs()) do dump.configs[#dump.configs + 1] = configDump(configID, how) end
    dump.namespaces, dump.functions = findApis()
    dump.achievements = findAchievements()
    dump.probed = probeNamespaces()
    ZbuildsDB = ZbuildsDB or {}
    ZbuildsDB.legacyDump = dump

    ns.Print("Legacy dump")
    for _, config in ipairs(dump.configs) do
        local info = valid(config.info) and config.info or {}
        local nodes, points = 0, {}
        for _, tree in ipairs(config.trees) do
            nodes = nodes + #tree.nodes
            for _, cur in ipairs(valid(tree.currency) and tree.currency or {}) do
                points[#points + 1] = ("%s/%s"):format(tostring(cur.quantity), tostring(cur.maxQuantity))
            end
        end
        print(("   config %d (%s): type %s \"%s\", %d trees, %d nodes, points %s"):format(config.id, config.foundBy,
            tostring(info.type), tostring(info.name), #config.trees, nodes, table.concat(points, " ")))
    end
    local spaces = {}
    for name in pairs(dump.namespaces) do spaces[#spaces + 1] = name end
    table.sort(spaces)
    print("   APIs: " .. table.concat(spaces, ", "))
    local categories = dump.achievements and #dump.achievements.categories or 0
    local matching = 0
    for _ in pairs(dump.achievements and dump.achievements.matching or {}) do matching = matching + 1 end
    print(("   achievement categories: %d (%d look like Legacy/challenges)"):format(categories, matching))
    print("   Saved to ZbuildsDB.legacyDump: type /reload (or log out) so the game writes it to disk.")
end

SLASH_ZBUILDSLEGACY1 = "/zbuildslegacydump"
SlashCmdList.ZBUILDSLEGACY = function() ns.LegacyDump() end
