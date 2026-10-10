-- Trainer reminder: on level up (or /zb trainer), the spell ranks your class trainer sells that you can learn
-- now and do not have, with their total cost. What the trainer sells comes from Data.lua (spell ids and the
-- level of each rank and its price on Wowhead); what you know comes from the game (IsPlayerSpell); the costs
-- read at the trainer itself (the real price, reputation discount included) replace Wowhead's, kept per account.
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
            local cost = costs()[spell.id] or spell.cost
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

-- The total, the ranks without a known price, and whether your gold is enough (only said when every price is known).
local function costLine(due, total, unknown)
    local parts = {}
    if unknown < #due then parts[#parts + 1] = L.TRAINER_COST:format(money(total)) end
    if unknown > 0 then parts[#parts + 1] = L.TRAINER_UNKNOWN:format(unknown) end
    local short = total - GetMoney()
    if short > 0 then
        parts[#parts + 1] = "|cffff5050" .. L.TRAINER_SHORT:format(money(short)) .. "|r"
    elseif unknown == 0 then
        parts[#parts + 1] = "|cff60ff60" .. L.TRAINER_ENOUGH .. "|r"
    end
    return table.concat(parts, "   ")
end

-- On level up, a banner in the middle of the screen like the game's own level-up one: a dark band fading at
-- both ends between two gold lines, the title, the level, the icons of the new spells and their cost.
-- It slides in, stays a few seconds and fades away; a click closes it.
local GOLD = { 1, 0.82, 0 }
local MAX_ICONS = 10
local banner

-- A horizontal band that fades out at both ends: two halves meeting in the middle, anchored at the top,
-- the bottom or the centre of the parent, with an inset at the ends.
local function band(parent, layer, anchor, y, height, inset, color, alpha)
    for side = 1, 2 do
        local tex = parent:CreateTexture(nil, layer)
        tex:SetColorTexture(1, 1, 1)
        tex:SetHeight(height)
        local outer, inner = side == 1 and "LEFT" or "RIGHT", side == 1 and "RIGHT" or "LEFT"
        local point = anchor == "CENTER" and "" or anchor
        tex:SetPoint(point .. outer, parent, point .. outer, side == 1 and inset or -inset, y)
        tex:SetPoint(point .. inner, parent, anchor, 0, y)
        local clear, solid = CreateColor(color[1], color[2], color[3], 0), CreateColor(color[1], color[2], color[3], alpha)
        tex:SetGradient("HORIZONTAL", side == 1 and clear or solid, side == 1 and solid or clear)
        if layer == "ARTWORK" then tex:SetBlendMode("ADD") end
    end
end

local function text(parent, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetShadowOffset(1, -1)
    return fs
end

local function createBanner()
    local f = CreateFrame("Button", nil, UIParent)
    f:SetSize(620, 128)
    f:SetPoint("TOP", UIParent, "TOP", 0, -170)
    f:SetFrameStrata("HIGH")
    f:Hide()
    band(f, "BACKGROUND", "CENTER", 0, 128, 0, { 0, 0, 0 }, 0.75)
    band(f, "BORDER", "TOP", 0, 2, 0, GOLD, 0.9)
    band(f, "BORDER", "BOTTOM", 0, 2, 0, GOLD, 0.9)
    band(f, "ARTWORK", "TOP", -10, 40, 120, GOLD, 0.18) -- a soft gold light behind the title

    f.title = text(f, 26, GOLD)
    f.title:SetPoint("TOP", 0, -12)
    f.sub = text(f, 13, { 1, 1, 1 })
    f.sub:SetPoint("TOP", f.title, "BOTTOM", 0, -4)
    f.icons = {}
    for k = 1, MAX_ICONS do
        local icon = CreateFrame("Frame", nil, f)
        icon:SetSize(32, 32)
        icon.border = icon:CreateTexture(nil, "ARTWORK")
        icon.border:SetAllPoints()
        icon.border:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.8)
        icon.tex = icon:CreateTexture(nil, "OVERLAY")
        icon.tex:SetPoint("TOPLEFT", 1, -1)
        icon.tex:SetPoint("BOTTOMRIGHT", -1, 1)
        icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon.rank = text(icon, 10, { 1, 1, 1 })
        icon.rank:SetPoint("BOTTOMRIGHT", 2, -2)
        icon:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetSpellByID(self.spellID)
            GameTooltip:Show()
        end)
        icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.icons[k] = icon
    end
    f.more = text(f, 14, GOLD)
    f.cost = text(f, 12, { 0.85, 0.85, 0.85 })
    f.cost:SetPoint("BOTTOM", 0, 8)

    -- in: fade and a short drop into place; then hold; then out
    f.anim = f:CreateAnimationGroup()
    local fadeIn = f.anim:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0) fadeIn:SetToAlpha(1) fadeIn:SetDuration(0.35) fadeIn:SetOrder(1)
    local drop = f.anim:CreateAnimation("Translation")
    drop:SetOffset(0, -14) drop:SetDuration(0.35) drop:SetOrder(1) drop:SetSmoothing("OUT")
    local fadeOut = f.anim:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1) fadeOut:SetToAlpha(0) fadeOut:SetDuration(1.2) fadeOut:SetStartDelay(6) fadeOut:SetOrder(2)
    f.anim:SetScript("OnFinished", function() f:Hide() end)
    f:SetScript("OnClick", function() f.anim:Stop() f:Hide() end)
    return f
end

local SOUNDS = { "UI_ALERT_ACHIEVEMENT_GAINED", "ACHIEVEMENT_MENU_OPEN", "RAID_WARNING" }
local function sound()
    for _, name in ipairs(SOUNDS) do
        if SOUNDKIT and SOUNDKIT[name] then PlaySound(SOUNDKIT[name]) return end
    end
end

local function notice(due, total, unknown)
    banner = banner or createBanner()
    banner.title:SetText(L.TRAINER_NOTICE_TITLE)
    banner.sub:SetText(L.TRAINER_NOTICE:format(UnitLevel("player"), #due))
    local shown = math.min(#due, MAX_ICONS)
    local width = shown * 36 - 4 + (#due > shown and 40 or 0)
    for k, icon in ipairs(banner.icons) do
        local spell = due[k]
        if spell and k <= shown then
            icon.tex:SetTexture(C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spell.id) or 134400)
            icon.rank:SetText(spell.rank > 1 and spell.rank or "")
            icon.spellID = spell.id
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", banner, "TOP", -width / 2 + (k - 1) * 36, -66)
            icon:Show()
        else
            icon:Hide()
        end
    end
    banner.more:SetText(#due > shown and "+" .. (#due - shown) or "")
    banner.more:ClearAllPoints()
    banner.more:SetPoint("LEFT", banner.icons[math.max(shown, 1)], "RIGHT", 8, 0)
    banner.cost:SetText(costLine(due, total, unknown))
    banner:SetAlpha(1)
    banner:Show()
    banner.anim:Stop()
    banner.anim:Play()
    sound()
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
    if not asked then notice(due, total, unknown) end
    print("   " .. costLine(due, total, unknown))
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
