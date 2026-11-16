-- New spells and ranks onto your action bars: when you learn a spell or a new rank of one (at the trainer, from a
-- quest, a talent), a small window lists it. With a lower rank of it on your bars, "Replace" puts the new rank on
-- every button that has the old one. Not on your bars, "Place" puts it on your cursor: click the bar button you
-- want it on. Passive spells and spells already on a bar (the game places some itself) are left out. Bars cannot
-- be changed in combat: the window waits for the end of it. The Options tab turns it off.
local _, ns = ...
local L = ns.L

local SLOTS = 180           -- every action slot the game has (all the bars and their pages)
local MAX_ROWS = 8
local ROW_H, WIDTH = 34, 400
local pending = {}          -- { id = spellID }, in the order learned
local window
local ranks                 -- [spellID] = its rank, from the trainer's data (nil: not a ranked trainer spell)

local function name(id) return C_Spell.GetSpellName(id) end

local function rankOf(id)
    if not ranks then
        ranks = {}
        for _, spell in ipairs(ZbuildsData and ZbuildsData.trainer and ZbuildsData.trainer[ns.PlayerClass()] or {}) do
            ranks[spell.id] = spell.rank
        end
    end
    return ranks[id]
end

-- Where a spell stands on your bars: the slots holding a lower rank of it (another rank of the same name; with the
-- trainer's data, only a lower one), and whether that very rank is on a bar. Macros are left as they are.
local function onBars(id)
    local lower, here, own, rank = {}, false, name(id), rankOf(id)
    for slot = 1, SLOTS do
        local kind, actionID = GetActionInfo(slot)
        if issecretvalue and (issecretvalue(kind) or issecretvalue(actionID)) then actionID = nil end
        if kind == "spell" and actionID then
            if actionID == id then
                here = true
            elseif own and name(actionID) == own then
                local old = rankOf(actionID)
                if not (old and rank) or old < rank then lower[#lower + 1] = slot end
            end
        end
    end
    return lower, here
end

local function label(id)
    local rank = rankOf(id)
    return rank and rank > 1 and L.TRAINER_RANK:format(name(id) or "?", rank) or (name(id) or "?")
end

local function remove(id)
    for k = #pending, 1, -1 do if pending[k].id == id then table.remove(pending, k) end end
end

-- what is worth offering now: each learned spell with a lower rank on your bars, or not on them at all
local function offers()
    local list = {}
    for _, p in ipairs(pending) do
        local lower, here = onBars(p.id)
        if #lower > 0 then
            list[#list + 1] = { id = p.id, slots = lower }
        elseif not here then
            list[#list + 1] = { id = p.id }
        end
    end
    return list
end

local Refresh

-- bars change only out of combat, and never over what you hold on the cursor
local function cannot()
    if InCombatLockdown() then
        ns.Print(L.NEW_SPELLS_COMBAT)
        return true
    end
    if GetCursorInfo and GetCursorInfo() then
        ns.Print(L.NEW_SPELLS_CURSOR)
        return true
    end
end

-- the new rank on every button with a lower one (picked up and dropped on each: what the old one leaves on the
-- cursor is cleared)
function ns.NewSpellReplace(id)
    if cannot() then return end
    local lower = onBars(id)
    for _, slot in ipairs(lower) do
        C_Spell.PickupSpell(id)
        PlaceAction(slot)
        ClearCursor()
    end
    ns.Print(L.NEW_SPELLS_REPLACED:format(label(id), #lower))
    remove(id)
    Refresh()
end

-- on the cursor, for the button you click next
function ns.NewSpellPlace(id)
    if cannot() then return end
    C_Spell.PickupSpell(id)
    ns.Print(L.NEW_SPELLS_PLACE_HINT)
    remove(id)
    Refresh()
end

function ns.NewSpellSkip(id)
    remove(id)
    Refresh()
end

local function button(parent, width, text, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function create()
    window = CreateFrame("Frame", "ZbuildsNewSpells", UIParent, "BackdropTemplate")
    window:SetSize(WIDTH, 60)
    window:SetPoint("CENTER", 0, 160)
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:SetMovable(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    window:SetBackdropColor(0.05, 0.05, 0.06, 0.94)
    window:SetBackdropBorderColor(0.62, 0.55, 0.38, 0.9)
    window.title = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    window.title:SetPoint("TOPLEFT", 12, -10)
    window.title:SetText(L.NEW_SPELLS_TITLE)
    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() wipe(pending) Refresh() end)
    window.rows = {}
    for k = 1, MAX_ROWS do
        local row = CreateFrame("Frame", nil, window)
        row:SetSize(WIDTH - 20, ROW_H)
        row:SetPoint("TOPLEFT", 10, -30 - (k - 1) * ROW_H)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(26, 26)
        row.icon:SetPoint("LEFT")
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -1)
        row.name:SetWidth(WIDTH - 210)
        row.name:SetJustifyH("LEFT")
        row.note = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.note:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 1)
        row.skip = button(row, 24, "×", function() ns.NewSpellSkip(row.id) end)
        row.skip:SetPoint("RIGHT")
        row.action = button(row, 110, "", function()
            if row.replace then ns.NewSpellReplace(row.id) else ns.NewSpellPlace(row.id) end
        end)
        row.action:SetPoint("RIGHT", row.skip, "LEFT", -4, 0)
        window.rows[k] = row
    end
    window:Hide()
end

function Refresh()
    if not window then create() end
    local list = (ns.Option("newSpells") and not InCombatLockdown()) and offers() or {}
    for k, row in ipairs(window.rows) do
        local o = list[k]
        row:SetShown(o ~= nil)
        if o then
            row.id, row.replace = o.id, o.slots ~= nil
            row.icon:SetTexture(C_Spell.GetSpellTexture(o.id))
            row.name:SetText(label(o.id))
            row.note:SetText(o.slots and L.NEW_SPELLS_LOWER:format(#o.slots) or L.NEW_SPELLS_NOT_ON_BARS)
            row.action:SetText(o.slots and L.NEW_SPELLS_REPLACE or L.NEW_SPELLS_PLACE)
        end
    end
    -- (what no longer needs anything leaves the list)
    local still = {}
    for _, o in ipairs(list) do still[o.id] = true end
    if not InCombatLockdown() then
        for k = #pending, 1, -1 do if not still[pending[k].id] then table.remove(pending, k) end end
    end
    window:SetHeight(40 + math.min(#list, MAX_ROWS) * ROW_H)
    window:SetShown(#list > 0)
end
ns.NewSpellsRefresh = function() Refresh() end

-- what you learned: a newer rank replaces an older one of the same spell waiting in the list
local function learned(id)
    if not (id and ns.Option("newSpells")) then return end
    if C_Spell.IsSpellPassive and C_Spell.IsSpellPassive(id) then return end
    local own, rank = name(id), rankOf(id)
    for k = #pending, 1, -1 do
        local other = pending[k].id
        if other == id then return end
        if own and name(other) == own and (rankOf(other) or 0) < (rank or 0) then table.remove(pending, k) end
    end
    pending[#pending + 1] = { id = id }
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "LEARNED_SPELL_IN_SKILL_LINE", "PLAYER_REGEN_ENABLED", "ACTIONBAR_SLOT_CHANGED" }) do
    if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(event) then
        events:RegisterEvent(event)
    end
end
events:SetScript("OnEvent", function(_, event, id)
    if event == "LEARNED_SPELL_IN_SKILL_LINE" then
        learned(id)
        -- a moment later: several ranks come at once at the trainer, and the game may place some itself
        C_Timer.After(0.5, Refresh)
    elseif #pending > 0 then
        Refresh()   -- out of combat now, or a bar changed (a placed spell leaves the list)
    end
end)
