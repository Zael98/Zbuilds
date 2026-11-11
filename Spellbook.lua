-- The trainer in the spellbook: a panel on the right of the game's spellbook (on its spellbook tab only) with
-- every rank of your class and the level that brings it: what you can learn now with its price (red when your
-- gold does not reach it), what each coming level brings, and, when asked, what you already know. Hovering a
-- spell shows the game's tooltip. A button on the window's edge folds the panel away (remembered per account).
-- What is listed comes from ns.TrainingList (Trainer.lua): the same ranks the trainer reminder counts.
local _, ns = ...
local L = ns.L

local WIDTH, ROW_H, HEADER_H, TOP = 280, 20, 24, 58
local BOOK_ICON = "Interface\\Icons\\INV_Misc_Book_09"
local KNOWN_MARK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t"
local window, book, panel, toggle, list, content
local rows, used = {}, 0

-- the game's window and its spellbook tab: Forever's (and retail's) PlayerSpellsFrame, or a classic spellbook
local function host()
    if PlayerSpellsFrame and PlayerSpellsFrame.SpellBookFrame then return PlayerSpellsFrame, PlayerSpellsFrame.SpellBookFrame end
    if SpellBookFrame then return SpellBookFrame, SpellBookFrame end
end

local function kindTag(spell)
    if spell.kind == "pet" then
        return " |cff88aaff(" .. (ns.PlayerClass() == "WARLOCK" and L.SPELLBOOK_DEMON or L.SPELLBOOK_PET) .. ")|r"
    elseif spell.kind == "poison" then
        return " |cff88aaff(" .. L.SPELLBOOK_POISON .. ")|r"
    end
    return ""
end

local function showTooltip(row)
    if not row.spell then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(row.spell.id) else GameTooltip:SetText(ns.RankName(row.spell)) end
    GameTooltip:AddLine(L.SPELLBOOK_TIP_LEVEL:format(row.spell.level), 1, 0.82, 0)
    local cost = ns.TrainerPrice(row.spell)
    if cost then GameTooltip:AddLine(L.TRAINER_COST:format(ns.Money(cost)), 1, 1, 1) end
    GameTooltip:Show()
end

local function makeRow()
    local row = CreateFrame("Button", nil, content)
    row:SetHeight(ROW_H)
    row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_H - 4, ROW_H - 4)
    row.icon:SetPoint("LEFT", 4, 0)
    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.right:SetPoint("RIGHT", -4, 0)
    row.right:SetJustifyH("RIGHT")
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
    row.name:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.line = row:CreateTexture(nil, "ARTWORK")
    row.line:SetHeight(1)
    row.line:SetPoint("BOTTOMLEFT", 2, 1)
    row.line:SetPoint("BOTTOMRIGHT", -2, 1)
    row.line:SetColorTexture(0.62, 0.55, 0.38, 0.45)
    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 1, 1, 0.08)
    row:SetScript("OnEnter", showTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function take(y, height)
    used = used + 1
    local row = rows[used] or makeRow()
    rows[used] = row
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    row:SetHeight(height)
    row:Show()
    return row
end

local function header(y, text)
    local row = take(y, HEADER_H)
    row.spell, row.state = nil, "header"
    row.icon:Hide()
    row.line:Show()
    row.hl:Hide()
    row.name:SetText(text)
    row.name:SetTextColor(1, 0.82, 0)
    row.right:SetText("")
    return y + HEADER_H
end

-- now: white, its price red when your gold does not reach it; later: grey; known: dim with a tick
local function spellRow(y, spell, state, gold)
    local row = take(y, ROW_H)
    row.spell, row.state = spell, state
    row.icon:Show()
    row.icon:SetTexture(C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spell.id) or 134400)
    row.icon:SetDesaturated(state ~= "now")
    row.line:Hide()
    row.hl:Show()
    row.name:SetText(ns.RankName(spell) .. kindTag(spell))
    local shade = state == "now" and 1 or state == "later" and 0.72 or 0.5
    row.name:SetTextColor(shade, shade, shade)
    local cost = ns.TrainerPrice(spell)
    if state == "known" then
        row.right:SetText(KNOWN_MARK)
    elseif cost then
        row.right:SetText(ns.Money(cost))
        if state == "now" and cost > gold then row.right:SetTextColor(1, 0.31, 0.31) else row.right:SetTextColor(shade, shade, shade) end
    else
        local source = spell.source and L["TRAINER_SOURCE_" .. spell.source:upper()]
        row.right:SetText(source or "")
        row.right:SetTextColor(shade, shade, shade)
    end
    return y + ROW_H
end

local function paint()
    if not (panel and panel:IsShown()) then return end
    used = 0
    local r, gold = ns.TrainingList(), GetMoney and GetMoney() or 0
    local total = 0
    for _, spell in ipairs(r.now) do total = total + (ns.TrainerPrice(spell) or 0) end
    local y = header(0, #r.now > 0 and L.SPELLBOOK_NOW:format(#r.now, ns.Money(total)) or L.SPELLBOOK_NOW_NONE)
    for _, spell in ipairs(r.now) do y = spellRow(y, spell, "now", gold) end
    for _, group in ipairs(r.later) do
        y = header(y + 4, L.SPELLBOOK_LEVEL:format(group[1]))
        for _, spell in ipairs(group[2]) do y = spellRow(y, spell, "later", gold) end
    end
    if ns.Option("trainingKnown") and #r.known > 0 then
        y = header(y + 4, L.SPELLBOOK_KNOWN:format(#r.known))
        for _, spell in ipairs(r.known) do y = spellRow(y, spell, "known", gold) end
    end
    for k = used + 1, #rows do rows[k]:Hide() end
    content:SetHeight(math.max(y, 1))
    panel.sub:SetText(L.SPELLBOOK_SUB:format(UnitLevel("player"), ns.Money(gold)))
    panel.known:SetChecked(ns.Option("trainingKnown"))
end
ns.RefreshTraining = paint

-- shown or folded (nil: the other way round); the choice is kept
local function setOpen(open)
    if open == nil then open = not ns.Option("trainingPanel") end
    ns.SetOption("trainingPanel", open)
    panel:SetShown(open)
    toggle:SetShown(not open)
    paint()
end
ns.ToggleTraining = setOpen

local function create()
    window, book = host()
    if not book or panel then return end
    -- on the spellbook tab: shown and hidden with it, beside the window
    panel = CreateFrame("Frame", "ZbuildsTrainingPanel", book, "BackdropTemplate")
    panel:SetWidth(WIDTH)
    panel:SetPoint("TOPLEFT", window, "TOPRIGHT", 2, 0)
    panel:SetPoint("BOTTOMLEFT", window, "BOTTOMRIGHT", 2, 0)
    panel:EnableMouse(true)
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    panel:SetBackdropColor(0.05, 0.05, 0.06, 0.92)
    panel:SetBackdropBorderColor(0.62, 0.55, 0.38, 0.9)
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOPLEFT", 12, -10)
    panel.title:SetText(L.SPELLBOOK_TITLE)
    panel.sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.sub:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -4)
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() setOpen(false) end)
    panel.known = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    panel.known:SetSize(22, 22)
    panel.known:SetPoint("BOTTOMLEFT", 8, 6)
    panel.known.label = panel.known:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.known.label:SetPoint("LEFT", panel.known, "RIGHT", 2, 0)
    panel.known.label:SetText(L.SPELLBOOK_SHOW_KNOWN)
    panel.known:SetScript("OnClick", function(self)
        ns.SetOption("trainingKnown", self:GetChecked() and true or false)
        paint()
    end)
    list = CreateFrame("ScrollFrame", nil, panel)
    list:SetPoint("TOPLEFT", 8, -TOP + 12)
    list:SetPoint("BOTTOMRIGHT", -8, 34)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, delta)
        local room = math.max(0, content:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(room, self:GetVerticalScroll() - delta * ROW_H * 3)))
    end)
    content = CreateFrame("Frame", nil, list)
    content:SetWidth(WIDTH - 16)
    list:SetScrollChild(content)
    panel:SetScript("OnShow", paint)
    -- folded: a book on the window's edge brings it back
    toggle = CreateFrame("Button", nil, book)
    toggle:SetSize(34, 34)
    toggle:SetPoint("TOPLEFT", window, "TOPRIGHT", 2, -40)
    toggle:SetNormalTexture(BOOK_ICON)
    toggle:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    toggle:SetScript("OnClick", function() setOpen(true) end)
    toggle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.SPELLBOOK_TITLE, 1, 0.82, 0)
        GameTooltip:AddLine(L.SPELLBOOK_TIP, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    toggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
    setOpen(ns.Option("trainingPanel"))
end

-- for the tests: the rows shown, as "state|text|right"
function ns.TrainingLines()
    local out = {}
    for k = 1, used do
        local row = rows[k]
        out[#out + 1] = row.state .. "|" .. tostring(row.name:GetText()) .. "|" .. tostring(row.right:GetText())
    end
    return out, panel ~= nil and panel:IsShown()
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "ADDON_LOADED", "PLAYER_LEVEL_UP", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB",
    "PLAYER_MONEY", "TRAINER_UPDATE", "UNIT_PET" }) do
    if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(event) then
        events:RegisterEvent(event)
    end
end
events:SetScript("OnEvent", function(_, event, arg)
    if event == "PLAYER_LOGIN" or (event == "ADDON_LOADED" and (arg == "Blizzard_PlayerSpells" or arg == "Blizzard_SpellBook")) then
        create()
    elseif event == "PLAYER_LEVEL_UP" then
        C_Timer.After(1, paint)   -- (UnitLevel catches up a moment later)
    elseif event ~= "ADDON_LOADED" then
        paint()
    end
end)
