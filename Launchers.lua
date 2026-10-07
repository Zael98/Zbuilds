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

function ns.RefreshTalentBar()
    if not bar then return end
    local classToken = ns.PlayerClass()
    local classData, build = ns.ClassData(classToken), ns.SelectedBuild(classToken)
    bar.pick:SetText(build and shorten(build.name, 34) or L.PICK_BUILD)
    bar.learn:SetEnabled(build ~= nil)
    local tree = build and classData and ns.ReadTree(classData)
    local t, i, rank
    if tree then t, i, rank = ns.NextStep(build, classData, tree) end
    bar.next:SetText((t and L.NEXT:format("|cffffd100" .. ns.TalentName(classData, tree, t, i) .. "|r", rank))
        or (tree and ("|cff40d860" .. L.COMPLETE .. "|r")) or "")
end

local function addTalentBar()
    if bar then return end
    for _, frameName in pairs(TALENT_UIS) do
        local talentFrame = _G[frameName]
        if talentFrame then
            bar = CreateFrame("Frame", nil, talentFrame)
            bar:SetSize(talentFrame:GetWidth() - 8, 24)
            bar:SetPoint("BOTTOMLEFT", talentFrame, "TOPLEFT", 4, 2)

            bar.pick = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
            bar.pick:SetSize(260, 22)
            bar.pick:SetPoint("LEFT")
            bar.pick:SetScript("OnClick", openMenu)

            bar.learn = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
            bar.learn:SetSize(140, 22)
            bar.learn:SetText(L.APPLY)
            bar.learn:SetWidth(math.max(140, (bar.learn:GetTextWidth() or 0) + 24))
            bar.learn:SetPoint("LEFT", bar.pick, "RIGHT", 4, 0)
            bar.learn:SetScript("OnClick", function()
                local build = ns.SelectedBuild(ns.PlayerClass())
                if build then ns.LearnAndReport(build, ns.ClassData(ns.PlayerClass())) end
                ns.RefreshTalentBar()
            end)

            bar.next = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            bar.next:SetPoint("LEFT", bar.learn, "RIGHT", 10, 0)

            local open = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
            open:SetSize(90, 22)
            open:SetPoint("RIGHT")
            open:SetText("Zbuilds")
            open:SetScript("OnClick", function() ns.Toggle() end)
            open:SetScript("OnEnter", tooltip)
            open:SetScript("OnLeave", GameTooltip_Hide)
            bar.next:SetPoint("RIGHT", open, "LEFT", -8, 0)
            bar.next:SetJustifyH("LEFT")

            talentFrame:HookScript("OnShow", ns.RefreshTalentBar)
            ns.RefreshTalentBar()
            return
        end
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
