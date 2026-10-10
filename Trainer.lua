-- Trainer reminder: on level up (or /zb trainer), the spell ranks your class trainer sells that you can learn
-- now and do not have, with their total cost. What the trainer sells comes from Data.lua (spell ids and the
-- level of each rank); what you know comes from the game (IsPlayerSpell); the costs are read at the trainer
-- itself, the only place the game gives them, and kept per account (they are the same for every character).
local _, ns = ...
local L = ns.L

local function costs()
    ZbuildsDB = ZbuildsDB or {}
    ZbuildsDB.trainerCosts = ZbuildsDB.trainerCosts or {}
    return ZbuildsDB.trainerCosts
end

local function knows(spellID)
    return (IsPlayerSpell and IsPlayerSpell(spellID)) or (IsSpellKnown and IsSpellKnown(spellID)) or false
end

-- Ranks you can learn at your level and do not have: per spell, only the ranks above the highest one you know
-- (an old rank you skipped is never worth buying). Returns the list, the total of the known costs, and how
-- many costs are not known yet.
function ns.TrainerDue()
    local data = ZbuildsData and ZbuildsData.trainer and ZbuildsData.trainer[ns.PlayerClass()]
    if not data then return {}, 0, 0 end
    local level, best = UnitLevel("player"), {}
    for _, spell in ipairs(data) do
        if knows(spell.id) and spell.rank > (best[spell.name] or 0) then best[spell.name] = spell.rank end
    end
    local due, total, unknown = {}, 0, 0
    for _, spell in ipairs(data) do
        if spell.level <= level and spell.rank > (best[spell.name] or 0) and not knows(spell.id) then
            due[#due + 1] = spell
            local cost = costs()[spell.id]
            if cost then total = total + cost else unknown = unknown + 1 end
        end
    end
    return due, total, unknown
end

local function money(copper)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    return ("%dg %ds %dc"):format(floor(copper / 10000), floor(copper / 100) % 100, copper % 100)
end

-- The reminder in the chat; quiet when there is nothing to learn unless asked (/zb trainer).
function ns.TrainerReminder(asked)
    local due, total, unknown = ns.TrainerDue()
    if #due == 0 then
        if asked then ns.Print(L.TRAINER_NOTHING) end
        return
    end
    local names = {}
    for _, spell in ipairs(due) do
        local name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spell.id)) or spell.name
        names[#names + 1] = spell.rank > 1 and L.TRAINER_RANK:format(name, spell.rank) or name
    end
    ns.Print(L.TRAINER_DUE:format(#due, table.concat(names, ", ")))
    local line = L.TRAINER_COST:format(money(total))
    if unknown > 0 then line = line .. "  " .. L.TRAINER_UNKNOWN:format(unknown) end
    local short = total - GetMoney()
    line = line .. "  " .. (short > 0 and ("|cffff5050" .. L.TRAINER_SHORT:format(money(short)) .. "|r") or L.TRAINER_ENOUGH)
    print("   " .. line)
end

-- At the trainer: the cost of everything it sells, by spell id (the tooltip data knows the id).
local function readTrainer()
    if not (GetNumTrainerServices and GetTrainerServiceCost) then return end
    local read = 0
    for index = 1, GetNumTrainerServices() do
        local info = C_TooltipInfo and C_TooltipInfo.GetTrainerService and C_TooltipInfo.GetTrainerService(index)
        local spellID = info and info.id
        local cost = GetTrainerServiceCost(index)
        if spellID and cost then
            costs()[spellID] = cost
            read = read + 1
        end
    end
    if read > 0 then ns.Print(L.TRAINER_READ:format(read)) end
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "TRAINER_SHOW", "PLAYER_LEVEL_UP" }) do
    if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(event) then
        events:RegisterEvent(event)
    end
end
events:SetScript("OnEvent", function(_, event)
    if event == "TRAINER_SHOW" then
        C_Timer.After(0.2, readTrainer) -- the services list fills a moment after the window opens
    else
        C_Timer.After(1.5, function() ns.TrainerReminder(false) end) -- after the level's spells are granted
    end
end)
