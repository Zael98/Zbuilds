-- Does the sites' data still fit the game? The talent tree of the dumped character and the Legacy trees,
-- read the way the addon reads them, from a real /zb legacy dump (tests/fixtures/legacy_dump.lua).
-- After a game patch the dump is from the old build: run /zb legacy and /reload in game, then copy
-- ZbuildsDB.legacyDump from WTF/Account/<account>/SavedVariables/Zbuilds.lua into the fixture.
local dump, out = REAL_DUMP_DB.legacyDump, {}
local configs = {}
for _, c in ipairs(dump.configs) do configs[c.id] = c end
local function treeNodes(tree)
  local nodes = {}
  for _, n in ipairs(tree.nodes) do
    nodes[n.id] = { ID = n.id, posX = n.x, posY = n.y, maxRanks = n.maxRanks, currentRank = n.currentRank or 0,
                    ranksPurchased = n.ranksPurchased, entryIDs = { n.entries[1].id }, isVisible = true,
                    visibleEdges = n.edges, spell = n.entries[1].spellID, name = n.entries[1].name }
  end
  return nodes
end
local nodesOf, treeOf, spellOf = {}, {}, {}
for _, c in ipairs(dump.configs) do
  nodesOf[c.id] = {}
  for _, tree in ipairs(c.trees) do
    treeOf[tree.id] = { config = c.id, ids = {} }
    for id, n in pairs(treeNodes(tree)) do
      nodesOf[c.id][id] = n; table.insert(treeOf[tree.id].ids, id); spellOf[n.entryIDs[1]] = n
    end
  end
end
local talents
for _, c in ipairs(dump.configs) do if c.foundBy == "class talents" then talents = c end end
C_ClassTalents.GetActiveConfigID = function() return talents.id end
C_Traits.GetConfigInfo = function(id) return configs[id].info end
C_Traits.GetConfigIDByTreeID = function(id) return treeOf[id] and treeOf[id].config end
C_Traits.GetTreeNodes = function(id) return treeOf[id] and treeOf[id].ids or {} end
C_Traits.GetNodeInfo = function(cfg, id) return nodesOf[cfg][id] end
C_Traits.GetEntryInfo = function(_, id) return { definitionID = id } end
C_Traits.GetDefinitionInfo = function(id) return { spellID = spellOf[id].spell } end
C_Traits.GetTreeCurrencyInfo = function() return { { quantity = 0 } } end
C_Spell.GetSpellName = function(id) for _, n in pairs(spellOf) do if n.spell == id then return n.name end end end

out[#out+1] = "dump of build " .. dump.client[2] .. ", data of " .. ZbuildsData.generated
local cd = ns.ClassData(dump.class)
local tree, err = ns.ReadTree(cd)
if tree then
  local found, total = 0, 0
  for t, data in ipairs(cd.trees) do for i in ipairs(data.talents) do
    total = total + 1
    local id = tree.node[t][i]
    if id and nodesOf[talents.id][id].name == data.talents[i].name then found = found + 1 end
  end end
  out[#out+1] = ("%s talents: %d/%d found, %d outdated: %s"):format(dump.class, found, total, #tree.mismatches,
    table.concat(tree.mismatches, ", "))
else
  out[#out+1] = dump.class .. " talents: " .. tostring(err)
end
local legacy = ns.ReadLegacy(ns.LegacyData())
local found, total, wrong = 0, 0, {}
for t, data in ipairs(ns.LegacyData().trees) do for i, perk in ipairs(data.perks) do
  total = total + 1
  local id = legacy.node[t][i]
  local name = id and nodesOf[legacy.configID][id].name
  if name == perk.name then found = found + 1 else wrong[#wrong+1] = perk.name end
end end
out[#out+1] = ("legacy perks: %d/%d found, not where the data puts them: %s"):format(found, total, table.concat(wrong, ", "))
return table.concat(out, "\n")
