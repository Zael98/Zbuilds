-- Trainer reminder: on level up (or /zb trainer), the spell ranks your class trainer sells that you can learn
-- now and do not have, with their total cost. What the trainer sells comes from Data.lua (spell ids and the
-- level of each rank and its price on Wowhead); what you know comes from the game (IsPlayerSpell); the costs
-- read at the trainer itself (the real price, reputation discount included) replace Wowhead's, kept per account.
-- Pet and demon abilities (kind "pet") and poisons (kind "poison") are only offered as upgrades of a rank the
-- pet or you already have: who can learn which of them depends on the pet family or on quests.
local _, ns = ...
local L = ns.L

local FORECAST_LEVELS = 5

local function costs()
    ZbuildsDB = ZbuildsDB or {}
    ZbuildsDB.trainerCosts = ZbuildsDB.trainerCosts or {}
    return ZbuildsDB.trainerCosts
end

local function classSpells()
    return ZbuildsData and ZbuildsData.trainer and ZbuildsData.trainer[ns.PlayerClass()] or {}
end

local function knows(spell)
    if spell.kind == "pet" then return IsSpellKnown and IsSpellKnown(spell.id, true) or false end
    return (IsPlayerSpell and IsPlayerSpell(spell.id)) or (IsSpellKnown and IsSpellKnown(spell.id)) or false
end

local function spellName(spell)
    return (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spell.id)) or spell.name
end

local function price(spell)
    return costs()[spell.id] or spell.cost
end

-- Names of the spells on your action bars (macros included), or nil when the client cannot tell: a known spell
-- that is not there gets its new ranks marked optional.
local function barSpells()
    if not GetActionInfo then return end
    local names = {}
    for slot = 1, 180 do
        local kind, id = GetActionInfo(slot)
        if kind == "macro" and GetMacroSpell then kind, id = "spell", GetMacroSpell(id) end
        local name = kind == "spell" and id and C_Spell.GetSpellName(id)
        if name then names[name] = true end
    end
    return next(names) and names or nil
end

-- What your trainer has for you now: { due, optional (spell -> true), total, optionalTotal, unpriced, pet,
-- forecast }. Per spell, only the ranks above the highest one you know (an old rank you skipped is never worth
-- buying); a spell you know but do not have on your bars is optional; forecast is the cost of what the next
-- levels bring.
function ns.TrainerDue()
    local level, petLevel = UnitLevel("player"), UnitExists and UnitExists("pet") and UnitLevel("pet") or 0
    local best = {}
    for _, spell in ipairs(classSpells()) do
        local key = (spell.kind or "") .. spell.name
        if spell.rank > (best[key] or 0) and knows(spell) then best[key] = spell.rank end
    end
    local bars = barSpells()
    local r = { due = {}, optional = {}, total = 0, optionalTotal = 0, unpriced = {}, pet = {}, forecast = 0 }
    for _, spell in ipairs(classSpells()) do
        local have = best[(spell.kind or "") .. spell.name] or 0
        local wanted = spell.rank > have and (not spell.kind or have > 0) and not knows(spell)
        if wanted and spell.kind == "pet" then
            if spell.level <= petLevel then r.pet[#r.pet + 1] = spell end
        elseif wanted and spell.level <= level then
            r.due[#r.due + 1] = spell
            local cost = price(spell)
            local optional = bars and have > 0 and not spell.kind and not bars[spellName(spell)]
            if optional then r.optional[spell] = true end
            if not cost then
                r.unpriced[#r.unpriced + 1] = spell
            else
                r.total = r.total + cost
                if optional then r.optionalTotal = r.optionalTotal + cost end
            end
        elseif wanted and spell.level <= level + FORECAST_LEVELS then
            r.forecast = r.forecast + (price(spell) or 0)
        end
    end
    return r
end

-- gold, silver and copper with the game's coin icons when it has them
local function money(copper)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    local gold, silver = floor(copper / 10000), floor(copper / 100) % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. "|cffffd700g|r" end
    if silver > 0 or gold > 0 then parts[#parts + 1] = silver .. "|cffc7c7cfs|r" end
    if copper % 100 > 0 or #parts == 0 then parts[#parts + 1] = (copper % 100) .. "|cffeda55fc|r" end
    return table.concat(parts, " ")
end

local function rankName(spell)
    return spell.rank > 1 and L.TRAINER_RANK:format(spellName(spell), spell.rank) or spellName(spell)
end

local function names(spells, optional)
    local out = {}
    for _, spell in ipairs(spells) do
        out[#out + 1] = optional and optional[spell] and "|cff888888" .. rankName(spell) .. "|r" or rankName(spell)
    end
    return table.concat(out, ", ")
end

-- The total, what the spells on your bars cost, and whether your gold is enough.
local function costLine(r)
    if #r.unpriced == #r.due then return "" end
    local line = L.TRAINER_COST:format(money(r.total))
    local essential = r.total - r.optionalTotal
    if r.optionalTotal > 0 then line = line .. "   " .. L.TRAINER_ON_BARS:format(money(essential)) end
    local gold = GetMoney()
    if gold >= r.total then
        return line .. "   |cff60ff60" .. L.TRAINER_ENOUGH .. "|r"
    elseif r.optionalTotal > 0 and gold >= essential then
        return line .. "   |cffffd200" .. L.TRAINER_ENOUGH_BARS .. "|r"
    end
    return line .. "   |cffff5050" .. L.TRAINER_SHORT:format(money(r.total - gold)) .. "|r"
end

-- The ranks the total leaves out, each with where it comes from when Wowhead says.
local function unpricedLine(r)
    if #r.unpriced == 0 then return "" end
    local out = {}
    for _, spell in ipairs(r.unpriced) do
        local source = spell.source and L["TRAINER_SOURCE_" .. spell.source:upper()]
        out[#out + 1] = source and ("%s (%s)"):format(rankName(spell), source) or rankName(spell)
    end
    return L.TRAINER_UNPRICED:format(table.concat(out, ", "))
end

local function petLine(r)
    if #r.pet == 0 then return "" end
    return (ns.PlayerClass() == "WARLOCK" and L.TRAINER_DEMON or L.TRAINER_PET):format(names(r.pet))
end

local function forecastLine(r)
    if r.forecast == 0 then return "" end
    return L.TRAINER_FORECAST:format(FORECAST_LEVELS, money(r.forecast))
end

local function icon(spellID)
    return C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID) or 134400
end

-- The level-up banner: the next talent of your build and what your trainer has for you.
local function levelUpBanner(r)
    local talent, talentRank, talentSpell = nil, nil, nil
    if ns.Option("talentAlert") then talent, talentRank, talentSpell = ns.NextTalent() end
    if #r.due == 0 and #r.pet == 0 and not talent then return end
    local icons = {}
    for _, spell in ipairs(r.due) do
        icons[#icons + 1] = { texture = icon(spell.id), spellID = spell.id, rank = spell.rank, dim = r.optional[spell] }
    end
    local talentLine = talent and L.BANNER_TALENT:format(
        talentSpell and ("|T%s:16:16|t "):format(icon(talentSpell)) or "", talent, talentRank) or ""
    local level = UnitLevel("player")
    return ns.ShowBanner({
        title = #r.due > 0 and L.TRAINER_NOTICE_TITLE or (talent and L.BANNER_TALENT_TITLE or L.TRAINER_NOTICE_TITLE),
        sub = #r.due > 0 and L.TRAINER_NOTICE:format(level, #r.due) or L.BANNER_LEVEL:format(level),
        icons = icons,
        lines = { costLine(r), talentLine, petLine(r), unpricedLine(r), forecastLine(r) },
    })
end

-- The reminder in the chat (quiet when there is nothing to learn unless asked, /zb trainer); on level up
-- (asked false) also the banner.
function ns.TrainerReminder(asked)
    local r = ns.TrainerDue()
    if not asked then levelUpBanner(r) end
    if not asked and not ns.Option("chat") then return end
    if #r.due == 0 and #r.pet == 0 then
        if asked then
            ns.Print(L.TRAINER_NOTHING)
            if r.forecast > 0 then print("   " .. forecastLine(r)) end
        end
        return
    end
    if #r.due > 0 then
        ns.Print(L.TRAINER_DUE:format(#r.due, names(r.due, r.optional))
            .. (next(r.optional) and "  " .. L.TRAINER_GREY or ""))
    end
    for _, line in ipairs({ costLine(r), petLine(r), unpricedLine(r), forecastLine(r) }) do
        if line ~= "" then print("   " .. line) end
    end
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

-- ---------------------------------------------------------------- "Train all" on the trainer window

-- The services you can learn now, with their cost; without the optional ones (spells not on your bars)
-- unless everything is asked for. The game says which are available; when its answer is not one of the
-- known words (WoW Forever's may differ), a due rank whose previous rank you know counts as available.
local KNOWN_KINDS = { available = true, unavailable = true, used = true }

local function learnable(everything)
    local due = ns.TrainerDue()
    local optional, ready = {}, {}
    for spell in pairs(due.optional) do optional[spell.id] = true end
    local ranks = {}
    for _, spell in ipairs(classSpells()) do ranks[spell.name .. "#" .. spell.rank] = spell end
    for _, spell in ipairs(due.due) do
        local previous = ranks[spell.name .. "#" .. (spell.rank - 1)]
        if spell.rank == 1 or (previous and knows(previous)) then ready[spell.id] = true end
    end
    local out, total = {}, 0
    for index = 1, GetNumTrainerServices() do
        local _, _, kind = GetTrainerServiceInfo(index)
        local spellID = serviceSpell(index)
        local available = kind == "available" or (not KNOWN_KINDS[kind] and spellID and ready[spellID])
        if available and (everything or not (spellID and optional[spellID])) then
            local cost = GetTrainerServiceCost(index) or 0
            out[#out + 1] = { index = index, cost = cost }
            total = total + cost
        end
    end
    return out, total
end

-- Buys from the bottom of the list up, so a purchase does not move the services still to buy; stops buying
-- what your gold does not cover. A rank that needs the one just bought shows up after, for another click.
function ns.TrainAll(everything)
    local gold, learned, spent = GetMoney(), 0, 0
    local list = learnable(everything)
    for k = #list, 1, -1 do
        local service = list[k]
        if service.cost <= gold - spent then
            BuyTrainerService(service.index)
            learned, spent = learned + 1, spent + service.cost
        end
    end
    ns.Print(learned > 0 and L.TRAIN_ALL_DONE:format(learned, money(spent)) or L.TRAIN_ALL_NONE)
    return learned
end

local trainButton
local function trainTooltip(self)
    local list, total = learnable(false)
    local all, allTotal = learnable(true)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(L.TRAIN_ALL)
    GameTooltip:AddLine(L.TRAIN_ALL_CLICK:format(#list, money(total)), 1, 1, 1, true)
    if #all > #list then GameTooltip:AddLine(L.TRAIN_ALL_SHIFT:format(#all, money(allTotal)), 0.7, 0.7, 0.7, true) end
    GameTooltip:Show()
end

local function showTrainButton()
    local trainer = ClassTrainerFrame
    if not trainer or (IsTradeskillTrainer and IsTradeskillTrainer()) or not BuyTrainerService then
        if trainButton then trainButton:Hide() end
        return
    end
    if not trainButton then
        trainButton = CreateFrame("Button", nil, trainer, "UIPanelButtonTemplate")
        trainButton:SetText(L.TRAIN_ALL)
        trainButton:SetSize(math.max(110, (trainButton:GetFontString() and trainButton:GetFontString():GetStringWidth() or 80) + 24), 22)
        trainButton:SetPoint("TOPLEFT", trainer, "TOPLEFT", 12, -30) -- free space left of the filters, clear of your gold
        trainButton:SetScript("OnClick", function() ns.TrainAll(IsShiftKeyDown and IsShiftKeyDown()) end)
        trainButton:SetScript("OnEnter", trainTooltip)
        trainButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    trainButton:SetEnabled(#learnable(true) > 0)
    trainButton:Show()
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
        C_Timer.After(0.2, function() -- the services list fills a moment after the window opens
            readTrainer()
            showTrainButton()
        end)
    elseif event == "TRAINER_UPDATE" then
        readTrainer()
        showTrainButton()
    elseif event == "PLAYER_LEVEL_UP" then
        C_Timer.After(1.5, function() ns.TrainerReminder(false) end) -- after the level's spells and point are granted
    end
end)
