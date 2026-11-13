-- Gear advice on item tooltips: how much better or worse an item is than what you wear in that slot, for your
-- specialisation (the tree with most points of your talents, or of your selected build before you have any).
-- Each role weighs the item's stats (the game's GetItemStats); the comparison is against the weaker item of two
-- slots (rings, trinkets, one-handers) and against main and off hand together for a two-hander. Equip effects
-- written as text ("+1% crit") are not stats the game gives, so they do not count. Quest rewards, loot and
-- vendors all use the item tooltip, so it shows there too. Option "gear".
local _, ns = ...
local L = ns.L

-- weight of one point of each stat, per role (1 = the role's main stat)
local S = {
    STR = "ITEM_MOD_STRENGTH_SHORT", AGI = "ITEM_MOD_AGILITY_SHORT", STA = "ITEM_MOD_STAMINA_SHORT",
    INT = "ITEM_MOD_INTELLECT_SHORT", SPI = "ITEM_MOD_SPIRIT_SHORT", AP = "ITEM_MOD_ATTACK_POWER_SHORT",
    RAP = "ITEM_MOD_RANGED_ATTACK_POWER_SHORT", CRIT = "ITEM_MOD_CRIT_RATING_SHORT", HIT = "ITEM_MOD_HIT_RATING_SHORT",
    SP = "ITEM_MOD_SPELL_POWER_SHORT", HEAL = "ITEM_MOD_SPELL_HEALING_DONE_SHORT", MP5 = "ITEM_MOD_MANA_REGENERATION_SHORT",
    DEF = "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT", DODGE = "ITEM_MOD_DODGE_RATING_SHORT", PARRY = "ITEM_MOD_PARRY_RATING_SHORT",
    BLOCK = "ITEM_MOD_BLOCK_RATING_SHORT", ARMOR = "RESISTANCE0_NAME", DPS = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT",
}
local ROLES = {
    strength = { STR = 1, AGI = 0.6, AP = 0.5, STA = 0.2, CRIT = 0.9, HIT = 1, DPS = 3 },
    agility = { AGI = 1, STR = 0.5, AP = 0.5, STA = 0.2, CRIT = 0.9, HIT = 1, DPS = 3 },
    hunter = { AGI = 1, AP = 0.4, RAP = 0.45, INT = 0.3, STA = 0.2, CRIT = 0.9, HIT = 1, DPS = 2 },
    feral = { AGI = 1, STR = 1, STA = 0.5, AP = 0.5, ARMOR = 0.02, CRIT = 0.8, HIT = 0.8 },
    tank = { STA = 1, ARMOR = 0.02, DEF = 1.5, DODGE = 1.2, PARRY = 1, BLOCK = 0.5, STR = 0.5, AGI = 0.6, HIT = 0.3, DPS = 1 },
    caster = { SP = 1, INT = 0.4, SPI = 0.1, STA = 0.1, CRIT = 0.8, HIT = 0.9, MP5 = 0.3 },
    healer = { HEAL = 1, SP = 1, INT = 0.6, SPI = 0.4, MP5 = 1.5, STA = 0.1, CRIT = 0.5 },
}
-- a talent tree's role, by its name in the data (English)
local TREE_ROLE = {
    Arms = "strength", Fury = "strength", Retribution = "strength", Enhancement = "strength",
    Protection = "tank", Assassination = "agility", Combat = "agility", Subtlety = "agility",
    ["Beast Mastery"] = "hunter", Marksmanship = "hunter", Survival = "hunter", ["Feral Combat"] = "feral", Feral = "feral",
    Holy = "healer", Discipline = "healer", Restoration = "healer",
    Shadow = "caster", Elemental = "caster", Balance = "caster", Arcane = "caster", Fire = "caster", Frost = "caster",
    Affliction = "caster", Demonology = "caster", Destruction = "caster",
}

-- the slots an item goes in (the game's inventory slot ids)
local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
    INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 },
    INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
    INVTYPE_RELIC = { 18 },
}

-- your specialisation's tree: the one with most points spent (the game's), else of your selected build
function ns.GearTree()
    local class = ns.PlayerClass()
    local classData = ns.ClassData(class)
    if not classData then return end
    local points = {}
    local tree = ns.ReadTree and ns.ReadTree(classData)
    if tree and tree.rank then
        for t in ipairs(classData.trees) do
            local sum = 0
            for _, r in ipairs(tree.rank[t] or {}) do sum = sum + r end
            points[t] = sum
        end
    end
    local best, most = nil, 0
    for t, p in pairs(points) do
        if p > most then best, most = t, p end
    end
    if not best then
        local build = ns.SelectedBuild(class)
        for t, p in ipairs(build and build.points or {}) do
            if p > most then best, most = t, p end
        end
    end
    return best and classData.trees[best]
end

function ns.GearRole()
    local tree = ns.GearTree()
    return tree and TREE_ROLE[tree.name], tree
end

-- an item's worth for a role (nil: no item)
function ns.GearScore(link, role)
    if not link then return nil end
    local stats = C_Item.GetItemStats and C_Item.GetItemStats(link) or (GetItemStats and GetItemStats(link))
    local weights, score = ROLES[role] or {}, 0
    for key, w in pairs(weights) do score = score + (stats and stats[S[key]] or 0) * w end
    return score
end

-- how it compares with what you wear: percent (nil: cannot tell), and whether the slot is empty
function ns.GearCompare(link, role)
    local equipLoc = select(4, C_Item.GetItemInfoInstant(link))
    local slots = SLOTS[equipLoc]
    if not slots then return end
    local new = ns.GearScore(link, role)
    local old
    if equipLoc == "INVTYPE_2HWEAPON" then
        local mh, oh = GetInventoryItemLink("player", 16), GetInventoryItemLink("player", 17)
        if not mh and not oh then return nil, true end
        old = (ns.GearScore(mh, role) or 0) + (ns.GearScore(oh, role) or 0)
    else
        for _, slot in ipairs(slots) do
            local worn = GetInventoryItemLink("player", slot)
            if not worn then return nil, true end
            if worn == link then return end   -- (the one you wear)
            local s = ns.GearScore(worn, role)
            if not old or s < old then old = s end
        end
    end
    if old <= 0 then return new > 0 and 100 or nil end
    return (new - old) / old * 100
end

-- the tooltip line: { text, r, g, b } or nil
function ns.GearLine(link)
    if not (link and ns.Option("gear")) then return end
    if C_Item.IsEquippableItem and not C_Item.IsEquippableItem(link) then return end
    local role, tree = ns.GearRole()
    if not role then return end
    local pct, empty = ns.GearCompare(link, role)
    if empty then return { L.GEAR_EMPTY:format(tree.name), 0.4, 1, 0.4 } end
    if not pct then return end
    pct = math.floor(pct + 0.5)
    if pct > 0 then return { L.GEAR_BETTER:format(tree.name, pct), 0.4, 1, 0.4 } end
    if pct < 0 then return { L.GEAR_WORSE:format(tree.name, -pct), 1, 0.4, 0.4 } end
    return { L.GEAR_SAME:format(tree.name), 0.8, 0.8, 0.8 }
end

local function OnItemTooltip(tip)
    if tip ~= GameTooltip and tip ~= ItemRefTooltip then return end
    local ok, _, link = pcall(tip.GetItem, tip)
    if not ok then return end
    local line = ns.GearLine(link)
    if line then
        tip:AddLine(line[1], line[2], line[3], line[4])
        tip:Show()
    end
end
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
elseif GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetItem", OnItemTooltip)
end
