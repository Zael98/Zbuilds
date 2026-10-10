-- Legacy: the account-wide trees (Professions, Adventure, Resources) and their challenges.
-- For now only a dump of what the client exposes, to learn whether C_Traits reads those trees:
-- /zb legacy (or /zbuildslegacydump) writes it to ZbuildsDB.legacyDump and sums it up in the chat.
local _, ns = ...

-- The Legacy trees' grid in the game data (see /zb legacy): perks sit NODE_STEP apart from the origin.
local ORIGIN_X, ORIGIN_Y, NODE_STEP = 2400, 1050, 750

function ns.LegacyData()
    return ZbuildsData and ZbuildsData.legacy
end

function ns.PlanRank(plan, t, i)
    return tonumber(plan.ranks[t]:sub(i, i)) or 0
end

-- The character's Legacy as the game has it: { configID, available, spent, rank[t][i], node[t][i], spell[t][i] },
-- or nil, error. Nodes are matched to the data's perks by grid position, so it works in any client language.
function ns.ReadLegacy(data)
    if not (C_Traits and C_Traits.GetConfigIDByTreeID) then return nil, ns.L.NO_API end
    local configID = C_Traits.GetConfigIDByTreeID(data.trees[1].id)
    if not configID then return nil, ns.L.LEGACY_LOCKED end
    local result = { configID = configID, rank = {}, node = {}, spell = {}, spent = 0 }
    for t, tree in ipairs(data.trees) do
        local byPos = {}
        for i, perk in ipairs(tree.perks) do byPos[perk.row * 10 + perk.col] = i end
        result.rank[t], result.node[t], result.spell[t] = {}, {}, {}
        for i in ipairs(tree.perks) do result.rank[t][i] = 0 end
        for _, nodeID in ipairs(C_Traits.GetTreeNodes(tree.id) or {}) do
            local n = C_Traits.GetNodeInfo(configID, nodeID)
            local i = n and n.posX and byPos[(floor((n.posY - ORIGIN_Y) / NODE_STEP + 0.5) + 1) * 10
                + floor((n.posX - ORIGIN_X) / NODE_STEP + 0.5) + 1]
            if i then
                local entry = n.entryIDs and n.entryIDs[1] and C_Traits.GetEntryInfo(configID, n.entryIDs[1])
                local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
                result.rank[t][i], result.node[t][i] = n.currentRank or 0, nodeID
                result.spell[t][i] = def and def.spellID
                result.spent = result.spent + (n.ranksPurchased or 0)
            end
        end
    end
    local currency = C_Traits.GetTreeCurrencyInfo(configID, data.trees[1].id, false)
    result.available = currency and currency[1] and currency[1].quantity or 0
    return result
end

-- The plan's first point the character does not have yet: t, i, rank (nil when the plan is complete).
function ns.NextLegacyStep(plan, legacy)
    local seen = {}
    for _, step in ipairs(plan.order) do
        local t, i = step[1], step[2]
        seen[t * 100 + i] = (seen[t * 100 + i] or 0) + 1
        if seen[t * 100 + i] > legacy.rank[t][i] then return t, i, seen[t * 100 + i] end
    end
end

-- The Legacy challenges: account achievements whose reward is a Legacy point (found with /zb legacy).
-- Achievement ids do not change with the client's language. Each gets a difficulty from 1 (easy) to 5.
local CHALLENGES = {
    -- level 25 on a class / 150 in a craft / honor rank 3 / the beta
    [61502] = 1, [61989] = 1, [61994] = 1, [61997] = 1, [62000] = 1, [62003] = 1, [62006] = 1, [62009] = 1, [61499] = 1,
    [62012] = 1, [62015] = 1, [62018] = 1, [62021] = 1, [62024] = 1, [62028] = 1, [62041] = 1, [64283] = 1,
    -- level 45 / 225 skill / Field of Honor week 4 / first dungeons
    [61503] = 2, [61992] = 2, [61995] = 2, [61998] = 2, [62001] = 2, [62004] = 2, [62007] = 2, [62010] = 2, [61500] = 2,
    [62013] = 2, [62016] = 2, [62019] = 2, [62022] = 2, [62025] = 2, [62029] = 2, [63340] = 2, [62031] = 2,
    -- level 60 / 300 skill / rank 7 / week 7 / more dungeons / Onyxia
    [61504] = 3, [61993] = 3, [61996] = 3, [61999] = 3, [62002] = 3, [62005] = 3, [62008] = 3, [62011] = 3, [61501] = 3,
    [62014] = 3, [62017] = 3, [62020] = 3, [62023] = 3, [62026] = 3, [62030] = 3, [62042] = 3, [63341] = 3, [62032] = 3,
    [684] = 3,
    -- rank 10 / week 10 / the last dungeons / exalted with the battlegrounds / raids / Valthalak / Explorer
    [62043] = 4, [63342] = 4, [62033] = 4, [62046] = 4, [62047] = 4, [62048] = 4, [62049] = 4, [62034] = 4, [62035] = 4,
    [62054] = 4, [62382] = 4,
    -- honor ranks 13 and 14
    [62044] = 5, [62045] = 5,
}

-- Reaching a level on a class: progress comes from your level when you play that class.
local CLASS_LEVELS = {
    [61502] = { "DRUID", 25 }, [61503] = { "DRUID", 45 }, [61504] = { "DRUID", 60 },
    [61989] = { "HUNTER", 25 }, [61992] = { "HUNTER", 45 }, [61993] = { "HUNTER", 60 },
    [61994] = { "MAGE", 25 }, [61995] = { "MAGE", 45 }, [61996] = { "MAGE", 60 },
    [61997] = { "PALADIN", 25 }, [61998] = { "PALADIN", 45 }, [61999] = { "PALADIN", 60 },
    [62000] = { "PRIEST", 25 }, [62001] = { "PRIEST", 45 }, [62002] = { "PRIEST", 60 },
    [62003] = { "ROGUE", 25 }, [62004] = { "ROGUE", 45 }, [62005] = { "ROGUE", 60 },
    [62006] = { "SHAMAN", 25 }, [62007] = { "SHAMAN", 45 }, [62008] = { "SHAMAN", 60 },
    [62009] = { "WARLOCK", 25 }, [62010] = { "WARLOCK", 45 }, [62011] = { "WARLOCK", 60 },
    [61499] = { "WARRIOR", 25 }, [61500] = { "WARRIOR", 45 }, [61501] = { "WARRIOR", 60 },
}

-- How far along a challenge is: fraction 0..1 and a short text ("10/25", "3/8").
local function progress(id, completed)
    if completed then return 1, "" end
    local class = CLASS_LEVELS[id]
    if class then
        if class[1] ~= ns.PlayerClass() then return 0, "" end
        local level = UnitLevel("player")
        return math.min(1, level / class[2]), ("%d/%d"):format(level, class[2])
    end
    local count = GetAchievementNumCriteria and GetAchievementNumCriteria(id) or 0
    if count == 1 then
        local _, _, done, quantity, required = GetAchievementCriteriaInfo(id, 1)
        if required and required > 1 then
            return math.min(1, (quantity or 0) / required), ("%d/%d"):format(quantity or 0, required)
        end
        return done and 1 or 0, ""
    end
    local done = 0
    for c = 1, count do
        if select(3, GetAchievementCriteriaInfo(id, c)) then done = done + 1 end
    end
    if count == 0 then return 0, "" end
    return done / count, ("%d/%d"):format(done, count)
end

-- Every challenge as the game has it now: { id, name, description, icon, completed, tier, progress, progressText },
-- pending ones first, easiest and most advanced first; then the completed ones.
function ns.LegacyChallenges()
    local list = {}
    for id, tier in pairs(CHALLENGES) do
        local ok, _, name, _, completed, _, _, _, description, _, icon = pcall(GetAchievementInfo, id)
        if ok and name then
            local fraction, text = progress(id, completed == true)
            list[#list + 1] = { id = id, name = name, description = description, icon = icon, completed = completed == true,
                tier = tier, progress = fraction, progressText = text }
        end
    end
    table.sort(list, function(a, b)
        if a.completed ~= b.completed then return b.completed end
        if a.tier ~= b.tier then return a.tier < b.tier end
        if a.progress ~= b.progress then return a.progress > b.progress end
        return a.id < b.id
    end)
    return list
end

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

-- Every achievement of every category, with its reward text: the Legacy challenges may be achievements
-- spread over categories like Adventure or Tradeskills whose reward is a Legacy point.
local function achievementDump(categoryID, k)
    local id, name, points, completed, _, _, _, description, flags, _, rewardText = call(GetAchievementInfo, categoryID, k)
    if type(id) ~= "number" then return nil end
    local criteria = {}
    for c = 1, (call(GetAchievementNumCriteria, id) or 0) do
        local text, _, done, quantity, required = call(GetAchievementCriteriaInfo, id, c)
        criteria[#criteria + 1] = { text = text, done = done, quantity = quantity, required = required }
    end
    return { id = id, name = name, points = points, completed = completed, description = description, flags = flags,
        reward = rewardText, criteria = criteria }
end

local function findAchievements()
    if not GetCategoryList then return nil end
    local out = { categories = {} }
    for _, categoryID in ipairs(call(GetCategoryList) or {}) do
        local name, parentID = call(GetCategoryInfo, categoryID)
        local category = { id = categoryID, name = name, parent = parentID, achievements = {} }
        local count = call(GetCategoryNumAchievements, categoryID, true)
        for k = 1, (type(count) == "number" and count or 0) do
            category.achievements[#category.achievements + 1] = achievementDump(categoryID, k)
        end
        out.categories[#out.categories + 1] = category
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
    local categories, total, rewarded = 0, 0, 0
    for _, category in ipairs(dump.achievements and dump.achievements.categories or {}) do
        categories = categories + 1
        for _, a in ipairs(category.achievements) do
            total = total + 1
            if type(a.reward) == "string" and a.reward ~= "" then rewarded = rewarded + 1 end
        end
    end
    print(("   achievements: %d in %d categories, %d with a reward text"):format(total, categories, rewarded))
    print("   Saved to ZbuildsDB.legacyDump: type /reload (or log out) so the game writes it to disk.")
end

-- keep the challenge list current while the Legacy view is open; Forever errors on unknown events,
-- so each one is checked before it is registered
local events = CreateFrame("Frame")
for _, event in ipairs({ "ACHIEVEMENT_EARNED", "CRITERIA_UPDATE", "TRAIT_CONFIG_UPDATED" }) do
    if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(event) then
        events:RegisterEvent(event)
    end
end
events:SetScript("OnEvent", function()
    if ns.RefreshLegacy then ns.RefreshLegacy() end
end)

SLASH_ZBUILDSLEGACY1 = "/zbuildslegacydump"
SlashCmdList.ZBUILDSLEGACY = function() ns.LegacyDump() end
