-- Gear advice on item tooltips: the specialisation from the talents spent (an Enhancement shaman: strength), an
-- item better or worse than what is worn in its slot, an empty slot, a caster item, the option off.
local out = {}
for id, n in pairs(TREE_NODES) do
  if math.floor(id / 1000) == 2 then n.currentRank = n.maxRanks end   -- (every Enhancement talent bought)
end
local STATS = {
  ["item:1"] = { ITEM_MOD_STRENGTH_SHORT = 10 },
  ["item:2"] = { ITEM_MOD_STRENGTH_SHORT = 5 },
  ["item:3"] = { ITEM_MOD_INTELLECT_SHORT = 20 },
  ["item:4"] = { ITEM_MOD_STRENGTH_SHORT = 4 },
  ["item:5"] = { ITEM_MOD_STRENGTH_SHORT = 3 },
}
C_Item = C_Item or {}
C_Item.GetItemStats = function(link) return STATS[link] end
C_Item.GetItemInfoInstant = function(link) return 1, nil, nil, link == "item:5" and "INVTYPE_FINGER" or "INVTYPE_HEAD" end
C_Item.IsEquippableItem = function() return true end
local worn = { [1] = "item:2" }
GetInventoryItemLink = function(_, slot) return worn[slot] end
local function line(link) local l = ns.GearLine(link) return l and l[1] or "nil" end

local role, tree = ns.GearRole()
out[#out + 1] = ("role: %s (%s)"):format(tostring(role), tostring(tree and tree.name))
out[#out + 1] = "better: " .. line("item:1")
out[#out + 1] = "worse: " .. line("item:4")
out[#out + 1] = "caster item: " .. line("item:3")
out[#out + 1] = "worn one: " .. line("item:2")
out[#out + 1] = "empty ring slot: " .. line("item:5")
ns.SetOption("gear", false)
out[#out + 1] = "option off: " .. line("item:1")
ns.SetOption("gear", true)
return table.concat(out, "\n")
