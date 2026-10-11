-- A banner in the middle of the screen like the game's own level-up one: a dark band fading at both ends between
-- two gold lines, a title, a subtitle, a row of icons and a few lines of text. It slides in, stays a few seconds
-- and fades away; a click closes it. Used on level up (the next talent, the trainer's new spells) and when a
-- Legacy challenge is done. The Options tab turns it off, mutes it and sets how long it stays.
local _, ns = ...

local GOLD = { 1, 0.82, 0 }
local WIDTH, MAX_ICONS, MAX_LINES = 620, 12, 5
local LINE_COLORS = { { 0.95, 0.95, 0.95 }, { 0.8, 0.8, 0.8 }, { 0.7, 0.7, 0.7 }, { 0.7, 0.7, 0.7 }, { 0.7, 0.7, 0.7 } }
local banner

-- A horizontal band that fades out at both ends: two halves meeting in the middle, anchored at the top,
-- the bottom or the centre of the parent, with an inset at the ends. Returns its two textures.
local function band(parent, layer, anchor, y, height, inset, color, alpha)
    local halves = {}
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
        halves[side] = tex
    end
    return halves
end

local function text(parent, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetShadowOffset(1, -1)
    return fs
end

local function iconTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    if self.spellID then
        GameTooltip:SetSpellByID(self.spellID)
    elseif self.link then
        GameTooltip:SetHyperlink(self.link)
    end
    GameTooltip:Show()
end

local function createBanner()
    local f = CreateFrame("Button", nil, UIParent)
    f:SetSize(WIDTH, 144)
    f:SetPoint("TOP", UIParent, "TOP", 0, -170)
    f:SetFrameStrata("HIGH")
    f:Hide()
    -- the dark band is resized with the banner; a darker middle so it reads over snow
    f.backs = {}
    for _, back in ipairs({ band(f, "BACKGROUND", "CENTER", 0, 144, 0, { 0, 0, 0 }, 0.9),
        band(f, "BACKGROUND", "CENTER", 0, 144, 140, { 0, 0, 0 }, 0.5) }) do
        for _, tex in ipairs(back) do f.backs[#f.backs + 1] = tex end
    end
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
        icon.tex = icon:CreateTexture(nil, "OVERLAY")
        icon.tex:SetPoint("TOPLEFT", 1, -1)
        icon.tex:SetPoint("BOTTOMRIGHT", -1, 1)
        icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon.rank = text(icon, 10, { 1, 1, 1 })
        icon.rank:SetPoint("BOTTOMRIGHT", 2, -2)
        icon:SetScript("OnEnter", iconTooltip)
        icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.icons[k] = icon
    end
    f.more = text(f, 14, GOLD)
    f.lines = {}
    for k = 1, MAX_LINES do
        f.lines[k] = text(f, k == 1 and 13 or 11, LINE_COLORS[k])
        f.lines[k]:SetWidth(WIDTH - 60)
    end

    -- in: fade and a short drop into place; then hold; then out
    f.anim = f:CreateAnimationGroup()
    local fadeIn = f.anim:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0) fadeIn:SetToAlpha(1) fadeIn:SetDuration(0.35) fadeIn:SetOrder(1)
    local drop = f.anim:CreateAnimation("Translation")
    drop:SetOffset(0, -14) drop:SetDuration(0.35) drop:SetOrder(1) drop:SetSmoothing("OUT")
    f.fadeOut = f.anim:CreateAnimation("Alpha")
    f.fadeOut:SetFromAlpha(1) f.fadeOut:SetToAlpha(0) f.fadeOut:SetDuration(1.2) f.fadeOut:SetOrder(2)
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

-- The game's own banners in the same spot (level up, toasts, boss and zone banners): ours waits for them to go,
-- checking every half second, and shows anyway after a while so it is never lost.
local GAME_BANNERS = { "LevelUpDisplay", "EventToastManagerFrame", "BossBanner", "ZoneTextFrame" }
local WAIT_STEP, WAIT_TRIES = 0.5, 30

local function gameBannerShown()
    for _, name in ipairs(GAME_BANNERS) do
        local f = _G[name]
        if f and f.IsShown and f:IsShown() then return true end
    end
end

local show

-- spec = { title, sub, icons = { { texture, spellID or link, rank, dim } }, lines = { text, ... } }
-- (empty lines are skipped). Shown once the game's own banner is gone; nothing when the banner is turned off.
function ns.ShowBanner(spec, tries)
    if not ns.Option("banner") then return end
    tries = tries or 0
    if gameBannerShown() and tries < WAIT_TRIES then
        C_Timer.After(WAIT_STEP, function() ns.ShowBanner(spec, tries + 1) end)
        return
    end
    show(spec)
end

function show(spec)
    banner = banner or createBanner()
    banner.title:SetText(spec.title)
    banner.sub:SetText(spec.sub or "")
    local y = -60
    local icons = spec.icons or {}
    local shown = math.min(#icons, MAX_ICONS)
    local width = shown * 36 - 4 + (#icons > shown and 40 or 0)
    for k, icon in ipairs(banner.icons) do
        local item = icons[k]
        if item and k <= shown then
            icon.tex:SetTexture(item.texture or 134400)
            icon.tex:SetDesaturated(item.dim and true or false)
            icon.tex:SetAlpha(item.dim and 0.6 or 1)
            icon.border:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], item.dim and 0.3 or 0.8)
            icon.rank:SetText(item.rank and item.rank > 1 and item.rank or "")
            icon.spellID, icon.link = item.spellID, item.link
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", banner, "TOP", -width / 2 + (k - 1) * 36, y - 6)
            icon:Show()
        else
            icon:Hide()
        end
    end
    banner.more:SetText(#icons > shown and "+" .. (#icons - shown) or "")
    banner.more:ClearAllPoints()
    banner.more:SetPoint("LEFT", banner.icons[math.max(shown, 1)], "RIGHT", 8, 0)
    if shown > 0 then y = y - 44 end
    local used = 0
    for _, line in ipairs(spec.lines or {}) do
        if line and line ~= "" and used < MAX_LINES then
            used = used + 1
            local fs = banner.lines[used]
            fs:SetText(line)
            fs:ClearAllPoints()
            fs:SetPoint("TOP", 0, y)
            fs:Show()
            y = y - (used == 1 and 18 or 15)
        end
    end
    for k = used + 1, MAX_LINES do banner.lines[k]:SetText("") banner.lines[k]:Hide() end
    local height = -y + 10
    banner:SetHeight(height)
    for _, tex in ipairs(banner.backs) do tex:SetHeight(height) end
    banner.fadeOut:SetStartDelay(ns.Option("duration"))
    banner:SetAlpha(1)
    banner:Show()
    banner.anim:Stop()
    banner.anim:Play()
    if ns.Option("sound") then sound() end
end
