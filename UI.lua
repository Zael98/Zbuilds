-- Window: flat dark style. Left: grouped, searchable build list. Right: the selected build over the
-- three trees, either against your current talents or against a second build (compare mode).
local _, ns = ...
local L = ns.L

local WHITE = "Interface\\Buttons\\WHITE8x8"
local PAD, HEADER_H = 12, 34
local LIST_W, ROW_H, GROUP_H = 290, 42, 24
local CELL, GAP = 36, 10
local CARD_HEAD = 46
local CARD_W = 4 * (CELL + GAP) - GAP + 2 * PAD
local CARD_H = CARD_HEAD + 7 * (CELL + GAP) - GAP + PAD
local TREES_W = 3 * CARD_W + 2 * 8
local WIDTH = PAD + LIST_W + 16 + TREES_W + PAD
local HEIGHT = 728
local MAX_POINTS = 51
local STAR = "Interface\\COMMON\\FavoritesIcon"
-- point order timeline: two rows of talent icons under the trees
local TL_ICON, TL_STEP, TL_PER_ROW, TL_ROW_H = 21, 23, 26, 32
local TL_H = 18 + 2 * TL_ROW_H
local LOGO = "Interface\\AddOns\\Zbuilds\\media\\logo"

local CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local SOURCES = { "Talents Forever", "Icy Veins", "Warcraft Tavern", "Method", "WoW Forever Builds", "Guías extra",
    "Mis enlaces" }
-- short names for the filter chips (the list headers keep the full ones)
local SOURCE_SHORT = { ["Talents Forever"] = "T. Forever", ["WoW Forever Builds"] = "WF Builds",
    ["Warcraft Tavern"] = "Tavern" }
local CHIPS_PER_ROW = 4
local CATEGORIES = { "all", "Leveo", "PvE", "PvP", "none" }

local C = {
    bg = { 0.05, 0.05, 0.06, 0.95 },
    panel = { 0.09, 0.09, 0.11, 1 },
    raised = { 0.14, 0.14, 0.17, 1 },
    selected = { 0.16, 0.16, 0.21, 1 },
    line = { 0.2, 0.2, 0.23, 1 },
    text = { 0.92, 0.92, 0.92 },
    dim = { 0.5, 0.5, 0.55 },
    done = { 0.25, 0.85, 0.35 },
    pending = { 1, 0.78, 0.2 },
    over = { 1, 0.3, 0.3 },
    onlyA = { 0.3, 0.6, 1 },
    onlyB = { 1, 0.55, 0.15 },
    differ = { 1, 0.85, 0.2 },
    same = { 0.85, 0.85, 0.85 },
    category = { Leveo = { 0.4, 0.85, 0.5 }, PvE = { 0.45, 0.68, 1 }, PvP = { 1, 0.42, 0.42 } },
    -- one colour per tree, shared by its card stripe, the list's points bar and the timeline
    tree = { { 0.72, 0.52, 1 }, { 0.35, 0.85, 0.78 }, { 1, 0.5, 0.66 } },
    source = { ["Talents Forever"] = { 0.5, 0.88, 0.82 }, ["Icy Veins"] = { 0.45, 0.72, 1 },
        ["Warcraft Tavern"] = { 0.95, 0.6, 0.35 }, ["Method"] = { 1, 0.42, 0.5 }, ["WoW Forever Builds"] = { 0.62, 0.86, 0.4 },
        ["Guías extra"] = { 0.8, 0.6, 1 }, ["Mis enlaces"] = { 1, 0.82, 0 } },
}

local frame
-- spec: tree index of the open tab (nil = pick the character's current one)
-- preview: number of points of the build shown (the build at a level), nil = the whole build
local state = { class = nil, spec = nil, category = "all", build = nil, compare = nil, search = "", hidden = {}, collapsed = {},
    preview = nil, previewOf = nil, hideBeta = false }
local rows, cells, cards, specTabs, categoryChips, steps, diffChips = {}, {}, {}, {}, {}, {}, {}
local compareSummary

-- ---------------------------------------------------------------- flat widgets

local function hex(c) return ("ff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255) end
local function paint(text, c) return "|c" .. hex(c) .. text .. "|r" end

-- a coloured square for legends (the game font has no "■")
local function swatch(c, label)
    return ("|TInterface\\Buttons\\WHITE8x8:10:10:0:0:8:8:0:8:0:8:%d:%d:%d|t "):format(c[1] * 255, c[2] * 255, c[3] * 255)
        .. paint(label, c)
end

local function classColor(token)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    return c and { c.r, c.g, c.b } or C.pending
end

local function flat(f, bg, border, edge)
    if not f.SetBackdrop then Mixin(f, BackdropTemplateMixin) end
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = edge or 1 })
    f:SetBackdropColor(unpack(bg or C.panel))
    f:SetBackdropBorderColor(unpack(border or C.line))
    return f
end

local function text(parent, size, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size, "")
    fs:SetTextColor(unpack(color or C.text))
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- width is a minimum: translated labels can be longer, so the button grows to fit
local function button(parent, label, width, onClick)
    local b = flat(CreateFrame("Button", nil, parent, "BackdropTemplate"), C.raised)
    b.label = text(b, 12)
    b.label:SetPoint("CENTER")
    b.label:SetText(label)
    b:SetSize(math.max(width, b.label:GetStringWidth() + 24), 24)
    b:SetScript("OnEnter", function(self) if self:IsEnabled() then self:SetBackdropBorderColor(unpack(C.pending)) end end)
    b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(C.line)) end)
    b:SetScript("OnClick", onClick)
    hooksecurefunc(b, "SetEnabled", function(self, on) self.label:SetTextColor(unpack(on and C.text or C.dim)) end)
    return b
end

local function input(parent, width)
    local e = flat(CreateFrame("EditBox", nil, parent, "BackdropTemplate"), { 0.03, 0.03, 0.04, 1 })
    e:SetSize(width, 24)
    e:SetFont(STANDARD_TEXT_FONT, 12, "")
    e:SetTextColor(unpack(C.text))
    e:SetTextInsets(8, 8, 0, 0)
    e:SetAutoFocus(false)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    e:SetScript("OnEnterPressed", e.ClearFocus)
    return e
end

-- a thin horizontal bar: background track plus a fill sized by SetValue(0..1)
local function bar(parent, height)
    local track = parent:CreateTexture(nil, "ARTWORK")
    track:SetColorTexture(1, 1, 1, 0.06)
    track:SetHeight(height)
    local fill = parent:CreateTexture(nil, "ARTWORK", nil, 1)
    fill:SetHeight(height)
    fill:SetPoint("LEFT", track, "LEFT")
    return {
        track = track, fill = fill,
        Set = function(self, value, color)
            self.fill:SetColorTexture(color[1], color[2], color[3], 1)
            self.fill:SetWidth(math.max(0.001, (self.track:GetWidth() or 0) * math.min(1, value)))
            self.fill:SetShown(value > 0)
        end,
        SetShown = function(self, on) self.track:SetShown(on) self.fill:SetShown(on) end,
    }
end

-- ---------------------------------------------------------------- helpers

-- index of the tree with most points: the build's spec tab
local function leadIndex(points)
    local best = 1
    for t = 2, #points do if points[t] > points[best] then best = t end end
    return best
end

local function lead(build, classData)
    return classData and classData.trees[leadIndex(build.points)]
end

local function categoryKey(build)
    return build.category or "none"
end

-- builds of the open class and spec tab, before the type/search/source filters
local function specBuilds()
    local out = {}
    for _, build in ipairs(ns.BuildsFor(state.class)) do
        if leadIndex(build.points) == state.spec then out[#out + 1] = build end
    end
    return out
end

local function visibleBuilds()
    local query = state.search:lower()
    local groups = {}
    for _, source in ipairs(SOURCES) do groups[#groups + 1] = { source = source, builds = {} } end
    for _, build in ipairs(specBuilds()) do
        local haystack = build.name .. " " .. (build.spec or "")
        for _, other in ipairs(build.also or {}) do haystack = haystack .. " " .. other.name .. " " .. other.source end
        if not state.hidden[build.source] and (state.category == "all" or categoryKey(build) == state.category)
            and not (state.hideBeta and build.beta) and (query == "" or haystack:lower():find(query, 1, true)) then
            for _, g in ipairs(groups) do if g.source == build.source then table.insert(g.builds, build) end end
        end
    end
    -- the builds more sites agree on first, otherwise in the order the sources give them
    for _, g in ipairs(groups) do
        local position = {}
        for k, b in ipairs(g.builds) do position[b] = k end
        table.sort(g.builds, function(a, b)
            local na, nb = #(a.also or {}), #(b.also or {})
            if na ~= nb then return na > nb end
            return position[a] < position[b]
        end)
    end
    return groups
end

-- ---------------------------------------------------------------- build list

local function listRow(index)
    if rows[index] then return rows[index] end
    local row = CreateFrame("Button", nil, frame.listContent, "BackdropTemplate")
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.accent = row:CreateTexture(nil, "ARTWORK")
    row.accent:SetPoint("TOPLEFT")
    row.accent:SetPoint("BOTTOMLEFT")
    row.accent:SetWidth(3)
    -- a star on the builds kept as loadouts
    row.star = row:CreateTexture(nil, "OVERLAY")
    row.star:SetTexture(STAR)
    row.star:SetSize(14, 14)
    row.star:SetPoint("TOPLEFT", 4, -2)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(28, 28)
    row.icon:SetPoint("LEFT", 9, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.pill = flat(CreateFrame("Frame", nil, row, "BackdropTemplate"))
    row.pill:SetHeight(14)
    row.pill:SetPoint("TOPRIGHT", -6, -5)
    row.pill.text = text(row.pill, 9, C.text, "CENTER")
    row.pill.text:SetPoint("CENTER")
    row.title = text(row, 12)
    row.title:SetPoint("TOPLEFT", 44, -6)
    row.sub = text(row, 10, C.dim)
    row.sub:SetPoint("BOTTOMLEFT", 44, 6)
    row.sub:SetPoint("RIGHT", -24, 0)
    row.tag = text(row, 11, C.onlyB, "RIGHT")
    row.tag:SetPoint("BOTTOMRIGHT", -8, 5)
    -- how the build splits its points between the three trees
    row.split = {}
    for t = 1, 3 do
        row.split[t] = row:CreateTexture(nil, "ARTWORK")
        row.split[t]:SetHeight(2)
    end
    row:SetScript("OnEnter", function(self)
        if self.build then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.build.name, 1, 1, 1, 1, true)
            for _, other in ipairs(self.build.also or {}) do
                GameTooltip:AddLine(ns.SourceName(other.source) .. ": " .. other.name, 0.5, 0.85, 0.5, true)
            end
            if self.build.beta then GameTooltip:AddLine(L.BETA_TIP, 0.6, 0.6, 0.65, true) end
            GameTooltip:AddLine(L.ROW_HINT, 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
        if not self.selectedRow then self:SetBackdropColor(0.13, 0.13, 0.16, 1) end
    end)
    row:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        if not self.selectedRow then self:SetBackdropColor(unpack(self.base)) end
    end)
    row:SetScript("OnClick", function(self, mouse)
        if self.group then
            state.collapsed[self.group] = not state.collapsed[self.group]
        elseif mouse == "RightButton" then
            state.compare = (state.compare ~= self.build and self.build ~= state.build) and self.build or nil
        else
            state.build = self.build
            if state.compare == self.build then state.compare = nil end
        end
        ns.Refresh()
    end)
    rows[index] = row
    return row
end

local function place(row, y, height)
    row:SetHeight(height)
    row:SetPoint("TOPLEFT", 0, -y)
    row:SetPoint("TOPRIGHT", 0, -y)
end

local function refreshList()
    local classData = ns.ClassData(state.class)
    local y, n = 0, 0
    for _, g in ipairs(visibleBuilds()) do
        if #g.builds > 0 then
            n = n + 1
            local row = flat(listRow(n), { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
            row.group, row.build, row.selectedRow, row.base = g.source, nil, false, { 0, 0, 0, 0 }
            place(row, y, GROUP_H)
            row.icon:Hide()
            row.star:Hide()
            row.accent:Hide()
            row.pill:Hide()
            for t = 1, 3 do row.split[t]:Hide() end
            row.sub:SetText("")
            row.tag:SetText("")
            row.title:SetPoint("TOPLEFT", 4, -6)
            row.title:SetPoint("RIGHT", -8, 0)
            row.title:SetText(paint((state.collapsed[g.source] and "+ " or "- ") .. ns.SourceName(g.source):upper(),
                C.source[g.source] or C.dim) .. paint("  " .. #g.builds, C.dim))
            row:Show()
            y = y + GROUP_H
            if not state.collapsed[g.source] then
                for _, build in ipairs(g.builds) do
                    n = n + 1
                    local selected = build == state.build
                    row = listRow(n)
                    row.base = selected and C.selected or C.panel
                    flat(row, row.base, selected and classColor(state.class) or C.line)
                    row.group, row.build, row.selectedRow = nil, build, selected
                    place(row, y, ROW_H - 4)
                    local tree = lead(build, classData)
                    row.icon:SetTexture("Interface\\Icons\\" .. (tree and tree.icon or "inv_misc_questionmark"))
                    row.icon:Show()
                    row.accent:SetColorTexture(unpack(classColor(state.class)))
                    row.accent:SetShown(selected)
                    row.star:SetShown(ns.IsLoadout(build))

                    local color = C.category[build.category]
                    row.pill:SetShown(color ~= nil)
                    if color then
                        row.pill.text:SetText(ns.CategoryName(build.category))
                        row.pill.text:SetTextColor(unpack(color))
                        row.pill:SetWidth(row.pill.text:GetStringWidth() + 10)
                        row.pill:SetBackdropColor(color[1], color[2], color[3], 0.15)
                        row.pill:SetBackdropBorderColor(color[1], color[2], color[3], 0.6)
                    end
                    row.title:SetPoint("TOPLEFT", 44, -6)
                    if color then row.title:SetPoint("RIGHT", row.pill, "LEFT", -6, 0) else row.title:SetPoint("RIGHT", -8, 0) end
                    row.title:SetText(ns.DisplayName(build))
                    row.sub:SetText(("%s  ·  %s%s%s%s"):format(build.spec or "", table.concat(build.points, "/"),
                        build.level and ("  ·  " .. L.LEVEL_SHORT:format(build.level)) or "",
                        build.beta and ("  ·  " .. L.BETA) or "",
                        build.also and paint("  ·  +" .. #build.also, C.done) or ""))
                    row.tag:SetText(build == state.compare and "B" or "")
                    local total, x = math.max(1, build.points[1] + build.points[2] + build.points[3]), 44
                    for t = 1, 3 do
                        local w = (LIST_W - 44 - 8) * build.points[t] / total
                        local seg = row.split[t]
                        seg:ClearAllPoints()
                        seg:SetPoint("BOTTOMLEFT", x, 2)
                        seg:SetWidth(math.max(0.001, w))
                        seg:SetColorTexture(C.tree[t][1], C.tree[t][2], C.tree[t][3], 0.85)
                        seg:SetShown(w > 0)
                        x = x + w
                    end
                    row:Show()
                    y = y + ROW_H
                end
            end
        end
    end
    for i = n + 1, #rows do rows[i]:Hide() end
    frame.listContent:SetHeight(math.max(1, y))
    frame.list:SetVerticalScroll(math.min(frame.list:GetVerticalScroll(), math.max(0, y - frame.list:GetHeight())))
    frame.empty:SetShown(n == 0)
end

-- ---------------------------------------------------------------- trees

local function card(t)
    if cards[t] then return cards[t] end
    local c = flat(CreateFrame("Frame", nil, frame.trees, "BackdropTemplate"))
    c:SetSize(CARD_W, CARD_H)
    c:SetPoint("TOPLEFT", (t - 1) * (CARD_W + 8), 0)
    -- class-coloured glow fading down from the header
    c.glow = c:CreateTexture(nil, "BACKGROUND", nil, 1)
    c.glow:SetPoint("TOPLEFT", 1, -1)
    c.glow:SetPoint("TOPRIGHT", -1, -1)
    c.glow:SetHeight(140)
    c.glow:SetColorTexture(1, 1, 1, 1)
    c.stripe = c:CreateTexture(nil, "ARTWORK", nil, 3)
    c.stripe:SetPoint("TOPLEFT", 1, -1)
    c.stripe:SetPoint("TOPRIGHT", -1, -1)
    c.stripe:SetHeight(3)
    c.watermark = c:CreateTexture(nil, "BACKGROUND", nil, 2)
    c.watermark:SetSize(CARD_W - 20, CARD_W - 20)
    c.watermark:SetPoint("CENTER", 0, -24)
    c.watermark:SetAlpha(0.07)
    c.watermark:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetSize(20, 20)
    c.icon:SetPoint("TOPLEFT", PAD, -8)
    c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c.title = text(c, 13)
    c.title:SetPoint("LEFT", c.icon, "RIGHT", 6, 0)
    c.title:SetPoint("RIGHT", c, "TOPRIGHT", -54, -18)
    c.points = text(c, 13, C.text, "RIGHT")
    c.points:SetPoint("TOPRIGHT", -PAD, -11)
    -- points bars: one for the build (or A), a second one for B when comparing
    c.barA, c.barB = bar(c, 3), bar(c, 3)
    c.barA.track:SetPoint("TOPLEFT", PAD, -33)
    c.barA.track:SetPoint("TOPRIGHT", -PAD, -33)
    c.barB.track:SetPoint("TOPLEFT", PAD, -38)
    c.barB.track:SetPoint("TOPRIGHT", -PAD, -38)
    cards[t] = c
    return c
end

local function cellPos(talent)
    return PAD + (talent.col - 1) * (CELL + GAP), -(CARD_HEAD + PAD / 2) - (talent.row - 1) * (CELL + GAP)
end

local function badge(parent, point, x, y)
    local b = flat(CreateFrame("Frame", nil, parent, "BackdropTemplate"), { 0, 0, 0, 0.9 })
    b:SetPoint(point, x, y)
    b:SetSize(18, 14)
    b.text = text(b, 10, C.text, "CENTER")
    b.text:SetPoint("CENTER", 0, 0)
    b.Set = function(self, label, color)
        self.text:SetText(label)
        self.text:SetTextColor(unpack(color))
        self:SetBackdropBorderColor(color[1], color[2], color[3], 0.7)
        self:SetWidth(math.max(16, self.text:GetStringWidth() + 8))
        self:Show()
    end
    return b
end

local function cell(t, i)
    cells[t] = cells[t] or {}
    if cells[t][i] then return cells[t][i] end
    local c = flat(CreateFrame("Button", nil, card(t), "BackdropTemplate"), { 0, 0, 0, 1 }, C.line, 2)
    c:SetSize(CELL, CELL)
    c:SetFrameLevel(card(t):GetFrameLevel() + 2)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetPoint("TOPLEFT", 2, -2)
    c.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c.tint = c:CreateTexture(nil, "ARTWORK", nil, 2)
    c.tint:SetAllPoints(c.icon)
    c.badge = badge(c, "BOTTOMRIGHT", 6, -6)  -- the build's rank, or B's when comparing
    c.badgeA = badge(c, "BOTTOMLEFT", -6, -6) -- A's rank when comparing
    c.next = c:CreateTexture(nil, "OVERLAY")
    c.next:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    c.next:SetBlendMode("ADD")
    c.next:SetPoint("TOPLEFT", -8, 8)
    c.next:SetPoint("BOTTOMRIGHT", 8, -8)
    c:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.spell then GameTooltip:SetSpellByID(self.spell) else GameTooltip:SetText(self.name, 1, 1, 1) end
        for _, info in ipairs(self.info) do GameTooltip:AddLine(info[1], unpack(info[2])) end
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", GameTooltip_Hide)
    cells[t][i] = c
    return c
end

-- How one talent cell looks: { border, tint, dim, badge = {label, color}, badgeA = {label, color}, info }
local function cellLook(a, b, max, mine)
    if b then -- comparing build A with B
        if a == 0 and b == 0 then return { dim = true, info = {} } end
        local info = { { L.TIP_AB:format(a, max, b, max), C.same } }
        if a == b then return { border = C.same, badge = { tostring(a), C.same }, info = info } end
        local color = (b == 0 and C.onlyA) or (a == 0 and C.onlyB) or C.differ
        return { border = color, tint = color, info = info,
            badgeA = { a > 0 and tostring(a) or "-", C.onlyA }, badge = { b > 0 and tostring(b) or "-", C.onlyB } }
    end
    -- the label is always the build's rank; the border tells how far you are with it
    local label = a .. "/" .. max
    if not mine then
        if a == 0 then return { dim = true, info = {} } end
        return { border = C.pending, badge = { label, C.pending }, info = { { L.TIP_BUILD:format(a, max), C.pending } } }
    end
    local info = { { L.TIP_BUILD_YOU:format(a, max, mine), C.pending } }
    if a == 0 and mine == 0 then return { dim = true, info = {} } end
    if mine > a then
        return { border = C.over, tint = C.over, badge = a > 0 and { label, C.over } or nil,
            info = { { L.TIP_OVER:format(mine, a), C.over } } }
    end
    local color = mine == a and C.done or C.pending
    return { border = color, badge = { label, color }, info = info }
end

-- arrows live on the tree card: above its background, below the talent buttons
local function line(c, index)
    c.lines = c.lines or {}
    if not c.lines[index] then
        c.lines[index] = c:CreateLine(nil, "ARTWORK")
        c.lines[index]:SetThickness(2)
    end
    return c.lines[index]
end

-- Ranks of the build as shown: the whole build, or its first state.preview points (the build at a level).
local function shownRanks(build, classData)
    local ranks, points = {}, {}
    for t, data in ipairs(classData.trees) do
        ranks[t], points[t] = {}, 0
        for i in ipairs(data.talents) do
            ranks[t][i] = state.preview and 0 or ns.TargetRank(build, t, i)
            points[t] = points[t] + ranks[t][i]
        end
    end
    if state.preview then
        local order = ns.Order(build, classData)
        for k = 1, math.min(state.preview, #order) do
            local t, i = order[k][1], order[k][2]
            ranks[t][i], points[t] = ranks[t][i] + 1, points[t] + 1
        end
    end
    return ranks, points
end

local function refreshTrees(classData, tree)
    for _, list in pairs(cells) do for _, c in pairs(list) do c:Hide() end end
    for _, c in pairs(cards) do
        c:Hide()
        for _, l in ipairs(c.lines or {}) do l:Hide() end
    end
    local build, other = state.build, state.compare
    if not (build and classData) then return end

    local color = classColor(state.class)
    local ranksA, pointsA = shownRanks(build, classData)
    local nt, ni
    if tree and not other and not state.preview then nt, ni = ns.NextStep(build, classData, tree) end
    for t, data in ipairs(classData.trees) do
        local c = card(t)
        local icon = "Interface\\Icons\\" .. (data.icon or "inv_misc_questionmark")
        c.icon:SetTexture(icon)
        c.watermark:SetTexture(icon)
        c.glow:SetGradient("VERTICAL", CreateColor(color[1], color[2], color[3], 0),
            CreateColor(color[1], color[2], color[3], 0.14))
        c.title:SetText(data.name)
        c.stripe:SetColorTexture(C.tree[t][1], C.tree[t][2], C.tree[t][3], 1)
        if other then
            c.points:SetText(paint(pointsA[t], C.onlyA) .. paint(" / ", C.dim) .. paint(other.points[t], C.onlyB))
            c.barA:Set(pointsA[t] / MAX_POINTS, C.onlyA)
            c.barB:SetShown(true)
            c.barB:Set(other.points[t] / MAX_POINTS, C.onlyB)
        else
            c.points:SetText(tostring(pointsA[t]))
            c.barA:Set(pointsA[t] / MAX_POINTS, C.tree[t])
            c.barB:SetShown(false)
        end
        c:Show()
        for i, tal in ipairs(data.talents) do
            local cl = cell(t, i)
            cl:SetPoint("TOPLEFT", cellPos(tal))
            cl.icon:SetTexture("Interface\\Icons\\" .. (tal.icon or "inv_misc_questionmark"))
            cl.name, cl.spell = tal.name, ns.TalentSpell(classData, tree, t, i)
            local look = cellLook(ranksA[t][i], other and ns.TargetRank(other, t, i), tal.max,
                tree and tree.rank[t][i])
            cl.info = look.info
            cl:SetBackdropBorderColor(unpack(look.border or C.line))
            cl.icon:SetDesaturated(look.dim == true)
            cl.icon:SetAlpha(look.dim and 0.25 or 1)
            if look.tint then cl.tint:SetColorTexture(look.tint[1], look.tint[2], look.tint[3], 0.22) end
            cl.tint:SetShown(look.tint ~= nil)
            if look.badge then cl.badge:Set(look.badge[1], look.badge[2]) else cl.badge:Hide() end
            if look.badgeA then cl.badgeA:Set(look.badgeA[1], look.badgeA[2]) else cl.badgeA:Hide() end
            cl.next:SetShown(t == nt and i == ni)
            cl:Show()
        end
    end

    -- prerequisite arrows come from the game, so only for your own class
    for k, e in ipairs(tree and tree.edges or {}) do
        local l = line(cards[e[1]], k)
        l:SetStartPoint("CENTER", cells[e[1]][e[2]])
        l:SetEndPoint("CENTER", cells[e[3]][e[4]])
        local used = ranksA[e[3]][e[4]] > 0 or (other and ns.TargetRank(other, e[3], e[4]) > 0)
        l:SetColorTexture(unpack(used and color or C.line))
        l:Show()
    end
end

-- One point of the order timeline: talent icon, the level it is learned at, a border in its tree's colour.
local function step(k)
    if steps[k] then return steps[k] end
    local b = flat(CreateFrame("Button", nil, frame.timeline, "BackdropTemplate"), { 0, 0, 0, 1 })
    b:SetSize(TL_ICON, TL_ICON)
    b:SetPoint("TOPLEFT", 8 + ((k - 1) % TL_PER_ROW) * TL_STEP, -18 - math.floor((k - 1) / TL_PER_ROW) * TL_ROW_H)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.level = text(b, 8, C.dim, "CENTER")
    b.level:SetPoint("TOP", b, "BOTTOM", 0, -1)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if self.spell then GameTooltip:SetSpellByID(self.spell) else GameTooltip:SetText(self.name, 1, 1, 1) end
        GameTooltip:AddLine(L.TIP_LEVEL:format(self.k + 9, self.k), 1, 0.82, 0)
        GameTooltip:Show()
        self:SetBackdropBorderColor(1, 1, 1, 1)
    end)
    b:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        self:SetBackdropBorderColor(unpack(self.border))
    end)
    b:SetScript("OnClick", function(self)
        state.preview = state.preview ~= self.k and self.k or nil
        ns.Refresh()
    end)
    steps[k] = b
    return b
end

local function refreshTimeline(build, classData, tree)
    local order = ns.Order(build, classData)
    for k, s in ipairs(order) do
        local b, t, i = step(k), s[1], s[2]
        local tal = classData.trees[t].talents[i]
        b.k, b.name, b.spell = k, tal.name, ns.TalentSpell(classData, tree, t, i)
        b.icon:SetTexture("Interface\\Icons\\" .. (tal.icon or "inv_misc_questionmark"))
        local ahead = state.preview and k > state.preview
        b.icon:SetDesaturated(ahead)
        b.icon:SetAlpha(ahead and 0.35 or 1)
        b.border = k == state.preview and { 1, 1, 1, 1 } or { C.tree[t][1], C.tree[t][2], C.tree[t][3], ahead and 0.35 or 1 }
        b:SetBackdropBorderColor(unpack(b.border))
        b.level:SetText(k + 9)
        b.level:SetTextColor(unpack(k == state.preview and C.text or C.dim))
        b:Show()
    end
    for k = #order + 1, #steps do steps[k]:Hide() end
    if state.preview then
        frame.timelineTitle:SetText(paint(L.PREVIEW:format(state.preview + 9, state.preview), C.pending))
    else
        frame.timelineTitle:SetText(paint(build.orderEstimated and L.ORDER_ESTIMATED or L.ORDER_TITLE, C.dim))
    end
end

-- Compare mode: one chip per talent that differs, "icon  name  3 > 1".
local DIFF_PER_ROW, DIFF_ROWS = 4, 2
local function diffChip(k)
    if diffChips[k] then return diffChips[k] end
    local w = (TREES_W - 16 - (DIFF_PER_ROW - 1) * 6) / DIFF_PER_ROW
    local c = flat(CreateFrame("Frame", nil, frame.timeline, "BackdropTemplate"), C.raised)
    c:SetSize(w, 24)
    c:SetPoint("TOPLEFT", 8 + ((k - 1) % DIFF_PER_ROW) * (w + 6), -20 - math.floor((k - 1) / DIFF_PER_ROW) * 30)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetSize(18, 18)
    c.icon:SetPoint("LEFT", 3, 0)
    c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c.ranks = text(c, 11, C.text, "RIGHT")
    c.ranks:SetPoint("RIGHT", -6, 0)
    c.name = text(c, 10, C.text)
    c.name:SetPoint("LEFT", c.icon, "RIGHT", 5, 0)
    c.name:SetPoint("RIGHT", c.ranks, "LEFT", -4, 0)
    diffChips[k] = c
    return c
end

local function refreshDifferences(build, other, classData, tree)
    local list = {}
    for t, data in ipairs(classData.trees) do
        for i, tal in ipairs(data.talents) do
            local a, b = ns.TargetRank(build, t, i), ns.TargetRank(other, t, i)
            if a ~= b then list[#list + 1] = { t = t, i = i, tal = tal, a = a, b = b } end
        end
    end
    local room = DIFF_PER_ROW * DIFF_ROWS
    for k = 1, math.min(#list, room) do
        local c, d = diffChip(k), list[k]
        if k == room and #list > room then
            c.icon:SetTexture("Interface\\Icons\\inv_misc_questionmark")
            c.name:SetText(L.MORE:format(#list - room + 1))
            c.ranks:SetText("")
        else
            local color = (d.b == 0 and C.onlyA) or (d.a == 0 and C.onlyB) or C.differ
            c.icon:SetTexture("Interface\\Icons\\" .. (d.tal.icon or "inv_misc_questionmark"))
            c.name:SetText(ns.TalentName(classData, tree, d.t, d.i))
            c.ranks:SetText(paint(d.a, C.onlyA) .. paint(" > ", C.dim) .. paint(d.b, C.onlyB))
            c:SetBackdropBorderColor(color[1], color[2], color[3], 0.8)
        end
        c:Show()
    end
    for k = math.min(#list, room) + 1, #diffChips do diffChips[k]:Hide() end
    frame.timelineTitle:SetText(paint(L.DIFF_TITLE, C.text) .. "     " .. compareSummary(classData, build, other))
end

-- "N talents differ · only in A: x points · only in B: y points"
function compareSummary(classData, a, b)
    local differ, onlyA, onlyB = 0, 0, 0
    for t, data in ipairs(classData.trees) do
        for i in ipairs(data.talents) do
            local ra, rb = ns.TargetRank(a, t, i), ns.TargetRank(b, t, i)
            if ra ~= rb then
                differ = differ + 1
                if ra > rb then onlyA = onlyA + ra - rb else onlyB = onlyB + rb - ra end
            end
        end
    end
    if differ == 0 then return paint(L.SAME_BUILD, C.done) end
    return L.DIFF_SUMMARY:format(differ, onlyA, onlyB)
end

-- ---------------------------------------------------------------- spec tabs / type chips

local function refreshSpecTabs(classData, current)
    local trees = classData and classData.trees or {}
    local w = (LIST_W - (#trees - 1) * 4) / math.max(1, #trees)
    local color = classColor(state.class)
    for t, data in ipairs(trees) do
        local tab = specTabs[t]
        tab:SetWidth(w)
        tab:SetPoint("TOPLEFT", (t - 1) * (w + 4), 0)
        tab.icon:SetTexture("Interface\\Icons\\" .. (data.icon or "inv_misc_questionmark"))
        tab.label:SetText(data.name .. (t == current and paint(" (" .. L.YOU .. ")", C.done) or ""))
        local active = t == state.spec
        tab:SetBackdropColor(unpack(active and C.selected or C.panel))
        tab:SetBackdropBorderColor(unpack(active and color or C.line))
        tab.underline:SetColorTexture(color[1], color[2], color[3], 1)
        tab.underline:SetShown(active)
        tab.label:SetTextColor(unpack(active and C.text or C.dim))
        tab.icon:SetDesaturated(not active)
        tab:Show()
    end
    for t = #trees + 1, #specTabs do specTabs[t]:Hide() end

    local counts = { all = 0 }
    for _, build in ipairs(specBuilds()) do
        counts.all = counts.all + 1
        counts[categoryKey(build)] = (counts[categoryKey(build)] or 0) + 1
    end
    for _, chip in ipairs(categoryChips) do
        local n, active = counts[chip.key] or 0, chip.key == state.category
        chip.label:SetText(ns.CategoryName(chip.key) .. " " .. n)
        chip:SetBackdropColor(unpack(active and C.selected or C.panel))
        chip:SetBackdropBorderColor(unpack(active and color or C.line))
        chip.label:SetTextColor(unpack((active and C.text) or (n > 0 and (C.category[chip.key] or C.same)) or C.dim))
    end
end

-- ---------------------------------------------------------------- Legacy view
-- The account's Legacy trees (Professions, Adventure, Resourcefulness): points available and spent against
-- the limit, and a plan by goal laid over the trees, with the order of its points. Plans are not applied:
-- Legacy points cannot be refunded, so they are spent by hand in the game's own Legacy window.

local LEGACY_COLS, LEGACY_ROWS = 3, 4
local LEGACY_CARD_H = CARD_HEAD + LEGACY_ROWS * (CELL + GAP) - GAP + PAD
local PLAN_ROW_H = 40
local lv -- the Legacy view
local legacyCards, legacyCells, planRows, legacySteps, challengeRows = {}, {}, {}, {}, {}
local CHALLENGE_ROW_H = 34
local TIER_COLORS = { { 0.4, 0.85, 0.5 }, { 0.6, 0.85, 0.35 }, { 1, 0.78, 0.2 }, { 1, 0.5, 0.25 }, { 1, 0.3, 0.3 } }
local READY = "Interface\\RaidFrame\\ReadyCheck-Ready"

local function legacyPlans()
    local data = ns.LegacyData()
    return data and data.plans or {}
end

local function selectedPlan()
    local name = ZbuildsCharDB and ZbuildsCharDB.legacyPlan
    if name == false then return nil end -- "no plan" chosen
    for _, plan in ipairs(legacyPlans()) do
        if plan.name == name then return plan end
    end
    return legacyPlans()[1]
end

local function selectPlan(plan)
    ZbuildsCharDB = ZbuildsCharDB or {}
    ZbuildsCharDB.legacyPlan = plan and plan.name or false
    ns.Refresh()
end

local function treeName(tree)
    return L["LEGACY_TREE_" .. tree.id] or tree.name
end

local function perkName(data, legacy, t, i)
    local spell = legacy and legacy.spell[t][i]
    return (spell and C_Spell.GetSpellName(spell)) or data.trees[t].perks[i].name
end

local function planRow(k)
    if planRows[k] then return planRows[k] end
    local row = CreateFrame("Button", nil, lv, "BackdropTemplate")
    row:SetHeight(PLAN_ROW_H - 4)
    row:SetPoint("TOPLEFT", PAD, -HEADER_H - PAD - 140 - (k - 1) * PLAN_ROW_H)
    row:SetWidth(LIST_W)
    row.accent = row:CreateTexture(nil, "ARTWORK")
    row.accent:SetPoint("TOPLEFT")
    row.accent:SetPoint("BOTTOMLEFT")
    row.accent:SetWidth(3)
    row.title = text(row, 12)
    row.title:SetPoint("TOPLEFT", 12, -6)
    row.title:SetPoint("RIGHT", -8, 0)
    row.sub = text(row, 10, C.dim)
    row.sub:SetPoint("BOTTOMLEFT", 12, 6)
    row.sub:SetPoint("RIGHT", -8, 0)
    row:SetScript("OnClick", function(self) selectPlan(self.plan) end)
    planRows[k] = row
    return row
end

local function legacyCard(t)
    if legacyCards[t] then return legacyCards[t] end
    local c = flat(CreateFrame("Frame", nil, lv.trees, "BackdropTemplate"))
    c:SetSize(CARD_W, LEGACY_CARD_H)
    c:SetPoint("TOPLEFT", (t - 1) * (CARD_W + 8), 0)
    c.stripe = c:CreateTexture(nil, "ARTWORK", nil, 3)
    c.stripe:SetPoint("TOPLEFT", 1, -1)
    c.stripe:SetPoint("TOPRIGHT", -1, -1)
    c.stripe:SetHeight(3)
    c.stripe:SetColorTexture(C.tree[t][1], C.tree[t][2], C.tree[t][3], 1)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetSize(20, 20)
    c.icon:SetPoint("TOPLEFT", PAD, -8)
    c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c.title = text(c, 13)
    c.title:SetPoint("LEFT", c.icon, "RIGHT", 6, 0)
    c.title:SetPoint("RIGHT", c, "TOPRIGHT", -54, -18)
    c.points = text(c, 13, C.text, "RIGHT")
    c.points:SetPoint("TOPRIGHT", -PAD, -11)
    c.bar = bar(c, 3)
    c.bar.track:SetPoint("TOPLEFT", PAD, -33)
    c.bar.track:SetPoint("TOPRIGHT", -PAD, -33)
    legacyCards[t] = c
    return c
end

local function legacyCell(t, i)
    legacyCells[t] = legacyCells[t] or {}
    if legacyCells[t][i] then return legacyCells[t][i] end
    local c = flat(CreateFrame("Button", nil, legacyCard(t), "BackdropTemplate"), { 0, 0, 0, 1 }, C.line, 2)
    c:SetSize(CELL, CELL)
    c:SetFrameLevel(legacyCard(t):GetFrameLevel() + 2)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetPoint("TOPLEFT", 2, -2)
    c.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c.badge = badge(c, "BOTTOMRIGHT", 6, -6)
    c.next = c:CreateTexture(nil, "OVERLAY")
    c.next:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    c.next:SetBlendMode("ADD")
    c.next:SetPoint("TOPLEFT", -8, 8)
    c.next:SetPoint("BOTTOMRIGHT", 8, -8)
    c:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.spell then GameTooltip:SetSpellByID(self.spell) else
            GameTooltip:SetText(self.name, 1, 1, 1)
            if self.desc then GameTooltip:AddLine(self.desc, 0.9, 0.9, 0.9, true) end
        end
        for _, info in ipairs(self.info) do GameTooltip:AddLine(info[1], unpack(info[2])) end
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", GameTooltip_Hide)
    legacyCells[t][i] = c
    return c
end

local function legacyStep(k)
    if legacySteps[k] then return legacySteps[k] end
    local b = flat(CreateFrame("Frame", nil, lv.order, "BackdropTemplate"), { 0, 0, 0, 1 })
    b:SetSize(TL_ICON, TL_ICON)
    b:SetPoint("TOPLEFT", 8 + (k - 1) * TL_STEP, -18)
    b:EnableMouse(true)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.number = text(b, 8, C.dim, "CENTER")
    b.number:SetPoint("TOP", b, "BOTTOM", 0, -1)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if self.spell then GameTooltip:SetSpellByID(self.spell) else GameTooltip:SetText(self.name, 1, 1, 1) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    legacySteps[k] = b
    return b
end

-- Shows the challenge in the game: Forever's own Legacy Challenges window first, then the achievement
-- window of other clients. Only "show" functions: the toggle ones would close a window already open.
-- Where none exists, the achievement's link goes to the chat instead.
local SHOW_CHALLENGE = { "ShowLegacyChallenge", "ShowAchievementFrameForAchievement", "OpenAchievementFrameToAchievement" }

local function openAchievement(id)
    for _, name in ipairs(SHOW_CHALLENGE) do
        if type(_G[name]) == "function" and pcall(_G[name], id) then return end
    end
    local link = GetAchievementLink and GetAchievementLink(id)
    if link then ns.Print(link) end
end

-- one row of the challenge tracker: icon, name and description, progress, difficulty dots
local function challengeRow(k)
    if challengeRows[k] then return challengeRows[k] end
    local row = CreateFrame("Button", nil, lv.challengeContent, "BackdropTemplate")
    row:SetHeight(CHALLENGE_ROW_H - 3)
    row:SetPoint("TOPLEFT", 0, -(k - 1) * CHALLENGE_ROW_H)
    row:SetPoint("TOPRIGHT", 0, -(k - 1) * CHALLENGE_ROW_H)
    flat(row, C.panel, C.line)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(24, 24)
    row.icon:SetPoint("LEFT", 5, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.check = row:CreateTexture(nil, "OVERLAY")
    row.check:SetTexture(READY)
    row.check:SetSize(16, 16)
    row.check:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 4, -4)
    row.dots = {}
    for d = 1, 5 do
        row.dots[d] = row:CreateTexture(nil, "ARTWORK")
        row.dots[d]:SetSize(5, 5)
        row.dots[d]:SetPoint("RIGHT", -8 - (5 - d) * 7, 0)
    end
    row.progress = text(row, 11, C.text, "RIGHT")
    row.progress:SetPoint("RIGHT", -48, 0)
    row.name = text(row, 12)
    row.name:SetPoint("TOPLEFT", 36, -3)
    row.name:SetPoint("RIGHT", row.progress, "LEFT", -8, 0)
    row.desc = text(row, 10, C.dim)
    row.desc:SetPoint("BOTTOMLEFT", 36, 4)
    row.desc:SetPoint("RIGHT", row.progress, "LEFT", -8, 0)
    row.bar = bar(row, 2)
    row.bar.track:SetPoint("BOTTOMLEFT", 36, 1)
    row.bar.track:SetPoint("BOTTOMRIGHT", -48, 1)
    row:SetScript("OnClick", function(self) if self.id then openAchievement(self.id) end end)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.name:GetText(), 1, 1, 1)
        GameTooltip:AddLine(self.desc:GetText(), 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(L.TIER .. ": " .. L["TIER_" .. self.tier], unpack(TIER_COLORS[self.tier]))
        GameTooltip:AddLine(L.CHALLENGE_TIP, 0.6, 0.6, 0.65)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    challengeRows[k] = row
    return row
end

local function refreshChallenges()
    local all, shown, done = ns.LegacyChallenges(), 0, 0
    for _, c in ipairs(all) do if c.completed then done = done + 1 end end
    lv.challengeTitle:SetText(L.CHALLENGES .. paint("   " .. L.CHALLENGES_DONE:format(done, #all), C.dim))
    for _, c in ipairs(all) do
        if not (c.completed and state.hideDone) then
            shown = shown + 1
            local row = challengeRow(shown)
            row.id, row.tier = c.id, c.tier
            row.icon:SetTexture(c.icon or "Interface\\Icons\\inv_misc_questionmark")
            row.icon:SetDesaturated(c.completed)
            row.check:SetShown(c.completed)
            row.name:SetText(c.name)
            row.name:SetTextColor(unpack(c.completed and C.dim or C.text))
            row.desc:SetText(c.description or "")
            row.progress:SetText(c.completed and "" or c.progressText)
            row.bar:SetShown(not c.completed and c.progress > 0)
            if not c.completed and c.progress > 0 then row.bar:Set(c.progress, C.done) end
            for d = 1, 5 do
                local color = d <= c.tier and TIER_COLORS[c.tier] or C.line
                row.dots[d]:SetColorTexture(color[1], color[2], color[3], 1)
            end
            row:Show()
        end
    end
    for k = shown + 1, #challengeRows do challengeRows[k]:Hide() end
    lv.challengeContent:SetHeight(math.max(1, shown * CHALLENGE_ROW_H))
    lv.hideDone.label:SetText(state.hideDone and L.SHOW_DONE or L.HIDE_DONE)
end

local function refreshLegacy()
    local data = ns.LegacyData()
    if not data then
        lv.points:SetText(paint(L.MISSING_DATA, C.over))
        return
    end
    local legacy, err = ns.ReadLegacy(data)
    local plan = selectedPlan()

    -- points against the limit
    if legacy then
        lv.points:SetText(L.LEGACY_POINTS:format(legacy.available, legacy.spent, data.points))
        lv.pointsBar:Set(legacy.spent / data.points, C.done)
    else
        lv.points:SetText(paint(err or "", C.pending))
        lv.pointsBar:Set(0, C.done)
    end

    -- plans by goal, then "no plan"
    local plans = legacyPlans()
    for k = 1, #plans + 1 do
        local row, p = planRow(k), plans[k]
        local selected = p == plan
        row.plan = p
        flat(row, selected and C.selected or C.panel, selected and C.pending or C.line)
        row.accent:SetColorTexture(unpack(C.pending))
        row.accent:SetShown(selected)
        row.title:SetText(p and (L["GOAL_" .. p.name] or p.name) or L.LEGACY_NO_PLAN)
        row.sub:SetText(p and (table.concat(p.points, "/") .. "  ·  " .. p.source) or "")
        row:Show()
    end
    for k = #plans + 2, #planRows do planRows[k]:Hide() end

    -- the trees, with the plan's ranks over the character's
    local nt, ni, nr
    if plan and legacy then nt, ni, nr = ns.NextLegacyStep(plan, legacy) end
    for t, tree in ipairs(data.trees) do
        local c = legacyCard(t)
        c.icon:SetTexture("Interface\\Icons\\" .. (tree.icon or "inv_misc_questionmark"))
        c.title:SetText(treeName(tree))
        local mineIn = 0
        for i in ipairs(tree.perks) do mineIn = mineIn + (legacy and legacy.rank[t][i] or 0) end
        c.points:SetText(plan and (paint(mineIn, C.done) .. paint(" / ", C.dim) .. plan.points[t]) or tostring(mineIn))
        c.bar:Set((plan and plan.points[t] or mineIn) / data.points, C.tree[t])
        c:Show()
        local gridX = (CARD_W - (LEGACY_COLS * (CELL + GAP) - GAP)) / 2
        for i, perk in ipairs(tree.perks) do
            local cl = legacyCell(t, i)
            cl:SetPoint("TOPLEFT", gridX + (perk.col - 1) * (CELL + GAP), -(CARD_HEAD + PAD / 2) - (perk.row - 1) * (CELL + GAP))
            cl.icon:SetTexture("Interface\\Icons\\" .. (perk.icon or "inv_misc_questionmark"))
            cl.name, cl.desc, cl.spell = perk.name, perk.desc, legacy and legacy.spell[t][i]
            local a, mine = plan and ns.PlanRank(plan, t, i) or 0, legacy and legacy.rank[t][i] or 0
            local color = (mine > a and C.over) or (a > 0 and (mine >= a and C.done or C.pending)) or (mine > 0 and C.done) or nil
            cl:SetBackdropBorderColor(unpack(color or C.line))
            cl.icon:SetDesaturated(a == 0 and mine == 0)
            cl.icon:SetAlpha((a == 0 and mine == 0) and 0.35 or 1)
            if a > 0 or mine > 0 then cl.badge:Set((plan and a or mine) .. "/" .. perk.max, color) else cl.badge:Hide() end
            cl.info = { { L.TIP_BUILD_YOU:format(a, perk.max, mine), C.pending } }
            if perk.gate > 0 then cl.info[#cl.info + 1] = { L.LEGACY_GATE:format(perk.gate), C.dim } end
            if perk.req then cl.info[#cl.info + 1] = { L.LEGACY_REQ:format(perkName(data, legacy, t, perk.req)), C.dim } end
            cl.next:SetShown(t == nt and i == ni)
            cl:Show()
        end
    end

    -- header of the plan, the order of its points and what comes next
    lv.planTitle:SetText(plan and (L["GOAL_" .. plan.name] or plan.name) or L.LEGACY_NO_PLAN)
    local used = 0
    for _, pts in ipairs(plan and plan.points or {}) do used = used + pts end
    lv.planSub:SetText(plan and (paint(plan.source, C.source["WoW Forever Builds"]) .. paint(("   ·   %s   ·   %d/%d"):format(
        table.concat(plan.points, "/"), used, data.points), C.dim)) or "")
    lv.planNote:SetText(plan and paint(L.LEGACY_PLAN_NOTE:format(plan.source), C.dim) or "")
    lv.order:SetShown(plan ~= nil)
    for _, b in ipairs(legacySteps) do b:Hide() end
    for k, step in ipairs(plan and plan.order or {}) do
        local b, t, i = legacyStep(k), step[1], step[2]
        local perk = data.trees[t].perks[i]
        b.icon:SetTexture("Interface\\Icons\\" .. (perk.icon or "inv_misc_questionmark"))
        b.name, b.spell = perk.name, legacy and legacy.spell[t][i]
        b:SetBackdropBorderColor(C.tree[t][1], C.tree[t][2], C.tree[t][3], 1)
        b.number:SetText(k)
        b:Show()
    end
    lv.status:SetText((nt and L.NEXT:format(paint(perkName(data, legacy, nt, ni), C.pending), nr))
        or (plan and legacy and paint(L.COMPLETE, C.done)) or "")
    refreshChallenges()
end

-- refreshed by achievement events, only while the Legacy view is open
function ns.RefreshLegacy()
    if frame and frame:IsShown() and state.mode == "legacy" then ns.Refresh() end
end

local function createLegacyView()
    lv = CreateFrame("Frame", nil, frame)
    lv:SetAllPoints()
    lv:Hide()
    frame.legacyView = lv
    local top, right = -HEADER_H - PAD, PAD + LIST_W + 16

    local title = text(lv, 17)
    title:SetPoint("TOPLEFT", PAD, top)
    title:SetText(L.TAB_LEGACY)
    lv.points = text(lv, 12)
    lv.points:SetPoint("TOPLEFT", PAD, top - 26)
    lv.points:SetWidth(LIST_W)
    lv.points:SetWordWrap(true)
    lv.pointsBar = bar(lv, 4)
    lv.pointsBar.track:SetPoint("TOPLEFT", PAD, top - 64)
    lv.pointsBar.track:SetWidth(LIST_W)
    local note = text(lv, 11, C.pending)
    note:SetPoint("TOPLEFT", PAD, top - 76)
    note:SetWidth(LIST_W)
    note:SetWordWrap(true)
    note:SetText(L.LEGACY_NO_REFUND)
    local plansTitle = text(lv, 13)
    plansTitle:SetPoint("TOPLEFT", PAD, top - 116)
    plansTitle:SetText(L.LEGACY_PLANS)

    local divider = lv:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(unpack(C.line))
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT", PAD + LIST_W + 8, -HEADER_H)
    divider:SetPoint("BOTTOMLEFT", PAD + LIST_W + 8, 0)

    lv.planTitle = text(lv, 17)
    lv.planTitle:SetPoint("TOPLEFT", right, top)
    lv.planTitle:SetWidth(TREES_W)
    lv.planSub = text(lv, 11, C.dim)
    lv.planSub:SetPoint("TOPLEFT", right, top - 23)
    lv.planSub:SetWidth(TREES_W)
    lv.planNote = text(lv, 11, C.dim)
    lv.planNote:SetPoint("TOPLEFT", right, top - 42)
    lv.planNote:SetWidth(TREES_W)
    lv.planNote:SetWordWrap(true)

    lv.trees = CreateFrame("Frame", nil, lv)
    lv.trees:SetPoint("TOPLEFT", right, top - 82)
    lv.trees:SetSize(TREES_W, LEGACY_CARD_H)

    lv.order = flat(CreateFrame("Frame", nil, lv, "BackdropTemplate"))
    lv.order:SetPoint("TOPLEFT", lv.trees, "BOTTOMLEFT", 0, -8)
    lv.order:SetSize(TREES_W, 18 + TL_ROW_H)
    local orderTitle = text(lv.order, 10, C.dim)
    orderTitle:SetPoint("TOPLEFT", 8, -4)
    orderTitle:SetText(L.LEGACY_ORDER)

    lv.status = text(lv, 12)
    lv.status:SetPoint("TOPLEFT", lv.order, "BOTTOMLEFT", 0, -10)
    lv.status:SetWidth(TREES_W)
    lv.status:SetWordWrap(true)

    -- the challenges: read from the game's achievements every time, nothing saved
    local header = CreateFrame("Frame", nil, lv)
    header:SetPoint("TOPLEFT", lv.status, "BOTTOMLEFT", 0, -14)
    header:SetSize(TREES_W, 22)
    lv.challengeTitle = text(header, 13)
    lv.challengeTitle:SetPoint("LEFT")
    lv.hideDone = button(header, L.HIDE_DONE, 130, function()
        state.hideDone = not state.hideDone
        ns.Refresh()
    end)
    lv.hideDone:SetHeight(20)
    lv.hideDone:SetPoint("RIGHT")
    lv.challengeList = CreateFrame("ScrollFrame", nil, lv)
    lv.challengeList:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
    lv.challengeList:SetPoint("BOTTOMRIGHT", lv, "BOTTOMLEFT", right + TREES_W, PAD)
    lv.challengeList:EnableMouseWheel(true)
    lv.challengeList:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, lv.challengeContent:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, self:GetVerticalScroll() - delta * CHALLENGE_ROW_H * 2)))
    end)
    lv.challengeContent = CreateFrame("Frame", nil, lv.challengeList)
    lv.challengeContent:SetWidth(TREES_W)
    lv.challengeList:SetScrollChild(lv.challengeContent)
end

-- ---------------------------------------------------------------- refresh

function ns.Refresh()
    if not (frame and frame:IsShown()) then return end
    -- header tabs: the talents view or the Legacy view
    local legacyMode = state.mode == "legacy"
    frame.talentsView:SetShown(not legacyMode)
    frame.legacyView:SetShown(legacyMode)
    for _, tab in ipairs(frame.modeTabs) do
        local active = tab.mode == (state.mode or "talents")
        tab:SetBackdropColor(unpack(active and C.selected or C.raised))
        tab:SetBackdropBorderColor(unpack(active and C.pending or C.line))
        tab.label:SetTextColor(unpack(active and C.text or C.dim))
    end
    if legacyMode then
        local color = classColor(ns.PlayerClass())
        frame.accent:SetColorTexture(color[1], color[2], color[3], 1)
        return refreshLegacy()
    end
    local mine = state.class == ns.PlayerClass()
    local classData = ns.ClassData(state.class)
    local tree, err
    if mine and classData then tree, err = ns.ReadTree(classData) end

    -- your spec is the tree you have most points in; other classes open on their first tree
    local currentSpec
    if tree then
        local spent = {}
        for t in ipairs(classData.trees) do
            spent[t] = 0
            for _, r in ipairs(tree.rank[t]) do spent[t] = spent[t] + r end
        end
        currentSpec = leadIndex(spent)
    end
    state.spec = state.spec or currentSpec or 1
    refreshSpecTabs(classData, currentSpec)

    local builds = {}
    for _, g in ipairs(visibleBuilds()) do for _, b in ipairs(g.builds) do builds[#builds + 1] = b end end
    local known = {}
    for _, b in ipairs(builds) do known[b] = true end
    if not known[state.build] then
        local saved = mine and ns.SelectedBuild(state.class)
        state.build = (saved and known[saved] and saved) or builds[1]
    end
    if state.compare and not known[state.compare] and state.compare.source ~= "Personaje" then state.compare = nil end
    if state.compare and state.compare.source == "Personaje" then
        state.compare = tree and ns.CurrentAsBuild(classData, tree) or nil -- keep "my talents" current
    end

    if state.previewOf ~= state.build or state.compare then state.preview = nil end -- a preview belongs to one build
    state.previewOf = state.build

    local color = classColor(state.class)
    frame.accent:SetColorTexture(color[1], color[2], color[3], 1)
    frame.classLabel:SetText(paint(LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[state.class] or state.class, color))
    refreshList()
    refreshTrees(classData, tree)

    local build = state.build
    frame.timeline:SetShown(build ~= nil and classData ~= nil)
    for _, c in ipairs(diffChips) do c:Hide() end
    for _, b in ipairs(steps) do b:Hide() end
    if build and classData then
        if state.compare then refreshDifferences(build, state.compare, classData, tree)
        else refreshTimeline(build, classData, tree) end
    end
    frame.buildTitle:SetText(build and ns.DisplayName(build) or L.NO_BUILDS)
    local sub = ""
    if build then
        sub = paint(ns.SourceName(build.source), C.source[build.source] or C.dim)
        if C.category[build.category] then sub = sub .. "   " .. paint(ns.CategoryName(build.category), C.category[build.category]) end
        sub = sub .. paint(("   ·   %s   ·   %s%s%s"):format(build.spec or "", table.concat(build.points, "/"),
            build.level and ("   ·   " .. L.LEVEL:format(build.level)) or "", build.beta and ("   ·   " .. L.BETA) or ""), C.dim)
        if build.also then
            local names = {}
            for _, other in ipairs(build.also) do names[#names + 1] = ns.SourceName(other.source) end
            sub = sub .. "   ·   " .. paint(L.RECOMMENDED_BY:format(table.concat(names, ", ")), C.done)
        end
    end
    frame.buildSub:SetText(sub)

    if state.compare then
        frame.legend:SetText(paint("A  ", C.onlyA) .. (build and build.name or "") .. paint("     B  ", C.onlyB)
            .. state.compare.name)
        frame.summary:SetText(swatch(C.onlyA, L.LEG_ONLY_A) .. "   " .. swatch(C.onlyB, L.LEG_ONLY_B) .. "   "
            .. swatch(C.differ, L.LEG_DIFF) .. "   " .. swatch(C.same, L.LEG_SAME))
    elseif mine and tree then
        frame.legend:SetText(swatch(C.done, L.LEG_LEARNED) .. "   " .. swatch(C.pending, L.LEG_PENDING) .. "   "
            .. swatch(C.over, L.LEG_OVER))
        frame.summary:SetText(paint(L.RIGHT_CLICK, C.dim))
    else
        frame.legend:SetText("")
        frame.summary:SetText(paint(L.RIGHT_CLICK, C.dim))
    end

    local status = ""
    if build and mine and not tree then
        status = paint(err or "", C.over)
    elseif build and tree then
        local nt, ni, nr = ns.NextStep(build, classData, tree)
        status = (nt and L.NEXT:format(paint(ns.TalentName(classData, tree, nt, ni), C.pending), nr) or paint(L.COMPLETE, C.done))
            .. paint("     " .. L.FREE:format(ns.FreePoints(tree)), C.dim)
        if #tree.mismatches > 0 then
            status = status .. "\n" .. paint(L.OUTDATED:format(table.concat(tree.mismatches, ", ")), C.onlyB)
        end
    elseif build then
        status = paint(L.OTHER_CLASS, C.dim)
    end
    frame.status:SetText(status)

    frame.link:SetText(build and (build.guide or build.url) or "")
    frame.link:SetCursorPosition(0)
    frame.apply:SetEnabled(tree ~= nil and build ~= nil)
    frame.compareMine:SetEnabled(tree ~= nil and build ~= nil)
    frame.loadout:SetShown(mine and build ~= nil)
    frame.rename:SetShown(mine and build ~= nil and ns.IsLoadout(build))
    frame.loadout.label:SetText(build and ns.IsLoadout(build) and L.LOADOUT_REMOVE or L.LOADOUT_ADD)
    frame.clearCompare:SetEnabled(state.compare ~= nil)
    frame.remove:SetShown(build ~= nil and build.imported == true)
end

-- ---------------------------------------------------------------- window

local function cycleClass(step)
    for idx, token in ipairs(CLASS_ORDER) do
        if token == state.class then
            state.class = CLASS_ORDER[(idx - 1 + step) % #CLASS_ORDER + 1]
            state.build, state.compare, state.spec = nil, nil, nil
            break
        end
    end
    ns.Refresh()
end

local function version()
    local get = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local v = get and get("Zbuilds", "Version")
    return (v and not v:find("^@")) and v or ""
end

local function create()
    frame = flat(CreateFrame("Frame", "ZbuildsFrame", UIParent, "BackdropTemplate"), C.bg)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetScript("OnShow", function()
        -- always open on your class and the spec you currently play
        state.class, state.spec = ns.PlayerClass(), nil
        ns.Refresh()
    end)
    tinsert(UISpecialFrames, "ZbuildsFrame")

    -- header bar: drag to move; a line in the class colour under it
    local header = flat(CreateFrame("Frame", nil, frame, "BackdropTemplate"), C.panel)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER_H)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() frame:StartMoving() end)
    header:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    frame.accent = header:CreateTexture(nil, "ARTWORK")
    frame.accent:SetHeight(2)
    frame.accent:SetPoint("BOTTOMLEFT", 1, 0)
    frame.accent:SetPoint("BOTTOMRIGHT", -1, 0)
    local logo = header:CreateTexture(nil, "ARTWORK")
    logo:SetSize(24, 24)
    logo:SetPoint("LEFT", PAD - 2, 0)
    logo:SetTexture(LOGO)
    local title = text(header, 15)
    title:SetPoint("LEFT", logo, "RIGHT", 7, 0)
    title:SetText(paint("Z", C.pending) .. "builds" .. paint("  " .. version(), C.dim))
    local close = button(header, "x", 24, function() frame:Hide() end)
    close:SetPoint("RIGHT", -5, 0)

    -- the window's two views
    frame.modeTabs = {}
    for k, mode in ipairs({ "talents", "legacy" }) do
        local tab = button(header, mode == "talents" and L.TAB_TALENTS or L.TAB_LEGACY, 110, function()
            state.mode = mode
            ns.Refresh()
        end)
        tab:SetHeight(24)
        tab:SetPoint("LEFT", title, "RIGHT", 24 + (k - 1) * 116, 0)
        tab.mode = mode
        frame.modeTabs[k] = tab
    end

    -- below the header: the talents view, swapped with the Legacy view by the header tabs
    local view = CreateFrame("Frame", nil, frame)
    view:SetAllPoints()
    frame.talentsView = view

    -- left column: class switcher, spec tabs, search, type and source filters, list
    local top = -HEADER_H - PAD
    local prev = button(view, "<", 26, function() cycleClass(-1) end)
    prev:SetPoint("TOPLEFT", PAD, top)
    local nextBtn = button(view, ">", 26, function() cycleClass(1) end)
    nextBtn:SetPoint("TOPLEFT", PAD + LIST_W - 26, top)
    frame.classLabel = text(view, 15, C.text, "CENTER")
    frame.classLabel:SetPoint("TOP", frame, "TOPLEFT", PAD + LIST_W / 2, top - 5)

    local tabs = CreateFrame("Frame", nil, view)
    tabs:SetPoint("TOPLEFT", PAD, top - 32)
    tabs:SetSize(LIST_W, 28)
    for t = 1, 3 do
        local tab = button(tabs, "", 90, function()
            state.spec, state.build, state.compare = t, nil, nil
            ns.Refresh()
        end)
        tab:SetHeight(28)
        tab:SetScript("OnEnter", nil)
        tab:SetScript("OnLeave", nil)
        tab.icon = tab:CreateTexture(nil, "ARTWORK")
        tab.icon:SetSize(18, 18)
        tab.icon:SetPoint("LEFT", 6, 0)
        tab.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        tab.underline = tab:CreateTexture(nil, "OVERLAY")
        tab.underline:SetHeight(2)
        tab.underline:SetPoint("BOTTOMLEFT", 1, 1)
        tab.underline:SetPoint("BOTTOMRIGHT", -1, 1)
        tab.label:ClearAllPoints()
        tab.label:SetPoint("LEFT", tab.icon, "RIGHT", 4, 0)
        tab.label:SetPoint("RIGHT", -4, 0)
        tab.label:SetJustifyH("LEFT")
        tab.label:SetFont(STANDARD_TEXT_FONT, 11, "")
        specTabs[t] = tab
    end

    local search = input(view, LIST_W)
    search:SetPoint("TOPLEFT", PAD, top - 66)
    local hint = text(search, 12, C.dim)
    hint:SetPoint("LEFT", 8, 0)
    hint:SetText(L.SEARCH)
    search:SetScript("OnTextChanged", function(self)
        state.search = self:GetText()
        hint:SetShown(state.search == "")
        ns.Refresh()
    end)

    local typeW = (LIST_W - (#CATEGORIES - 1) * 4) / #CATEGORIES
    for k, key in ipairs(CATEGORIES) do
        local chip = button(view, ns.CategoryName(key), typeW, function()
            state.category, state.build = key, nil
            ns.Refresh()
        end)
        chip:SetSize(typeW, 20)
        chip:SetScript("OnEnter", nil)
        chip:SetScript("OnLeave", nil)
        chip.label:SetFont(STANDARD_TEXT_FONT, 10, "")
        chip.key = key
        chip:SetPoint("TOPLEFT", PAD + (k - 1) * (typeW + 4), top - 96)
        categoryChips[k] = chip
    end

    local chipW = (LIST_W - (CHIPS_PER_ROW - 1) * 6) / CHIPS_PER_ROW
    for k, source in ipairs(SOURCES) do
        local chip
        chip = button(view, SOURCE_SHORT[source] or ns.SourceName(source), chipW, function()
            state.hidden[source] = not state.hidden[source]
            chip:SetBackdropColor(unpack(state.hidden[source] and C.bg or C.raised))
            chip.label:SetTextColor(unpack(state.hidden[source] and C.dim or C.source[source]))
            ns.Refresh()
        end)
        chip:SetSize(chipW, 20)
        chip.label:SetFont(STANDARD_TEXT_FONT, 10, "")
        chip.label:SetTextColor(unpack(C.source[source]))
        local col, row = (k - 1) % CHIPS_PER_ROW, math.floor((k - 1) / CHIPS_PER_ROW)
        chip:SetPoint("TOPLEFT", PAD + col * (chipW + 6), top - 122 - row * 24)
    end
    local beta
    beta = button(view, L.BETA, chipW, function()
        state.hideBeta = not state.hideBeta
        beta:SetBackdropColor(unpack(state.hideBeta and C.bg or C.raised))
        beta.label:SetTextColor(unpack(state.hideBeta and C.dim or C.same))
        ns.Refresh()
    end)
    beta:SetSize(chipW, 20)
    beta.label:SetFont(STANDARD_TEXT_FONT, 10, "")
    beta.label:SetTextColor(unpack(C.same))
    beta:SetPoint("TOPLEFT", PAD + (#SOURCES % CHIPS_PER_ROW) * (chipW + 6),
        top - 122 - math.floor(#SOURCES / CHIPS_PER_ROW) * 24)

    local listTop = top - 174
    frame.list = CreateFrame("ScrollFrame", nil, view)
    frame.list:SetPoint("TOPLEFT", PAD, listTop)
    frame.list:SetSize(LIST_W, HEIGHT + listTop - PAD - 34)
    frame.list:EnableMouseWheel(true)
    frame.list:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, frame.listContent:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, self:GetVerticalScroll() - delta * ROW_H * 2)))
    end)
    frame.listContent = CreateFrame("Frame", nil, frame.list)
    frame.listContent:SetWidth(LIST_W)
    frame.list:SetScrollChild(frame.listContent)
    frame.empty = text(view, 12, C.dim, "CENTER")
    frame.empty:SetPoint("TOP", frame.list, "TOP", 0, -20)
    frame.empty:SetText(L.NO_MATCH)

    local importBtn = button(view, L.IMPORT_BTN, LIST_W, function() ns.ShowImport() end)
    importBtn:SetSize(LIST_W, 26)
    importBtn:SetPoint("BOTTOMLEFT", PAD, PAD)

    local divider = view:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(unpack(C.line))
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT", PAD + LIST_W + 8, -HEADER_H)
    divider:SetPoint("BOTTOMLEFT", PAD + LIST_W + 8, 0)

    -- right column: build header, legend and compare summary, trees, actions
    local right = PAD + LIST_W + 16
    frame.buildTitle = text(view, 17)
    frame.buildTitle:SetPoint("TOPLEFT", right, top)
    frame.buildTitle:SetWidth(TREES_W)
    frame.buildSub = text(view, 11, C.dim)
    frame.buildSub:SetPoint("TOPLEFT", right, top - 23)
    frame.buildSub:SetWidth(TREES_W)
    frame.legend = text(view, 11, C.text)
    frame.legend:SetPoint("TOPLEFT", right, top - 44)
    frame.legend:SetWidth(TREES_W)
    frame.summary = text(view, 11, C.text)
    frame.summary:SetPoint("TOPLEFT", right, top - 61)
    frame.summary:SetWidth(TREES_W)

    frame.trees = CreateFrame("Frame", nil, view)
    frame.trees:SetPoint("TOPLEFT", right, top - 82)
    frame.trees:SetSize(TREES_W, CARD_H)

    -- under the trees: the point order timeline, or the list of differences when comparing
    frame.timeline = flat(CreateFrame("Frame", nil, view, "BackdropTemplate"))
    frame.timeline:SetPoint("TOPLEFT", frame.trees, "BOTTOMLEFT", 0, -8)
    frame.timeline:SetSize(TREES_W, TL_H)
    frame.timelineTitle = text(frame.timeline, 10, C.dim)
    frame.timelineTitle:SetPoint("TOPLEFT", 8, -4)
    frame.timelineTitle:SetWidth(TREES_W - 16)

    frame.status = text(view, 12)
    frame.status:SetPoint("TOPLEFT", frame.timeline, "BOTTOMLEFT", 0, -8)
    frame.status:SetWidth(TREES_W)
    frame.status:SetWordWrap(true)
    frame.status:SetSpacing(3)

    frame.apply = button(view, L.APPLY, 160, function()
        ns.LearnAndReport(state.build, ns.ClassData(state.class))
        ns.Refresh()
    end)
    frame.apply:SetPoint("BOTTOMLEFT", right, PAD + 18)
    frame.apply:SetBackdropColor(0.12, 0.32, 0.17, 1)

    frame.compareMine = button(view, L.COMPARE_MINE, 150, function()
        local classData = ns.ClassData(state.class)
        local tree = ns.ReadTree(classData)
        state.compare = tree and ns.CurrentAsBuild(classData, tree)
        ns.Refresh()
    end)
    frame.compareMine:SetPoint("LEFT", frame.apply, "RIGHT", 8, 0)
    frame.clearCompare = button(view, L.CLEAR_COMPARE, 120, function()
        state.compare = nil
        ns.Refresh()
    end)
    frame.clearCompare:SetPoint("LEFT", frame.compareMine, "RIGHT", 8, 0)
    frame.remove = button(view, L.DELETE, 80, function()
        if state.build and state.build.imported then
            ns.RemoveImport(state.build)
            state.build = nil
            ns.Refresh()
        end
    end)
    frame.remove:SetPoint("LEFT", frame.clearCompare, "RIGHT", 8, 0)
    frame.remove:SetBackdropColor(0.32, 0.12, 0.12, 1)

    -- link to the source, selectable for Ctrl+C
    -- keep the build as a loadout, to rotate between loadouts on the game's talent window
    frame.loadout = button(view, L.LOADOUT_ADD, 150, function()
        local build = state.build
        if not build then return end
        ns.Print((ns.ToggleLoadout(build) and L.LOADOUT_ADDED or L.LOADOUT_REMOVED):format(build.name))
        ns.Refresh()
    end)
    frame.loadout:SetWidth(math.max(frame.loadout:GetWidth(), 150))
    frame.loadout:SetPoint("BOTTOMRIGHT", -PAD, PAD + 50)
    frame.rename = button(view, L.LOADOUT_RENAME, 90, function() ns.PromptRename(state.build) end)
    frame.rename:SetPoint("RIGHT", frame.loadout, "LEFT", -6, 0)
    frame.link = input(view, TREES_W - frame.loadout:GetWidth() - frame.rename:GetWidth() - 14)
    frame.link:SetPoint("BOTTOMLEFT", right, PAD + 50)
    frame.link:SetTextColor(unpack(C.dim))
    frame.link:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    frame.link:SetScript("OnTextChanged", function(self, user)
        if user then
            self:SetText(state.build and (state.build.guide or state.build.url) or "")
            self:HighlightText()
        end
    end)

    local credits = text(view, 10, C.dim)
    credits:SetPoint("BOTTOMLEFT", right, 8)
    credits:SetWidth(TREES_W)
    credits:SetText(L.CREDITS:format(ZbuildsData and ZbuildsData.generated or "?"))

    createLegacyView()
end

-- ---------------------------------------------------------------- import dialog

local dialog

local function createImport()
    dialog = flat(CreateFrame("Frame", "ZbuildsImport", frame, "BackdropTemplate"), C.bg, C.pending)
    dialog:SetSize(480, 220)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("DIALOG")
    dialog:EnableMouse(true)
    tinsert(UISpecialFrames, "ZbuildsImport")

    local inner = 480 - 2 * PAD
    local title = text(dialog, 14)
    title:SetPoint("TOPLEFT", PAD, -PAD)
    title:SetText(L.IMPORT_TITLE)
    local help = text(dialog, 10, C.dim)
    help:SetPoint("TOPLEFT", PAD, -34)
    help:SetWidth(inner)
    help:SetText(L.IMPORT_HELP)

    dialog.url = input(dialog, inner)
    dialog.url:SetPoint("TOPLEFT", PAD, -54)
    dialog.name = input(dialog, inner)
    dialog.name:SetPoint("TOPLEFT", PAD, -86)
    local urlHint, nameHint = text(dialog.url, 12, C.dim), text(dialog.name, 12, C.dim)
    urlHint:SetPoint("LEFT", 8, 0)
    urlHint:SetText(L.PASTE)
    nameHint:SetPoint("LEFT", 8, 0)
    nameHint:SetText(L.NAME_OPT)
    dialog.url:SetScript("OnTextChanged", function(self) urlHint:SetShown(self:GetText() == "") end)
    dialog.name:SetScript("OnTextChanged", function(self) nameHint:SetShown(self:GetText() == "") end)

    -- type: any of the CATEGORIES except "all"
    dialog.types = {}
    local typeW = (inner - 3 * 4) / 4
    for k, key in ipairs({ "none", "Leveo", "PvE", "PvP" }) do
        local chip = button(dialog, ns.CategoryName(key), typeW, function()
            dialog.category = key
            for _, other in ipairs(dialog.types) do
                local active = other.key == dialog.category
                other:SetBackdropBorderColor(unpack(active and C.pending or C.line))
                other.label:SetTextColor(unpack(active and C.text or C.dim))
            end
        end)
        chip:SetSize(typeW, 24)
        chip.key = key
        chip:SetScript("OnEnter", nil)
        chip:SetScript("OnLeave", nil)
        chip:SetPoint("TOPLEFT", PAD + (k - 1) * (typeW + 4), -118)
        dialog.types[k] = chip
    end

    dialog.error = text(dialog, 11, C.over)
    dialog.error:SetPoint("TOPLEFT", PAD, -150)
    dialog.error:SetWidth(inner)
    dialog.error:SetWordWrap(true)

    local ok = button(dialog, L.IMPORT, 110, function()
        local category = dialog.category ~= "none" and dialog.category or nil
        local build, err = ns.DecodeLink(dialog.url:GetText(), strtrim(dialog.name:GetText()), category)
        if not build then
            dialog.error:SetText(err)
            return
        end
        ns.AddImport(build)
        dialog:Hide()
        state.class, state.spec, state.category, state.build = build.class, nil, "all", build
        state.hidden["Mis enlaces"] = nil
        for t, tree in ipairs(ns.ClassData(build.class).trees) do
            if tree.name == build.spec then state.spec = t end
        end
        ns.Print(L.IMPORTED:format(build.name, table.concat(build.points, "/")))
        ns.Refresh()
    end)
    ok:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    ok:SetBackdropColor(0.12, 0.32, 0.17, 1)
    local cancel = button(dialog, L.CANCEL, 100, function() dialog:Hide() end)
    cancel:SetPoint("RIGHT", ok, "LEFT", -8, 0)
    dialog.url:SetScript("OnEnterPressed", function() ok:Click() end)
end

function ns.ShowImport()
    if not dialog then createImport() end
    dialog.url:SetText("")
    dialog.name:SetText("")
    dialog.error:SetText("")
    dialog.types[1]:Click()
    dialog:Show()
    dialog.url:SetFocus()
end

function ns.Toggle()
    if not ZbuildsData then
        ns.Print(L.MISSING_DATA)
        return
    end
    if not frame then
        create()
        state.class = ns.PlayerClass()
        frame:Hide()
    end
    frame:SetShown(not frame:IsShown())
end
