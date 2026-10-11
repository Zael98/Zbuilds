-- Trainer reminder: what is due, prices, optional ranks (not on your bars), the 5-level forecast, the level-up
-- banner and its options, "Train all", pets, demons and poisons, reading prices at the trainer.
local out = {}
local strip = function(x) return (tostring(x):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T[^|]*|t", "")) end
PRINTED = {}
print = function(...) local t = {} for k = 1, select("#", ...) do t[#t+1] = tostring(select(k, ...)) end PRINTED[#PRINTED+1] = table.concat(t, " ") end
C_Timer.After = function(_, f) f() end
GetCoinTextureString = nil
local class, level, gold, known, petKnown = "SHAMAN", 10, 50000, {}, {}
UnitClass = function() return class, class end
UnitLevel = function(unit) return unit == "pet" and 20 or level end
UnitExists = function(unit) return unit == "pet" and (class == "HUNTER" or class == "WARLOCK") end
GetMoney = function() return gold end
local function spells() return ZbuildsData.trainer[class] end
local function find(name, rank) for _, sp in ipairs(spells()) do if sp.name == name and sp.rank == rank then return sp end end end
-- a level 10 shaman who learned every rank up to level 8 but not Earth Shock rank 2 nor Lightning Shield
for _, sp in ipairs(spells()) do if sp.level <= 8 and sp.name ~= "Lightning Shield" and not (sp.name == "Earth Shock" and sp.rank == 2) then known[sp.id] = true end end
IsPlayerSpell = function(id) return known[id] == true end
IsSpellKnown = function(id, pet) if pet then return petKnown[id] == true end return known[id] == true end
C_Spell.GetSpellName = function(id) for _, list in pairs(ZbuildsData.trainer) do for _, sp in ipairs(list) do if sp.id == id then return sp.name end end end end
C_Spell.GetSpellTexture = function(id) return 1000 + id end
-- on the action bars: Healing Wave and Lightning Bolt (Earth Shock, known, is not there)
local bars = { find("Healing Wave", 1).id, find("Lightning Bolt", 1).id }
GetActionInfo = function(slot) if bars[slot] then return "spell", bars[slot] end end
STANDARD_TEXT_FONT = "font"; SOUNDKIT = { RAID_WARNING = 8959 }; SOUNDS = {}; PlaySound = function(id) SOUNDS[#SOUNDS+1] = id end
local function last(n) local t = {} for k = math.max(1, #PRINTED - n + 1), #PRINTED do t[#t+1] = strip(PRINTED[k]) end return table.concat(t, " / ") end
local function fire(event, ...) for _, o in ipairs(ALL) do if o.scripts.OnEvent then o.scripts.OnEvent(o, event, ...) end end end
local function banner() for _, o in ipairs(ALL) do if o.lines and o.anim then return o end end end
local function lines(b) local t = {} for _, fs in ipairs(b.lines) do if fs.shown and fs.text ~= "" then t[#t+1] = strip(fs.text) end end return table.concat(t, " | ") end

SlashCmdList.ZBUILDS("trainer")
out[#out+1] = "before the trainer: " .. last(3)

-- at the trainer: it sells every shaman rank up to level 20, 1 silver per level each
local sold = {}
for _, sp in ipairs(spells()) do if sp.level <= 20 then sold[#sold+1] = sp end end
GetNumTrainerServices = function() return #sold end
GetTrainerServiceCost = function(i) return sold[i].level * 100 end
C_TooltipInfo = { GetTrainerService = function(i) return { id = sold[i].id } end }
GetTrainerServiceInfo = function(i) return sold[i].name, "Rank " .. sold[i].rank, sold[i].level <= level and not known[sold[i].id] and "available" or "unavailable" end
IsTradeskillTrainer = function() return false end
BOUGHT = {}
BuyTrainerService = function(i) BOUGHT[#BOUGHT+1] = i end
fire("TRAINER_SHOW")
out[#out+1] = "trainer opened: " .. last(1) .. " | train button without the trainer frame: none"
ClassTrainerFrame = CreateFrame("Frame")
ClassTrainerTrainButton = CreateFrame("Button")
fire("TRAINER_SHOW")
local trainButton
for _, o in ipairs(ALL) do if o.text == ns.L.TRAIN_ALL then trainButton = o end end
out[#out+1] = "train button: " .. tostring(trainButton and trainButton.shown)
SlashCmdList.ZBUILDS("trainer")
out[#out+1] = "after: " .. last(3)

-- Train all: a click leaves out Earth Shock 2 (known spell, not on the bars); shift-click buys it too
IsShiftKeyDown = function() return false end
trainButton.scripts.OnClick(trainButton)
local boughtNames = {} for _, i in ipairs(BOUGHT) do boughtNames[#boughtNames+1] = sold[i].name .. " " .. sold[i].rank end
out[#out+1] = "train all: " .. table.concat(boughtNames, ", ") .. " | " .. last(1)
local descending = true for k = 2, #BOUGHT do if BOUGHT[k] > BOUGHT[k-1] then descending = false end end
out[#out+1] = "bought from the bottom up: " .. tostring(descending)
BOUGHT = {}
IsShiftKeyDown = function() return true end
trainButton.scripts.OnClick(trainButton)
boughtNames = {} for _, i in ipairs(BOUGHT) do boughtNames[#boughtNames+1] = sold[i].name .. " " .. sold[i].rank end
out[#out+1] = "shift: " .. table.concat(boughtNames, ", ")
gold = 0; BOUGHT = {}
trainButton.scripts.OnClick(trainButton)
out[#out+1] = "no gold: bought " .. #BOUGHT .. " | " .. last(1)
gold = 50000

-- level up to 12 with little gold: the banner, with the next talent of the build
level, gold = 12, 500
ns.NextTalent = function() return "Convection", 2, 16039, { name = "My build" } end
fire("PLAYER_LEVEL_UP")
local b = banner()
local dim = 0 for _, ic in ipairs(b.icons) do if ic.shown and ic.tex.desaturated then dim = dim + 1 end end
out[#out+1] = "banner: " .. tostring(b.title.text) .. " | " .. tostring(b.sub.text) .. " | " .. lines(b)
local n = 0 for _, ic in ipairs(b.icons) do if ic.shown then n = n + 1 end end
out[#out+1] = "icons " .. n .. " | sounds " .. #SOUNDS
out[#out+1] = "level 12 chat: " .. last(3)
-- only a talent: the banner says so
local saved = ZbuildsData.trainer.SHAMAN
ZbuildsData.trainer.SHAMAN = {}
fire("PLAYER_LEVEL_UP")
out[#out+1] = "talent only: " .. tostring(b.title.text) .. " | " .. tostring(b.sub.text) .. " | " .. lines(b)
ZbuildsData.trainer.SHAMAN = saved

-- the game's own level-up banner on screen: ours waits for it to go, then shows
b.shown = false
LevelUpDisplay = CreateFrame("Frame")
local queue = {}
C_Timer.After = function(_, f) queue[#queue+1] = f end
fire("PLAYER_LEVEL_UP")
for k = 1, 4 do local q = queue queue = {} for _, f in ipairs(q) do f() end end
out[#out+1] = "game banner on screen: ours shown " .. tostring(b.shown)
LevelUpDisplay:Hide()
for k = 1, 2 do local q = queue queue = {} for _, f in ipairs(q) do f() end end
out[#out+1] = "game banner gone: ours shown " .. tostring(b.shown)
LevelUpDisplay:Show()
b.shown = false
fire("PLAYER_LEVEL_UP")
for k = 1, 40 do local q = queue queue = {} for _, f in ipairs(q) do f() end end
out[#out+1] = "game banner never leaves: ours shown " .. tostring(b.shown)
LevelUpDisplay = nil
C_Timer.After = function(_, f) f() end

-- options: no banner, no sound, no chat
b.shown = false
ns.SetOption("banner", false)
local chatBefore = #PRINTED
fire("PLAYER_LEVEL_UP")
out[#out+1] = "banner off: shown " .. tostring(b.shown)
ns.SetOption("banner", true); ns.SetOption("sound", false); ns.SetOption("chat", false)
local soundsBefore = #SOUNDS
chatBefore = #PRINTED
fire("PLAYER_LEVEL_UP")
out[#out+1] = "sound off: new sounds " .. (#SOUNDS - soundsBefore) .. " | chat off: new lines " .. (#PRINTED - chatBefore) .. " (talent line from Core only) | banner shown " .. tostring(b.shown)
ns.SetOption("talentAlert", false)
fire("PLAYER_LEVEL_UP")
out[#out+1] = "talent off: " .. lines(b)
ZbuildsDB.options = nil

-- learn Earth Shock rank 3 (skipping rank 2): rank 2 is no longer offered
known[find("Earth Shock", 3).id] = true
local names = {} for _, sp in ipairs(ns.TrainerDue().due) do names[#names+1] = sp.name .. " " .. sp.rank end
out[#out+1] = "after learning Earth Shock 3: " .. table.concat(names, ", ")
ZbuildsDB.trainerCosts = {}
SlashCmdList.ZBUILDS("trainertest")
out[#out+1] = "trainertest banner: " .. lines(b)

-- hunter: pet abilities only as upgrades of what the pet knows, by the pet's level; never as the hunter's own
class, level, known = "HUNTER", 20, {}
for _, sp in ipairs(spells()) do if sp.level <= 20 and not sp.kind then known[sp.id] = true end end
petKnown = { [find("Bite", 1).id] = true, [find("Bite", 2).id] = true }
SlashCmdList.ZBUILDS("trainer")
out[#out+1] = "hunter: " .. last(2)
-- warlock: the demon
class, level, known = "WARLOCK", 20, {}
for _, sp in ipairs(spells()) do if sp.level <= 20 and not sp.kind then known[sp.id] = true end end
petKnown = { [find("Firebolt", 1).id] = true }
SlashCmdList.ZBUILDS("trainer")
out[#out+1] = "warlock: " .. last(2)
-- rogue: poisons only once you have their first rank
class, level, known = "ROGUE", 40, {}
for _, sp in ipairs(spells()) do if sp.level <= 40 and not sp.kind then known[sp.id] = true end end
local poisons = {} for _, sp in ipairs(ns.TrainerDue().due) do poisons[#poisons+1] = sp.name end
out[#out+1] = "rogue without poisons: " .. #poisons
known[find("Instant Poison", 1).id] = true
poisons = {} for _, sp in ipairs(ns.TrainerDue().due) do poisons[#poisons+1] = sp.name .. " " .. sp.rank end
out[#out+1] = "rogue with Instant Poison 1: " .. table.concat(poisons, ", ")
class, level = "SHAMAN", 12
for _, sp in ipairs(spells()) do if sp.level <= 8 then known[sp.id] = true end end

-- a client without tooltip ids: matched by name and rank
ZbuildsDB.trainerCosts = {}
C_TooltipInfo = nil
fire("TRAINER_SHOW")
local matched = 0 for _ in pairs(ZbuildsDB.trainerCosts) do matched = matched + 1 end
out[#out+1] = "by name and rank: " .. matched .. " costs | " .. last(1)
SlashCmdList.ZBUILDS("trainerdump")
out[#out+1] = "dump: " .. last(1) .. " | services saved " .. #ZbuildsDB.trainerDump.services
-- an empty trainer list: nothing read, no message, no error
GetNumTrainerServices = function() return 0 end
local before = #PRINTED
fire("TRAINER_SHOW")
out[#out+1] = "empty trainer: new messages " .. (#PRINTED - before) .. " | train button enabled " .. tostring(trainButton.enabled)
return table.concat(out, "\n")
