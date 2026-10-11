local out = {}
PRINTED = {}
print = function(...) local t = {} for k = 1, select("#", ...) do t[#t+1] = tostring(select(k, ...)) end PRINTED[#PRINTED+1] = table.concat(t, " ") end
GetBuildInfo = function() return "1.60.1", "70205", "", 16001 end
date = os.date
-- a made-up Legacy config: 3 trees, one node each, 4 of 16 points, a node gated by an achievement
local LEGACY = 500
local legacyNodes = { [9001] = { ID = 9001, posX = 0, posY = 0, maxRanks = 3, currentRank = 1, ranksPurchased = 1, entryIDs = { 7001 }, conditionIDs = { 61 } },
  [9002] = { ID = 9002, posX = 600, posY = 0, maxRanks = 1, currentRank = 0, ranksPurchased = 0, entryIDs = { 7002 }, conditionIDs = {} },
  [9003] = { ID = 9003, posX = 1200, posY = 0, maxRanks = 2, currentRank = 0, ranksPurchased = 0, entryIDs = { 7003 }, conditionIDs = {} } }
local classNode = C_Traits.GetNodeInfo
C_Traits.GetNodeInfo = function(cfg, id) if cfg == LEGACY then return legacyNodes[id] end return classNode(cfg, id) end
local classEntry, classDef = C_Traits.GetEntryInfo, C_Traits.GetDefinitionInfo
C_Traits.GetEntryInfo = function(cfg, id) if cfg == LEGACY then return { definitionID = id, maxRanks = 3, type = 1 } end return classEntry(cfg, id) end
C_Traits.GetDefinitionInfo = function(id) if id >= 7000 and id < 7100 then return { spellID = 999000 + id - 7000, overrideName = "Legacy perk " .. (id - 7000) } end return classDef(id) end
C_Traits.GetConfigsByType = function(t) if t == 3 then return { LEGACY } end return {} end
C_Traits.GetConfigIDBySystemID = function(id) if id == 42 then return LEGACY end end
C_Traits.GetConfigIDByTreeID = function(id) if id >= 2001 and id <= 2003 then return LEGACY end end
local classConfig = C_Traits.GetConfigInfo
C_Traits.GetConfigInfo = function(cfg) if cfg == LEGACY then return { ID = LEGACY, type = 3, name = "Legacy", treeIDs = { 2001, 2002, 2003 } } end return classConfig(cfg) end
local classTreeNodes = C_Traits.GetTreeNodes
C_Traits.GetTreeNodes = function(tree) if tree == 2001 then return { 9001 } elseif tree == 2002 then return { 9002 } elseif tree == 2003 then return { 9003 } end return classTreeNodes(tree) end
C_Traits.GetTreeCurrencyInfo = function(cfg, tree) if cfg == LEGACY then return { { traitCurrencyID = 77, quantity = 12, maxQuantity = 16, spent = 4 } } end return { { quantity = FREE } } end
C_Traits.GetTraitCurrencyInfo = function(id) return 5, "Interface\Icons\legacy", 16 end
C_Traits.GetConditionInfo = function(cfg, id) return { achievementID = 123456, isMet = false, tooltipText = "Complete a Legacy challenge" } end
C_Traits.GetSystemIDByTreeID = function(tree) return 42 end
C_Traits.GetTreeInfo = function(cfg, tree) return { ID = tree, gates = {} } end
C_Traits.GetTraitDescription = function(entry, rank) return "Perk " .. entry .. " rank " .. rank end
-- an error in one API must not stop the dump
C_LegacyProgress = { GetChallenges = function() end, GetPoints = function() end }
C_PerksActivities = { GetPerksActivitiesInfo = function() return { activities = { { ID = 1, activityName = 'Explore', completed = true } } } end, GetBroken = function() error('needs args') end, SetTracked = function() error('must not be called') end }
GetCategoryList = function() return { 1, 2 } end
GetCategoryInfo = function(id) if id == 1 then return "Quests", -1 else return "Legacy Challenges", -1 end end
GetCategoryNumAchievements = function(id) return id == 2 and 2 or 5 end
GetAchievementInfo = function(cat, k) return 100 * cat + k, "Challenge " .. k, 1, k == 1, nil, nil, nil, "Do thing " .. k, 0, nil, cat == 2 and "Reward: 1 Legacy Point" or "" end
GetAchievementNumCriteria = function(id) return 1 end
GetAchievementCriteriaInfo = function(id, c) error("criteria API broken") end

SlashCmdList.ZBUILDS("legacy")
for _, l in ipairs(PRINTED) do out[#out+1] = l:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
local d = ZbuildsDB.legacyDump
local legacy for _, c in ipairs(d.configs) do if c.id == LEGACY then legacy = c end end
out[#out+1] = ("dump: %d configs | legacy found by '%s' | trees %d | node 9001 rank %s/%s entry '%s' desc '%s' | condition achievement %s met=%s")
  :format(#d.configs, legacy.foundBy, #legacy.trees, legacy.trees[1].nodes[1].currentRank, legacy.trees[1].nodes[1].maxRanks,
    legacy.trees[1].nodes[1].entries[1].overrideName, legacy.trees[1].nodes[1].entries[1].description,
    legacy.conditions[61].achievementID, tostring(legacy.conditions[61].isMet))
local cat2 = d.achievements.categories[2]
out[#out+1] = ("achievements: %d categories, '%s' -> %d, first reward '%s', criteria error kept: %s")
  :format(#d.achievements.categories, cat2.name, #cat2.achievements, tostring(cat2.achievements[1].reward), tostring(cat2.achievements[1].criteria[1].text and cat2.achievements[1].criteria[1].text.error ~= nil))
local pr = ZbuildsDB.legacyDump.probed.C_PerksActivities
out[#out+1] = "probed: activities=" .. #pr.GetPerksActivitiesInfo[1].activities .. " first=" .. pr.GetPerksActivitiesInfo[1].activities[1].activityName .. " | broken kept as error: " .. tostring(pr.GetBroken[1].error ~= nil) .. " | Set* not called: " .. tostring(pr.SetTracked == nil)
out[#out+1] = "namespace C_LegacyProgress keys: " .. table.concat(d.namespaces.C_LegacyProgress, ",")
-- the other command name
PRINTED = {}
SlashCmdList.ZBUILDSLEGACY()
out[#out+1] = "/zbuildslegacydump prints " .. #PRINTED .. " lines"
return table.concat(out, "\n")
