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

-- ---------------------------------------------------------------- button on the game's talent window

local talentButtonDone

local function addTalentButton()
    if talentButtonDone then return end
    for _, frameName in pairs(TALENT_UIS) do
        local talentFrame = _G[frameName]
        if talentFrame then
            local b = CreateFrame("Button", nil, talentFrame, "UIPanelButtonTemplate")
            b:SetSize(90, 22)
            b:SetPoint("BOTTOMRIGHT", talentFrame, "TOPRIGHT", -4, 2)
            b:SetText("Zbuilds")
            b:SetScript("OnClick", function() ns.Toggle() end)
            b:SetScript("OnEnter", tooltip)
            b:SetScript("OnLeave", GameTooltip_Hide)
            talentButtonDone = true
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
        addTalentButton()
    elseif TALENT_UIS[addon] then
        addTalentButton()
    end
end)
