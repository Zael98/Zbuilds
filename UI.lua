-- Window: flat dark style. Left: grouped, searchable build list. Right: the selected build over the
-- three trees, either against your current talents or against a second build (compare mode).
local _, ns = ...

local WHITE = "Interface\\Buttons\\WHITE8x8"
local PAD, HEADER_H = 12, 32
local LIST_W, ROW_H, GROUP_H = 290, 40, 24
local CELL, GAP = 36, 10
local CARD_W = 4 * (CELL + GAP) - GAP + 2 * PAD
local CARD_H = 34 + 7 * (CELL + GAP) - GAP + PAD
local TREES_W = 3 * CARD_W + 2 * 8
local WIDTH = PAD + LIST_W + 16 + TREES_W + PAD
local HEIGHT = 640

local CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local SOURCES = { "Talents Forever", "Icy Veins", "Guías extra", "Mis enlaces" }
local CATEGORIES = { { key = "all", label = "Todas" }, { key = "Leveo", label = "Leveo" }, { key = "PvE", label = "PvE" },
    { key = "PvP", label = "PvP" }, { key = "none", label = "Sin tipo" } }

local C = {
    bg = { 0.05, 0.05, 0.06, 0.94 },
    panel = { 0.09, 0.09, 0.11, 1 },
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
    source = { ["Talents Forever"] = { 0.5, 0.88, 0.82 }, ["Icy Veins"] = { 0.45, 0.72, 1 }, ["Guías extra"] = { 0.8, 0.6, 1 },
        ["Mis enlaces"] = { 1, 0.82, 0 } },
}

local frame
-- spec: tree index of the open tab (nil = pick the character's current one)
local state = { class = nil, spec = nil, category = "all", build = nil, compare = nil, search = "", hidden = {}, collapsed = {} }
local rows, cells, cards, specTabs, categoryChips = {}, {}, {}, {}, {}

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

local function flat(f, bg, border)
    if not f.SetBackdrop then Mixin(f, BackdropTemplateMixin) end
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
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

local function button(parent, label, width, onClick)
    local b = flat(CreateFrame("Button", nil, parent, "BackdropTemplate"), { 0.14, 0.14, 0.17, 1 })
    b:SetSize(width, 24)
    b.label = text(b, 12)
    b.label:SetPoint("CENTER")
    b.label:SetText(label)
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
        local haystack = (build.name .. " " .. (build.spec or "")):lower()
        if not state.hidden[build.source] and (state.category == "all" or categoryKey(build) == state.category)
            and (query == "" or haystack:find(query, 1, true)) then
            for _, g in ipairs(groups) do if g.source == build.source then table.insert(g.builds, build) end end
        end
    end
    return groups
end

-- ---------------------------------------------------------------- build list

local function listRow(index)
    if rows[index] then return rows[index] end
    local row = CreateFrame("Button", nil, frame.listContent, "BackdropTemplate")
    row:SetHeight(ROW_H - 4)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.accent = row:CreateTexture(nil, "ARTWORK")
    row.accent:SetPoint("TOPLEFT")
    row.accent:SetPoint("BOTTOMLEFT")
    row.accent:SetWidth(3)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(26, 26)
    row.icon:SetPoint("LEFT", 9, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.title = text(row, 12)
    row.title:SetPoint("TOPLEFT", 42, -5)
    row.title:SetPoint("RIGHT", -8, 0)
    row.sub = text(row, 10, C.dim)
    row.sub:SetPoint("BOTTOMLEFT", 42, 5)
    row.sub:SetPoint("RIGHT", -8, 0)
    row.tag = text(row, 10, C.onlyB, "RIGHT")
    row.tag:SetPoint("TOPRIGHT", -8, -5)
    row:SetScript("OnEnter", function(self)
        if self.build then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.build.name, 1, 1, 1)
            GameTooltip:AddLine("Clic: ver   ·   Clic derecho: comparar", 0.7, 0.7, 0.7)
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
            if state.class == ns.PlayerClass() then ns.Select(self.build) end
        end
        ns.Refresh()
    end)
    rows[index] = row
    return row
end

local function refreshList()
    local classData = ns.ClassData(state.class)
    local y, n = 0, 0
    for _, g in ipairs(visibleBuilds()) do
        if #g.builds > 0 then
            n = n + 1
            local row = flat(listRow(n), { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
            row.group, row.build, row.selectedRow, row.base = g.source, nil, false, { 0, 0, 0, 0 }
            row:SetHeight(GROUP_H)
            row:SetPoint("TOPLEFT", 0, -y)
            row:SetPoint("TOPRIGHT", 0, -y)
            row.icon:Hide()
            row.accent:Hide()
            row.sub:SetText("")
            row.tag:SetText("")
            row.title:SetPoint("TOPLEFT", 4, -6)
            row.title:SetText(paint((state.collapsed[g.source] and "+ " or "– ") .. g.source:upper(), C.source[g.source] or C.dim)
                .. paint("  " .. #g.builds, C.dim))
            row:Show()
            y = y + GROUP_H
            if not state.collapsed[g.source] then
                for _, build in ipairs(g.builds) do
                    n = n + 1
                    local selected = build == state.build
                    row = listRow(n)
                    row.base = selected and { 0.16, 0.16, 0.2, 1 } or C.panel
                    flat(row, row.base, selected and classColor(state.class) or C.line)
                    row.group, row.build, row.selectedRow = nil, build, selected
                    row:SetHeight(ROW_H - 4)
                    row:SetPoint("TOPLEFT", 0, -y)
                    row:SetPoint("TOPRIGHT", 0, -y)
                    local tree = lead(build, classData)
                    row.icon:SetTexture("Interface\\Icons\\" .. (tree and tree.icon or "inv_misc_questionmark"))
                    row.icon:Show()
                    row.accent:SetColorTexture(unpack(classColor(state.class)))
                    row.accent:SetShown(selected)
                    row.title:SetPoint("TOPLEFT", 42, -5)
                    row.title:SetText(build.name)
                    row.sub:SetText(("%s  ·  %s  ·  %s%s"):format(build.category or "sin tipo", build.spec or "",
                        table.concat(build.points, "/"),
                        build.level and ("  ·  nv " .. build.level) or ""))
                    row.tag:SetText(build == state.compare and "B" or "")
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
    c.watermark = c:CreateTexture(nil, "BACKGROUND", nil, 1)
    c.watermark:SetSize(CARD_W - 40, CARD_W - 40)
    c.watermark:SetPoint("CENTER", 0, -14)
    c.watermark:SetAlpha(0.06)
    c.watermark:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetSize(18, 18)
    c.icon:SetPoint("TOPLEFT", PAD, -9)
    c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c.title = text(c, 13)
    c.title:SetPoint("LEFT", c.icon, "RIGHT", 6, 0)
    c.points = text(c, 13, C.text, "RIGHT")
    c.points:SetPoint("TOPRIGHT", -PAD, -11)
    c.rule = c:CreateTexture(nil, "ARTWORK")
    c.rule:SetColorTexture(unpack(C.line))
    c.rule:SetHeight(1)
    c.rule:SetPoint("TOPLEFT", 1, -34)
    c.rule:SetPoint("TOPRIGHT", -1, -34)
    cards[t] = c
    return c
end

local function cellPos(talent)
    return PAD + (talent.col - 1) * (CELL + GAP), -(34 + PAD / 2) - (talent.row - 1) * (CELL + GAP)
end

local function cell(t, i)
    cells[t] = cells[t] or {}
    if cells[t][i] then return cells[t][i] end
    local c = flat(CreateFrame("Button", nil, card(t), "BackdropTemplate"), { 0, 0, 0, 1 })
    c:SetSize(CELL, CELL)
    c:SetFrameLevel(card(t):GetFrameLevel() + 2)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetPoint("TOPLEFT", 2, -2)
    c.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c.badge = flat(CreateFrame("Frame", nil, c, "BackdropTemplate"), { 0, 0, 0, 0.85 })
    c.badge:SetPoint("BOTTOMRIGHT", 5, -5)
    c.badge:SetSize(26, 14)
    c.rank = text(c.badge, 10, C.text, "CENTER")
    c.rank:SetPoint("CENTER", 0, 0)
    c.next = c:CreateTexture(nil, "OVERLAY")
    c.next:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    c.next:SetBlendMode("ADD")
    c.next:SetPoint("TOPLEFT", -8, 8)
    c.next:SetPoint("BOTTOMRIGHT", 8, -8)
    c:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.spell then GameTooltip:SetSpellByID(self.spell) else GameTooltip:SetText(self.name, 1, 1, 1) end
        for _, line in ipairs(self.info) do GameTooltip:AddLine(line[1], unpack(line[2])) end
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", GameTooltip_Hide)
    cells[t][i] = c
    return c
end

-- What one talent cell shows: border colour, rank label, dimmed, tooltip lines.
local function cellLook(a, b, max, mine)
    if b then -- comparing build A with B
        if a == 0 and b == 0 then return nil, "", true, {} end
        local info = { { ("A: %d/%d   B: %d/%d"):format(a, max, b, max), C.same } }
        if a == b then return C.same, tostring(a), false, info end
        if b == 0 then return C.onlyA, a .. "·0", false, info end
        if a == 0 then return C.onlyB, "0·" .. b, false, info end
        return C.differ, a .. "·" .. b, false, info
    end
    -- the label is always the build's rank; the border tells how far you are with it
    local label = a > 0 and (a .. "/" .. max) or ""
    if not mine then
        if a == 0 then return nil, "", true, {} end
        return C.pending, label, false, { { ("Build: %d/%d"):format(a, max), C.pending } }
    end
    local cur = mine
    local info = { { ("Build: %d/%d   Tú: %d"):format(a, max, cur), C.pending } }
    if a == 0 and cur == 0 then return nil, "", true, {} end
    if cur > a then return C.over, label, false, { { ("Tienes %d, la build usa %d"):format(cur, a), C.over } } end
    if cur == a then return C.done, label, false, info end
    return C.pending, label, false, info
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

local function refreshTrees(classData, tree)
    for _, list in pairs(cells) do for _, c in pairs(list) do c:Hide() end end
    for _, c in pairs(cards) do
        c:Hide()
        for _, l in ipairs(c.lines or {}) do l:Hide() end
    end
    local build, other = state.build, state.compare
    if not (build and classData) then return end

    local nt, ni
    if tree and not other then nt, ni = ns.NextStep(build, classData, tree) end
    for t, data in ipairs(classData.trees) do
        local c = card(t)
        c.icon:SetTexture("Interface\\Icons\\" .. (data.icon or "inv_misc_questionmark"))
        c.watermark:SetTexture("Interface\\Icons\\" .. (data.icon or "inv_misc_questionmark"))
        c.title:SetText(data.name)
        c.points:SetText(other and (paint(build.points[t], C.onlyA) .. paint(" · ", C.dim) .. paint(other.points[t], C.onlyB))
            or tostring(build.points[t]))
        c:Show()
        for i, tal in ipairs(data.talents) do
            local cl = cell(t, i)
            cl:SetPoint("TOPLEFT", cellPos(tal))
            cl.icon:SetTexture("Interface\\Icons\\" .. (tal.icon or "inv_misc_questionmark"))
            cl.name, cl.spell = tal.name, tree and tree.spell[t][i]
            local a = ns.TargetRank(build, t, i)
            local b = other and ns.TargetRank(other, t, i)
            local border, label, dim, info = cellLook(a, b, tal.max, tree and tree.rank[t][i])
            cl.info = info
            cl:SetBackdropBorderColor(unpack(border or C.line))
            cl.icon:SetDesaturated(dim)
            cl.icon:SetAlpha(dim and 0.3 or 1)
            cl.rank:SetText(label)
            if border then cl.rank:SetTextColor(unpack(border)) end
            cl.badge:SetShown(label ~= "")
            cl.badge:SetWidth(math.max(18, cl.rank:GetStringWidth() + 8))
            cl.next:SetShown(t == nt and i == ni)
            cl:Show()
        end
    end

    -- prerequisite arrows come from the game, so only for your own class
    for k, e in ipairs(tree and tree.edges or {}) do
        local from, to = cells[e[1]][e[2]], cells[e[3]][e[4]]
        local l = line(cards[e[1]], k)
        l:SetStartPoint("CENTER", from)
        l:SetEndPoint("CENTER", to)
        local used = ns.TargetRank(build, e[3], e[4]) > 0
        l:SetColorTexture(unpack(used and C.pending or C.line))
        l:Show()
    end
end

-- ---------------------------------------------------------------- spec tabs / type chips

local function refreshSpecTabs(classData, current)
    local trees = classData and classData.trees or {}
    local w = (LIST_W - (#trees - 1) * 4) / math.max(1, #trees)
    for t, data in ipairs(trees) do
        local tab = specTabs[t]
        tab:SetWidth(w)
        tab:SetPoint("TOPLEFT", (t - 1) * (w + 4), 0)
        tab.icon:SetTexture("Interface\\Icons\\" .. (data.icon or "inv_misc_questionmark"))
        tab.label:SetText(data.name .. (t == current and paint(" (tú)", C.done) or ""))
        local active = t == state.spec
        tab:SetBackdropColor(unpack(active and { 0.16, 0.16, 0.2, 1 } or C.panel))
        tab:SetBackdropBorderColor(unpack(active and classColor(state.class) or C.line))
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
        chip.label:SetText(chip.text .. " " .. n)
        chip:SetBackdropColor(unpack(active and { 0.16, 0.16, 0.2, 1 } or C.panel))
        chip:SetBackdropBorderColor(unpack(active and classColor(state.class) or C.line))
        chip.label:SetTextColor(unpack((active and C.text) or (n > 0 and C.same) or C.dim))
    end
end

-- ---------------------------------------------------------------- refresh

function ns.Refresh()
    if not (frame and frame:IsShown()) then return end
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

    frame.classLabel:SetText(paint(LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[state.class] or state.class,
        classColor(state.class)))
    refreshList()
    refreshTrees(classData, tree)

    local build = state.build
    frame.buildTitle:SetText(build and build.name or "No hay builds para esta clase")
    frame.buildSub:SetText(build and (paint(build.source, C.source[build.source] or C.dim) .. paint(
        ("  ·  %s  ·  %s%s"):format(build.spec or "", table.concat(build.points, "/"),
            build.level and ("  ·  nivel " .. build.level) or ""), C.dim)) or "")

    if state.compare then
        frame.legend:SetText(paint("A ", C.onlyA) .. (build and build.name or "") .. paint("   vs   B ", C.onlyB) .. state.compare.name
            .. "\n" .. swatch(C.onlyA, "solo A") .. "   " .. swatch(C.onlyB, "solo B") .. "   "
            .. swatch(C.differ, "rangos distintos") .. "   " .. swatch(C.same, "iguales"))
    elseif mine and tree then
        frame.legend:SetText(swatch(C.done, "aprendido") .. "   " .. swatch(C.pending, "pendiente") .. "   "
            .. swatch(C.over, "sobra") .. "     Clic derecho en otra build para comparar")
    else
        frame.legend:SetText(paint("Clic derecho en otra build para comparar", C.dim))
    end

    local status = ""
    if build and mine and not tree then
        status = paint(err or "", C.over)
    elseif build and tree then
        local nt, ni, nr = ns.NextStep(build, classData, tree)
        local free = ns.FreePoints(tree)
        status = (nt and ("Siguiente: " .. paint(classData.trees[nt].talents[ni].name, C.pending) .. (" (rango %d)"):format(nr))
            or paint("Build completa", C.done)) .. paint(("     Puntos libres: %d"):format(free), C.dim)
        if #tree.mismatches > 0 then
            status = status .. "\n" .. paint("Datos desfasados en: " .. table.concat(tree.mismatches, ", "), C.onlyB)
        end
    elseif build then
        status = paint("Solo puedes aplicar builds de tu clase.", C.dim)
    end
    frame.status:SetText(status)

    frame.link:SetText(build and (build.guide or build.url) or "")
    frame.link:SetCursorPosition(0)
    frame.apply:SetEnabled(tree ~= nil and build ~= nil)
    frame.compareMine:SetEnabled(tree ~= nil and build ~= nil)
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

    -- header bar: drag to move
    local header = flat(CreateFrame("Frame", nil, frame, "BackdropTemplate"), C.panel)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER_H)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() frame:StartMoving() end)
    header:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    local title = text(header, 14)
    title:SetPoint("LEFT", PAD, 0)
    title:SetText(paint("Z", C.pending) .. "builds")
    local close = button(header, "×", 24, function() frame:Hide() end)
    close:SetPoint("RIGHT", -4, 0)
    close.label:SetFont(STANDARD_TEXT_FONT, 16, "")

    -- left column: class switcher, search, source filters, list
    local top = -HEADER_H - PAD
    local prev = button(frame, "<", 26, function() cycleClass(-1) end)
    prev:SetPoint("TOPLEFT", PAD, top)
    local nextBtn = button(frame, ">", 26, function() cycleClass(1) end)
    nextBtn:SetPoint("TOPLEFT", PAD + LIST_W - 26, top)
    frame.classLabel = text(frame, 15, C.text, "CENTER")
    frame.classLabel:SetPoint("TOP", frame, "TOPLEFT", PAD + LIST_W / 2, top - 5)

    local tabs = CreateFrame("Frame", nil, frame)
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
        tab.label:ClearAllPoints()
        tab.label:SetPoint("LEFT", tab.icon, "RIGHT", 4, 0)
        tab.label:SetPoint("RIGHT", -4, 0)
        tab.label:SetJustifyH("LEFT")
        tab.label:SetFont(STANDARD_TEXT_FONT, 11, "")
        specTabs[t] = tab
    end

    local search = input(frame, LIST_W)
    search:SetPoint("TOPLEFT", PAD, top - 66)
    local hint = text(search, 12, C.dim)
    hint:SetPoint("LEFT", 8, 0)
    hint:SetText("Buscar build o especialización…")
    search:SetScript("OnTextChanged", function(self)
        state.search = self:GetText()
        hint:SetShown(state.search == "")
        ns.Refresh()
    end)

    local chipW = (LIST_W - (#SOURCES - 1) * 6) / #SOURCES
    for k, source in ipairs(SOURCES) do
        local chip
        chip = button(frame, source, chipW, function()
            state.hidden[source] = not state.hidden[source]
            chip:SetBackdropColor(unpack(state.hidden[source] and C.bg or { 0.14, 0.14, 0.17, 1 }))
            chip.label:SetTextColor(unpack(state.hidden[source] and C.dim or C.source[source]))
            ns.Refresh()
        end)
        chip:SetHeight(20)
        chip.label:SetFont(STANDARD_TEXT_FONT, 10, "")
        chip.label:SetTextColor(unpack(C.source[source]))
        chip:SetPoint("TOPLEFT", PAD + (k - 1) * (chipW + 6), top - 122)
    end

    local typeW = (LIST_W - (#CATEGORIES - 1) * 4) / #CATEGORIES
    for k, cat in ipairs(CATEGORIES) do
        local chip = button(frame, cat.label, typeW, function()
            state.category, state.build = cat.key, nil
            ns.Refresh()
        end)
        chip:SetHeight(20)
        chip:SetScript("OnEnter", nil)
        chip:SetScript("OnLeave", nil)
        chip.label:SetFont(STANDARD_TEXT_FONT, 10, "")
        chip.key, chip.text = cat.key, cat.label
        chip:SetPoint("TOPLEFT", PAD + (k - 1) * (typeW + 4), top - 96)
        categoryChips[k] = chip
    end

    local listTop = top - 150
    frame.list = CreateFrame("ScrollFrame", nil, frame)
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
    frame.empty = text(frame, 12, C.dim, "CENTER")
    frame.empty:SetPoint("TOP", frame.list, "TOP", 0, -20)
    frame.empty:SetText("Ninguna build coincide")

    local importBtn = button(frame, "+ Importar enlace", LIST_W, function() ns.ShowImport() end)
    importBtn:SetPoint("BOTTOMLEFT", PAD, PAD)
    importBtn:SetHeight(26)

    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(unpack(C.line))
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT", PAD + LIST_W + 8, -HEADER_H)
    divider:SetPoint("BOTTOMLEFT", PAD + LIST_W + 8, 0)

    -- right column: build header, legend, trees, actions
    local right = PAD + LIST_W + 16
    frame.buildTitle = text(frame, 16)
    frame.buildTitle:SetPoint("TOPLEFT", right, top)
    frame.buildTitle:SetWidth(TREES_W)
    frame.buildSub = text(frame, 11, C.dim)
    frame.buildSub:SetPoint("TOPLEFT", right, top - 22)
    frame.legend = text(frame, 11, C.text)
    frame.legend:SetPoint("TOPLEFT", right, top - 42)
    frame.legend:SetWordWrap(true)
    frame.legend:SetSpacing(3)

    frame.trees = CreateFrame("Frame", nil, frame)
    frame.trees:SetPoint("TOPLEFT", right, top - 78)
    frame.trees:SetSize(TREES_W, CARD_H)

    frame.status = text(frame, 12)
    frame.status:SetPoint("TOPLEFT", frame.trees, "BOTTOMLEFT", 0, -10)
    frame.status:SetWidth(TREES_W)
    frame.status:SetWordWrap(true)
    frame.status:SetSpacing(3)

    frame.apply = button(frame, "Aprender puntos libres", 170, function()
        local learned, err = ns.Apply(state.build, ns.ClassData(state.class))
        if learned then
            ns.Print(learned > 0 and ("aprendidos %d puntos de \"%s\"."):format(learned, state.build.name)
                or "no hay puntos libres o la build ya está completa.")
        else
            ns.Print("|cffff5050" .. err .. "|r")
        end
        ns.Refresh()
    end)
    frame.apply:SetPoint("BOTTOMLEFT", right, PAD + 18)
    frame.apply:SetBackdropColor(0.12, 0.3, 0.16, 1)

    frame.compareMine = button(frame, "Comparar con mis talentos", 180, function()
        local classData = ns.ClassData(state.class)
        local tree = ns.ReadTree(classData)
        state.compare = tree and ns.CurrentAsBuild(classData, tree)
        ns.Refresh()
    end)
    frame.compareMine:SetPoint("LEFT", frame.apply, "RIGHT", 8, 0)
    frame.clearCompare = button(frame, "Quitar comparación", 140, function()
        state.compare = nil
        ns.Refresh()
    end)
    frame.clearCompare:SetPoint("LEFT", frame.compareMine, "RIGHT", 8, 0)
    frame.remove = button(frame, "Borrar", 90, function()
        if state.build and state.build.imported then
            ns.RemoveImport(state.build)
            state.build = nil
            ns.Refresh()
        end
    end)
    frame.remove:SetPoint("LEFT", frame.clearCompare, "RIGHT", 8, 0)

    -- link to the source, selectable for Ctrl+C
    frame.link = input(frame, TREES_W)
    frame.link:SetPoint("BOTTOMLEFT", right, PAD + 50)
    frame.link:SetTextColor(unpack(C.dim))
    frame.link:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    frame.link:SetScript("OnTextChanged", function(self, user)
        if user then
            self:SetText(state.build and (state.build.guide or state.build.url) or "")
            self:HighlightText()
        end
    end)

    local credits = text(frame, 10, C.dim)
    credits:SetPoint("BOTTOMLEFT", right, 8)
    credits:SetText(("Datos: Talents Forever (CC BY 4.0) e Icy Veins  ·  actualizado %s  ·  enlace: clic y Ctrl+C")
        :format(ZbuildsData and ZbuildsData.generated or "?"))
end

-- ---------------------------------------------------------------- import dialog

local dialog

local function createImport()
    dialog = flat(CreateFrame("Frame", "ZbuildsImport", frame, "BackdropTemplate"), C.bg, C.pending)
    dialog:SetSize(460, 214)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("DIALOG")
    dialog:EnableMouse(true)
    tinsert(UISpecialFrames, "ZbuildsImport")

    local title = text(dialog, 14)
    title:SetPoint("TOPLEFT", PAD, -PAD)
    title:SetText("Importar enlace de build")
    local help = text(dialog, 10, C.dim)
    help:SetPoint("TOPLEFT", PAD, -34)
    help:SetText("Enlace de talentsforever.com o de la calculadora de Icy Veins (#tc-). Se guarda en tu cuenta.")

    dialog.url = input(dialog, 460 - 2 * PAD)
    dialog.url:SetPoint("TOPLEFT", PAD, -54)
    dialog.name = input(dialog, 460 - 2 * PAD)
    dialog.name:SetPoint("TOPLEFT", PAD, -86)
    local urlHint, nameHint = text(dialog.url, 12, C.dim), text(dialog.name, 12, C.dim)
    urlHint:SetPoint("LEFT", 8, 0)
    urlHint:SetText("Pega aquí el enlace (Ctrl+V)")
    nameHint:SetPoint("LEFT", 8, 0)
    nameHint:SetText("Nombre (opcional)")
    dialog.url:SetScript("OnTextChanged", function(self) urlHint:SetShown(self:GetText() == "") end)
    dialog.name:SetScript("OnTextChanged", function(self) nameHint:SetShown(self:GetText() == "") end)

    -- type: one of the CATEGORIES except "all"
    dialog.types = {}
    local typeW = (460 - 2 * PAD - 3 * 4) / 4
    for k, cat in ipairs({ CATEGORIES[5], CATEGORIES[2], CATEGORIES[3], CATEGORIES[4] }) do
        local chip = button(dialog, cat.label, typeW, function()
            dialog.category = cat.key
            for _, other in ipairs(dialog.types) do
                local active = other.key == dialog.category
                other:SetBackdropBorderColor(unpack(active and C.pending or C.line))
                other.label:SetTextColor(unpack(active and C.text or C.dim))
            end
        end)
        chip.key = cat.key
        chip:SetScript("OnEnter", nil)
        chip:SetScript("OnLeave", nil)
        chip:SetPoint("TOPLEFT", PAD + (k - 1) * (typeW + 4), -118)
        dialog.types[k] = chip
    end

    dialog.error = text(dialog, 11, C.over)
    dialog.error:SetPoint("TOPLEFT", PAD, -150)
    dialog.error:SetWidth(460 - 2 * PAD)
    dialog.error:SetWordWrap(true)

    local ok = button(dialog, "Importar", 120, function()
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
        ns.Print(("importada \"%s\" (%s)."):format(build.name, table.concat(build.points, "/")))
        ns.Refresh()
    end)
    ok:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    ok:SetBackdropColor(0.12, 0.3, 0.16, 1)
    local cancel = button(dialog, "Cancelar", 100, function() dialog:Hide() end)
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
        ns.Print("falta Data.lua: ejecuta tools/update_builds.py")
        return
    end
    if not frame then
        create()
        state.class = ns.PlayerClass()
        frame:Hide()
    end
    frame:SetShown(not frame:IsShown())
end
