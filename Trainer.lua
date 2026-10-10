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

local function classSpells()
    return ZbuildsData and ZbuildsData.trainer and ZbuildsData.trainer[ns.PlayerClass()] or {}
end

local function knows(spellID)
    return (IsPlayerSpell and IsPlayerSpell(spellID)) or (IsSpellKnown and IsSpellKnown(spellID)) or false
end

local function spellName(spell)
    return (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spell.id)) or spell.name
end

-- Ranks you can learn at your level and do not have: per spell, only the ranks above the highest one you know
-- (an old rank you skipped is never worth buying). Returns the list, the total of the known costs, and how
-- many costs are not known yet.
function ns.TrainerDue()
    local level, best = UnitLevel("player"), {}
    for _, spell in ipairs(classSpells()) do
        if knows(spell.id) and spell.rank > (best[spell.name] or 0) then best[spell.name] = spell.rank end
    end
    local due, total, unknown = {}, 0, 0
    for _, spell in ipairs(classSpells()) do
        if spell.level <= level and spell.rank > (best[spell.name] or 0) and not knows(spell.id) then
            due[#due + 1] = spell
            local cost = costs()[spell.id]
            if cost then total = total + cost else unknown = unknown + 1 end
        end
    end
    return due, total, unknown
end

-- gold, silver and copper with the game's coin icons when it has them
local function money(copper)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    local gold, silver = floor(copper / 10000), floor(copper / 100) % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. "|cffffd700g|r" end
    if silver > 0 or gold > 0 then parts[#parts + 1] = silver .. "|cffc7c7cfs|r" end
    parts[#parts + 1] = (copper % 100) .. "|cffeda55fc|r"
    return table.concat(parts, " ")
end

-- On level up, also in the middle of the screen, the way the game shows raid warnings.
local function notice(count)
    local text = L.TRAINER_NOTICE:format(count)
    if RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, text, { r = 1, g = 0.82, b = 0 })
    elseif UIErrorsFrame then
        UIErrorsFrame:AddMessage(text, 1, 0.82, 0)
    end
    if SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
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
        names[#names + 1] = spell.rank > 1 and L.TRAINER_RANK:format(spellName(spell), spell.rank) or spellName(spell)
    end
    ns.Print(L.TRAINER_DUE:format(#due, table.concat(names, ", ")))
    if not asked then notice(#due) end
    local parts = {}
    if unknown < #due then parts[#parts + 1] = L.TRAINER_COST:format(money(total)) end
    if unknown > 0 then parts[#parts + 1] = L.TRAINER_UNKNOWN:format(unknown) end
    -- whether the gold is enough is only said when every cost is known
    local short = total - GetMoney()
    if short > 0 then
        parts[#parts + 1] = "|cffff5050" .. L.TRAINER_SHORT:format(money(short)) .. "|r"
    elseif unknown == 0 then
        parts[#parts + 1] = L.TRAINER_ENOUGH
    end
    print("   " .. table.concat(parts, "   "))
end

-- The spell id of a trainer service: from the tooltip data when the client gives it, else by matching
-- the service's name and rank with the class's trainer spells.
local function serviceSpell(index)
    local info = C_TooltipInfo and C_TooltipInfo.GetTrainerService and C_TooltipInfo.GetTrainerService(index)
    if info and info.id then return info.id end
    local name, rankText = GetTrainerServiceInfo(index)
    local rank = tonumber(rankText and rankText:match("(%d+)")) or 1
    for _, spell in ipairs(classSpells()) do
        if spell.rank == rank and spellName(spell) == name then return spell.id end
    end
end

-- At the trainer: the cost of everything it sells.
local lastRead = 0
local function readTrainer()
    if not (GetNumTrainerServices and GetTrainerServiceCost and GetTrainerServiceInfo) then return end
    local read = 0
    for index = 1, GetNumTrainerServices() do
        local spellID, cost = serviceSpell(index), GetTrainerServiceCost(index)
        if spellID and cost then
            costs()[spellID] = cost
            read = read + 1
        end
    end
    if read > lastRead then ns.Print(L.TRAINER_READ:format(read)) end
    lastRead = read
end

-- /zb trainerdump, at an open trainer: what this client's trainer functions return, to adapt the reading.
function ns.TrainerDump()
    local dump = { functions = {}, namespaces = {} }
    for name, value in pairs(_G) do
        if type(name) == "string" and name:find("Trainer") then
            if type(value) == "function" then
                dump.functions[#dump.functions + 1] = name
            elseif type(value) == "table" and name:match("^C_") then
                local keys = {}
                for key in pairs(value) do keys[#keys + 1] = tostring(key) end
                dump.namespaces[name] = keys
            end
        end
    end
    table.sort(dump.functions)
    local function try(fn, ...) if type(fn) ~= "function" then return "missing" end return { pcall(fn, ...) } end
    dump.count = try(GetNumTrainerServices)
    dump.filters = {}
    for _, kind in ipairs({ "available", "unavailable", "used" }) do dump.filters[kind] = try(GetTrainerServiceTypeFilter, kind) end
    dump.services = {}
    local count = type(dump.count) == "table" and dump.count[2] or 0
    for index = 1, math.min(type(count) == "number" and count or 0, 8) do
        dump.services[index] = { info = try(GetTrainerServiceInfo, index), cost = try(GetTrainerServiceCost, index),
            level = try(GetTrainerServiceLevelReq, index),
            tooltip = try(C_TooltipInfo and C_TooltipInfo.GetTrainerService, index) }
    end
    ZbuildsDB = ZbuildsDB or {}
    ZbuildsDB.trainerDump = dump
    ns.Print(("trainer dump: %d services, %d trainer functions; saved, type /reload to write it to disk.")
        :format(type(count) == "number" and count or -1, #dump.functions))
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE", "PLAYER_LEVEL_UP" }) do
    if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(event) then
        events:RegisterEvent(event)
    end
end
events:SetScript("OnEvent", function(_, event)
    if event == "TRAINER_SHOW" then
        lastRead = 0
        C_Timer.After(0.2, readTrainer) -- the services list fills a moment after the window opens
    elseif event == "TRAINER_UPDATE" then
        readTrainer()
    else
        C_Timer.After(1.5, function() ns.TrainerReminder(false) end) -- after the level's spells are granted
    end
end)
