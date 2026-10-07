-- Ways to open the window besides /zb: a minimap button, the game's addon menu (compartment)
-- and a button on the game's talent window.
local _, ns = ...
local L = ns.L

local LOGO = "Interface\\AddOns\\Zbuilds\\media\\logo"
-- the game's talent window, depending on the client generation; Forever loads one of these on demand
local TALENT_UIS = { Blizzard_PlayerSpells = "PlayerSpellsFrame", Blizzard_ClassTalentUI = "ClassTalentFrame",
    Blizzard_TalentUI = "PlayerTalentFrame" }

local function settings()
    ZbuildsDB = ZbuildsDB or {}
    ZbuildsDB.minimap = ZbuildsDB.minimap or { angle = 200 }
    return ZbuildsDB.minimap
end

local function tooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:SetText("Zbuilds", 1, 0.82, 0)
    GameTooltip:AddLine(L.LAUNCHER_TIP, 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end

-- ---------------------------------------------------------------- minimap button

local button

local function place()
    local angle = math.rad(settings().angle)
    local radius = Minimap:GetWidth() / 2 + 6
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function createButton()
    button = CreateFrame("Button", "ZbuildsMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(LOGO)
    icon:SetSize(19, 19)
    icon:SetPoint("TOPLEFT", 7, -6)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    button:SetScript("OnClick", function() ns.Toggle() end)
    button:SetScript("OnEnter", tooltip)
    button:SetScript("OnLeave", GameTooltip_Hide)
    -- drag around the minimap edge; the angle is saved per account
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local scale, cx, cy = Minimap:GetEffectiveScale(), Minimap:GetCenter()
            settings().angle = math.deg(math.atan2(y / scale - cy, x / scale - cx))
            place()
        end)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    place()
end

local function refreshButton()
    if not button then createButton() end
    button:SetShown(not settings().hide)
end

function ns.ToggleMinimapButton()
    settings().hide = not settings().hide
    refreshButton()
end

-- ---------------------------------------------------------------- addon compartment (named in the .toc)

function Zbuilds_OnCompartmentClick()
    ns.Toggle()
end

function Zbuilds_OnCompartmentEnter(_, owner)
    tooltip(owner)
end

function Zbuilds_OnCompartmentLeave()
    GameTooltip:Hide()
end

-- ---------------------------------------------------------------- bar on the game's talent window
-- Forever has no saved talent loadouts (talents are unlearned at a trainer, like Classic), so the bar
-- offers Zbuilds' own builds: pick one, learn its free points, see the next talent.

local bar

local function leadTree(build)
    local best = 1
    for t = 2, #build.points do if build.points[t] > build.points[best] then best = t end end
    return best
end

local function shorten(text, size)
    return #text > size and (text:sub(1, size - 3) .. "...") or text
end

-- The game's own menu: builds of your class under a title per tree, the chosen one ticked.
local function openMenu(owner)
    local classToken = ns.PlayerClass()
    local classData = ns.ClassData(classToken)
    if not (classData and MenuUtil and MenuUtil.CreateContextMenu) then return ns.Toggle() end
    local selected = ns.SelectedBuild(classToken)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        if root.SetScrollMode then root:SetScrollMode(460) end
        local builds = ns.BuildsFor(classToken)
        for t, tree in ipairs(classData.trees) do
            root:CreateTitle(tree.name)
            for _, build in ipairs(builds) do
                if leadTree(build) == t then
                    local label = ("%s  |cff888888%s · %s|r"):format(shorten(build.name, 48), table.concat(build.points, "/"),
                        ns.SourceName(build.source))
                    root:CreateRadio(label, function() return build == selected end, function() ns.Select(build) end)
                end
            end
        end
    end)
end

-- Look of the bar: dark panels with a thin gold edge, like the game's "Unspent Talents" box.
local WHITE = "Interface\\Buttons\\WHITE8x8"
local GOLD = { 1, 0.82, 0 }
local UPCOMING = 3 -- points predicted: the next one glows on the tree, the following ones are numbered

local function panel(frame, alpha)
    if not frame.SetBackdrop then Mixin(frame, BackdropTemplateMixin) end
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    frame:SetBackdropColor(0, 0, 0, alpha or 0.6)
    frame:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.45)
    return frame
end

local function label(parent, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size, "")
    fs:SetTextColor(unpack(color or { 1, 1, 1 }))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function icon(parent, size)
    local tex = parent:CreateTexture(nil, "ARTWORK")
    tex:SetSize(size, size)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return tex
end

local function spellTooltip(self)
    if not self.spell then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetSpellByID(self.spell)
    if self.note then GameTooltip:AddLine(self.note, GOLD[1], GOLD[2], GOLD[3]) end
    GameTooltip:Show()
end

local function hoverGold(self) self:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1) end
local function hoverOff(self) self:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.45) end

-- ---- prediction on the game's own talent buttons

local nodeButtons, marks = {}, {}

-- The game's talent buttons, found by the trait node they show (retail-style buttons know their node).
local function nodeOf(frame)
    if frame.GetNodeID then
        local ok, id = pcall(frame.GetNodeID, frame)
        if ok and id then return id end
    end
    return frame.nodeID or (frame.nodeInfo and frame.nodeInfo.ID)
end

local function scanButtons(frame, depth)
    if depth > 8 then return end
    for _, child in ipairs({ frame:GetChildren() }) do
        local id = nodeOf(child)
        if id then
            if child:IsShown() then nodeButtons[id] = child end
        else
            scanButtons(child, depth + 1)
        end
    end
end

-- The game reuses its buttons when it redraws the tree, so a remembered button is checked again
-- and the tree scanned anew when it now shows another talent.
local function buttonFor(talentFrame, nodeID)
    local button = nodeButtons[nodeID]
    if not (button and nodeOf(button) == nodeID and button:IsShown()) then
        wipe(nodeButtons)
        scanButtons(talentFrame, 0)
        button = nodeButtons[nodeID]
    end
    return button
end

-- A mark over a talent button: a pulsing gold glow for the next point, a numbered badge for all.
local function mark(k)
    if marks[k] then return marks[k] end
    local m = CreateFrame("Frame")
    m.glow = m:CreateTexture(nil, "OVERLAY")
    m.glow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    m.glow:SetBlendMode("ADD")
    m.glow:SetPoint("TOPLEFT", -10, 10)
    m.glow:SetPoint("BOTTOMRIGHT", 10, -10)
    m.pulse = m.glow:CreateAnimationGroup()
    m.pulse:SetLooping("BOUNCE")
    local fade = m.pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.25)
    fade:SetDuration(0.7)
    m.badge = panel(CreateFrame("Frame", nil, m, "BackdropTemplate"), 0.85)
    m.badge:SetSize(16, 16)
    m.badge:SetPoint("TOPLEFT", -6, 6)
    m.number = label(m.badge, 11, GOLD)
    m.number:SetPoint("CENTER", 0, 0)
    marks[k] = m
    return m
end

local function showMarks(talentFrame, tree, steps)
    for _, m in ipairs(marks) do m:Hide() m.pulse:Stop() end
    local shown = {}
    for k, step in ipairs(steps) do
        local nodeID = tree.node[step.t][step.i]
        local button = nodeID and buttonFor(talentFrame, nodeID)
        -- one mark per talent: a talent wanted twice in a row keeps the earliest number
        if button and not shown[nodeID] then
            shown[nodeID] = true
            local m = mark(k)
            m:SetParent(button)
            m:SetAllPoints(button)
            m:SetFrameLevel(button:GetFrameLevel() + 5)
            m.number:SetText(k)
            m.glow:SetShown(k == 1)
            if k == 1 then m.pulse:Play() end
            m:Show()
        end
    end
end

-- ---- the bar

-- "Next · level 31", or "Next · now" when your free points already cover it
local function stepWhen(step)
    return step.level and L.NEXT_AT:format(step.level) or L.NEXT_NOW
end

function ns.RefreshTalentBar()
    if not bar then return end
    local classToken = ns.PlayerClass()
    local classData, build = ns.ClassData(classToken), ns.SelectedBuild(classToken)
    local lead = build and classData and classData.trees[leadTree(build)]
    bar.pick.icon:SetTexture("Interface\\Icons\\" .. (lead and lead.icon or "inv_misc_book_09"))
    bar.pick.text:SetText(build and build.name or L.PICK_BUILD)
    bar.pick.sub:SetText(build and (table.concat(build.points, "/") .. "  ·  " .. ns.SourceName(build.source)) or "")

    local tree = build and classData and ns.ReadTree(classData)
    local steps = tree and ns.UpcomingSteps(build, classData, tree, UPCOMING) or {}
    local first = steps[1]
    bar.next:SetShown(first ~= nil)
    bar.done:SetShown(tree ~= nil and first == nil)
    if first then
        local tal = classData.trees[first.t].talents[first.i]
        bar.next.icon:SetTexture("Interface\\Icons\\" .. (tal.icon or "inv_misc_questionmark"))
        bar.next.title:SetText(stepWhen(first))
        bar.next.text:SetText(("%s  |cffffd100%d/%d|r"):format(ns.TalentName(classData, tree, first.t, first.i), first.rank, tal.max))
        bar.next.spell, bar.next.note = ns.TalentSpell(classData, tree, first.t, first.i), stepWhen(first)
    end
    for k = 2, UPCOMING do
        local after, step = bar.after[k - 1], steps[k]
        after:SetShown(step ~= nil)
        if step then
            local tal = classData.trees[step.t].talents[step.i]
            after.icon:SetTexture("Interface\\Icons\\" .. (tal.icon or "inv_misc_questionmark"))
            after.number:SetText(k)
            after.spell, after.note = ns.TalentSpell(classData, tree, step.t, step.i), stepWhen(step)
        end
    end

    local free = tree and ns.FreePoints(tree) or 0
    bar.learn:SetEnabled(first ~= nil and free > 0)
    bar.learn.text:SetText(free > 0 and L.LEARN_N:format(free) or L.NO_FREE)
    bar.learn.text:SetTextColor(unpack(free > 0 and first and GOLD or { 0.5, 0.5, 0.5 }))

    if tree and bar.talentFrame:IsShown() then showMarks(bar.talentFrame, tree, steps) end
end

local function createBar(talentFrame)
    bar = CreateFrame("Frame", nil, talentFrame)
    bar.talentFrame = talentFrame
    -- above the window's own art (its band and backgrounds are child frames several levels up)
    bar:SetFrameLevel(talentFrame:GetFrameLevel() + 500)
    -- centred on the gold band under the spec tabs, left of the game's "Unspent Talents" box
    local function place()
        local w, h = talentFrame:GetWidth(), talentFrame:GetHeight()
        bar:ClearAllPoints()
        bar:SetPoint("LEFT", talentFrame, "TOPLEFT", w * 0.03, -h * 0.136)
        bar:SetSize(w * 0.76, 36)
    end
    place()

    -- build picker: lead tree icon, name, points and source, an arrow; opens the game's menu
    bar.pick = panel(CreateFrame("Button", nil, bar, "BackdropTemplate"))
    bar.pick:SetSize(300, 36)
    bar.pick:SetPoint("LEFT")
    bar.pick.icon = icon(bar.pick, 28)
    bar.pick.icon:SetPoint("LEFT", 5, 0)
    bar.pick.text = label(bar.pick, 12)
    bar.pick.text:SetPoint("TOPLEFT", bar.pick.icon, "TOPRIGHT", 8, -2)
    bar.pick.text:SetPoint("RIGHT", -26, 0)
    bar.pick.sub = label(bar.pick, 10, { 0.65, 0.65, 0.65 })
    bar.pick.sub:SetPoint("BOTTOMLEFT", bar.pick.icon, "BOTTOMRIGHT", 8, 2)
    bar.pick.sub:SetPoint("RIGHT", -26, 0)
    local arrow = bar.pick:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
    arrow:SetSize(22, 22)
    arrow:SetPoint("RIGHT", -3, 0)
    bar.pick:SetScript("OnClick", openMenu)
    bar.pick:SetScript("OnEnter", hoverGold)
    bar.pick:SetScript("OnLeave", hoverOff)

    -- the predicted next point, then the two after it
    bar.next = panel(CreateFrame("Frame", nil, bar, "BackdropTemplate"))
    bar.next:SetSize(250, 36)
    bar.next:SetPoint("LEFT", bar.pick, "RIGHT", 8, 0)
    bar.next:EnableMouse(true)
    bar.next.icon = icon(bar.next, 28)
    bar.next.icon:SetPoint("LEFT", 5, 0)
    bar.next.title = label(bar.next, 10, GOLD)
    bar.next.title:SetPoint("TOPLEFT", bar.next.icon, "TOPRIGHT", 8, -2)
    bar.next.text = label(bar.next, 12)
    bar.next.text:SetPoint("BOTTOMLEFT", bar.next.icon, "BOTTOMRIGHT", 8, 2)
    bar.next.text:SetPoint("RIGHT", -6, 0)
    bar.next:SetScript("OnEnter", spellTooltip)
    bar.next:SetScript("OnLeave", GameTooltip_Hide)
    bar.done = label(bar, 12, { 0.25, 0.85, 0.35 })
    bar.done:SetPoint("LEFT", bar.pick, "RIGHT", 14, 0)
    bar.done:SetText(L.COMPLETE)

    bar.after = {}
    for k = 2, UPCOMING do
        local a = panel(CreateFrame("Frame", nil, bar, "BackdropTemplate"), 0.5)
        a:SetSize(28, 28)
        a:SetPoint("LEFT", k == 2 and bar.next or bar.after[k - 2], "RIGHT", 6, 0)
        a:EnableMouse(true)
        a.icon = icon(a, 24)
        a.icon:SetPoint("CENTER")
        a.icon:SetAlpha(0.8)
        a.number = label(a, 10, GOLD)
        a.number:SetPoint("BOTTOMRIGHT", 3, -3)
        a:SetScript("OnEnter", spellTooltip)
        a:SetScript("OnLeave", GameTooltip_Hide)
        bar.after[k - 1] = a
    end

    -- learn the free points of the build
    bar.learn = panel(CreateFrame("Button", nil, bar, "BackdropTemplate"), 0.75)
    bar.learn:SetSize(150, 30)
    bar.learn:SetPoint("LEFT", bar.after[#bar.after], "RIGHT", 12, 0)
    bar.learn:SetBackdropColor(0.1, 0.26, 0.12, 0.9)
    bar.learn.text = label(bar.learn, 12, GOLD)
    bar.learn.text:SetPoint("CENTER")
    bar.learn:SetScript("OnClick", function()
        local build = ns.SelectedBuild(ns.PlayerClass())
        if build then ns.LearnAndReport(build, ns.ClassData(ns.PlayerClass())) end
        ns.RefreshTalentBar()
    end)
    bar.learn:SetScript("OnEnter", hoverGold)
    bar.learn:SetScript("OnLeave", hoverOff)

    -- open Zbuilds: its logo
    local open = panel(CreateFrame("Button", nil, bar, "BackdropTemplate"), 0.75)
    open:SetSize(30, 30)
    open:SetPoint("LEFT", bar.learn, "RIGHT", 8, 0)
    local logo = open:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(LOGO)
    logo:SetPoint("TOPLEFT", 3, -3)
    logo:SetPoint("BOTTOMRIGHT", -3, 3)
    open:SetScript("OnClick", function() ns.Toggle() end)
    open:SetScript("OnEnter", function(self) hoverGold(self) tooltip(self) end)
    open:SetScript("OnLeave", function(self) hoverOff(self) GameTooltip:Hide() end)

    talentFrame:HookScript("OnShow", function() place() ns.RefreshTalentBar() end)
    talentFrame:HookScript("OnSizeChanged", place)
    ns.RefreshTalentBar()
end

local function addTalentBar()
    if bar then return end
    for _, frameName in pairs(TALENT_UIS) do
        if _G[frameName] then return createBar(_G[frameName]) end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, addon)
    if event == "PLAYER_LOGIN" then
        refreshButton()
        addTalentBar()
    elseif TALENT_UIS[addon] then
        addTalentBar()
    end
end)
