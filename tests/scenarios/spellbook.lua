-- The trainer panel on the spellbook: what you can learn now (the same ranks as the trainer reminder) with its
-- total, each coming level with what it brings, the learned spells only when asked, folding it away.
local out = {}
local strip = function(x) return (tostring(x):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T[^|]*|t", "")) end
C_Timer.After = function(_, f) f() end
GetCoinTextureString = nil
local class, level, gold, known = "SHAMAN", 10, 50000, {}
UnitClass = function() return class, class end
UnitLevel = function() return level end
UnitExists = function() return false end
GetMoney = function() return gold end
local function spells() return ZbuildsData.trainer[class] end
-- a level 10 shaman who learned every rank up to level 8 but Lightning Shield
for _, sp in ipairs(spells()) do if sp.level <= 8 and sp.name ~= "Lightning Shield" then known[sp.id] = true end end
IsPlayerSpell = function(id) return known[id] == true end
IsSpellKnown = function(id) return known[id] == true end
C_Spell.GetSpellName = function(id) for _, sp in ipairs(spells()) do if sp.id == id then return sp.name end end end
C_Spell.GetSpellTexture = function(id) return 1000 + id end
local function fire(event, ...) for _, o in ipairs(ALL) do if o.scripts.OnEvent then o.scripts.OnEvent(o, event, ...) end end end

-- the game's window with its spellbook tab, loaded (and a minimap for the minimap button, also made at login)
Minimap = STUB(); Minimap.GetWidth = function() return 140 end
PlayerSpellsFrame = CreateFrame("Frame")
PlayerSpellsFrame.SpellBookFrame = CreateFrame("Frame")
PlayerSpellsFrame.TalentsFrame = CreateFrame("Frame")
fire("PLAYER_LOGIN")

local function shown()
  local lines, open = ns.TrainingLines()
  local headers, now, later = {}, 0, 0
  for _, line in ipairs(lines) do
    local state, text = line:match("^(%a+)|([^|]*)")
    if state == "header" then headers[#headers + 1] = strip(text) end
    if state == "now" then now = now + 1 end
    if state == "later" then later = later + 1 end
  end
  return headers, now, later, open, lines
end

local headers, now, later, open = shown()
out[#out + 1] = ("open %s; now %d (due %d); later %d; first: %s; then: %s"):format(tostring(open), now,
  #ns.TrainerDue().due, later, headers[1] or "-", headers[2] or "-")
local lightning = false
for _, line in ipairs(select(5, shown())) do if line:find("^now|Lightning Shield") then lightning = true end end
out[#out + 1] = "lightning shield now: " .. tostring(lightning)
local last = headers[#headers]
out[#out + 1] = "known hidden: " .. tostring(not last:find("%(%d+%)$") or not last:find(ns.L.SPELLBOOK_KNOWN:gsub("%%d", ""):gsub("[%(%)]", ""), 1, true))

-- learned ones shown when asked
ns.SetOption("trainingKnown", true)
ns.RefreshTraining()
headers = shown()
local known_n = 0
for _ in pairs(known) do known_n = known_n + 1 end
out[#out + 1] = ("known shown: %s (learned %d)"):format(headers[#headers], known_n)
ns.SetOption("trainingKnown", false)

-- a level up: what level 12 brought moves to now
level = 12
fire("PLAYER_LEVEL_UP")
local _, now12 = shown()
out[#out + 1] = ("level 12: now %d (due %d)"):format(now12, #ns.TrainerDue().due)

-- folded away and back
ns.ToggleTraining(false)
local _, _, _, folded = shown()
local kept = ns.Option("trainingPanel")
ns.ToggleTraining(true)
local _, _, _, back = shown()
out[#out + 1] = ("folded: open %s, option %s; back: open %s"):format(tostring(folded), tostring(kept), tostring(back))
return table.concat(out, "\n")
