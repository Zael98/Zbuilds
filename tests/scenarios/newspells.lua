-- New spells and ranks onto the action bars: a new rank with a lower one on the bars (Replace puts it on every such
-- button), a new spell not on the bars (Place puts it on the cursor), a passive one and one the game already
-- placed (not offered), two ranks learned at once (only the highest), combat (waits), something on the cursor,
-- and the option off.
local out = {}
PRINTED = {}
print = function(...) local t = {} for k = 1, select("#", ...) do t[#t+1] = tostring(select(k, ...)) end PRINTED[#PRINTED+1] = table.concat(t, " ") end
C_Timer.After = function(_, f) f() end
UnitClass = function() return "SHAMAN", "SHAMAN" end
local function find(name, rank)
  for _, sp in ipairs(ZbuildsData.trainer.SHAMAN) do if sp.name == name and sp.rank == rank then return sp.id end end
end
C_Spell.GetSpellName = function(id)
  for _, sp in ipairs(ZbuildsData.trainer.SHAMAN) do if sp.id == id then return sp.name end end
  if id == 9001 then return "Passive Thing" end
end
C_Spell.GetSpellTexture = function(id) return 1000 + id end
C_Spell.IsSpellPassive = function(id) return id == 9001 end
local cursor
C_Spell.PickupSpell = function(id) cursor = id end
GetCursorInfo = function() if cursor then return "spell", cursor end end
ClearCursor = function() cursor = nil end
-- the bars: Lightning Bolt rank 1 on buttons 1 and 13, Healing Wave rank 1 on button 2
local bars = { [1] = find("Lightning Bolt", 1), [13] = find("Lightning Bolt", 1), [2] = find("Healing Wave", 1) }
GetActionInfo = function(slot) if bars[slot] then return "spell", bars[slot] end end
PlaceAction = function(slot) local old = bars[slot] bars[slot] = cursor cursor = old end
local combat = false
InCombatLockdown = function() return combat end
local function fire(event, ...) for _, o in ipairs(ALL) do if o.scripts.OnEvent then o.scripts.OnEvent(o, event, ...) end end end
local function strip(x) return (tostring(x):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function rows()
  local w, t = _G.ZbuildsNewSpells, {}
  if not (w and w.shown) then return "closed" end
  for _, r in ipairs(w.rows) do if r.shown then t[#t+1] = strip(r.name.text) .. " [" .. r.action.text .. "] " .. r.note.text end end
  return table.concat(t, " | ")
end
local function row(n) return _G.ZbuildsNewSpells.rows[n] end

-- rank 2 and rank 3 of Lightning Bolt at once, Lightning Shield (not on the bars), a passive, Healing Wave rank 1
-- (already on the bars)
fire("LEARNED_SPELL_IN_SKILL_LINE", find("Lightning Bolt", 2), 1, false)
fire("LEARNED_SPELL_IN_SKILL_LINE", find("Lightning Bolt", 3), 1, false)
fire("LEARNED_SPELL_IN_SKILL_LINE", find("Lightning Shield", 1), 1, false)
fire("LEARNED_SPELL_IN_SKILL_LINE", 9001, 1, false)
fire("LEARNED_SPELL_IN_SKILL_LINE", find("Healing Wave", 1), 1, false)
out[#out+1] = "offered: " .. rows()

-- something on the cursor: nothing changes
cursor = 12345
row(1).action.scripts.OnClick(row(1).action)
out[#out+1] = "cursor busy: bars " .. tostring(bars[1] == find("Lightning Bolt", 1)) .. ", said " .. strip(PRINTED[#PRINTED])
cursor = nil

-- Replace: rank 3 on both buttons, the cursor left empty
row(1).action.scripts.OnClick(row(1).action)
out[#out+1] = ("replaced: button 1 %s, button 13 %s, healing wave kept %s, cursor %s, said %s"):format(
  tostring(bars[1] == find("Lightning Bolt", 3)), tostring(bars[13] == find("Lightning Bolt", 3)),
  tostring(bars[2] == find("Healing Wave", 1)), tostring(cursor), strip(PRINTED[#PRINTED]))
out[#out+1] = "left: " .. rows()

-- Place: Lightning Shield on the cursor, for the button you click
row(1).action.scripts.OnClick(row(1).action)
out[#out+1] = ("placed: cursor %s, said %s, window %s"):format(tostring(cursor == find("Lightning Shield", 1)),
  strip(PRINTED[#PRINTED]), rows())
cursor = nil

-- in combat: nothing until it ends
combat = true
fire("LEARNED_SPELL_IN_SKILL_LINE", find("Healing Wave", 2), 1, false)
out[#out+1] = "in combat: " .. rows()
combat = false
fire("PLAYER_REGEN_ENABLED")
out[#out+1] = "after combat: " .. rows()
row(1).skip.scripts.OnClick(row(1).skip)
out[#out+1] = "skipped: " .. rows()

-- the option off: nothing offered
ns.SetOption("newSpells", false)
fire("LEARNED_SPELL_IN_SKILL_LINE", find("Earth Shock", 2), 1, false)
out[#out+1] = "option off: " .. rows()
ZbuildsDB.options = nil
return table.concat(out, "\n")
