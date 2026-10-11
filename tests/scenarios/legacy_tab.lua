local out = {}
local strip = function(x) return (tostring(x):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
-- the game's Legacy config, rebuilt from the player's real /zb legacy dump
local real
for _, c in ipairs(REAL_DUMP_DB.legacyDump.configs) do if c.info and c.info.type == 3 then real = c end end
local LCFG, legacyNodes, treeNodes, entries = real.id, {}, {}, {}
for _, tree in ipairs(real.trees) do
  treeNodes[tree.id] = {}
  for _, n in ipairs(tree.nodes) do
    legacyNodes[n.id] = { ID = n.id, posX = n.x, posY = n.y, maxRanks = n.maxRanks, currentRank = n.currentRank, ranksPurchased = n.ranksPurchased, entryIDs = { n.entries[1].id } }
    entries[n.entries[1].id] = n.entries[1].spellID
    table.insert(treeNodes[tree.id], n.id)
  end
end
local cNode, cTree, cEntry, cDef, cCur = C_Traits.GetNodeInfo, C_Traits.GetTreeNodes, C_Traits.GetEntryInfo, C_Traits.GetDefinitionInfo, C_Traits.GetTreeCurrencyInfo
C_Traits.GetConfigIDByTreeID = function(tree) if treeNodes[tree] then return LCFG end end
C_Traits.GetNodeInfo = function(cfg, id) if cfg == LCFG then return legacyNodes[id] end return cNode(cfg, id) end
C_Traits.GetTreeNodes = function(tree) return treeNodes[tree] or cTree(tree) end
C_Traits.GetEntryInfo = function(cfg, id) if cfg == LCFG then return { definitionID = 900000 + id } end return cEntry(cfg, id) end
C_Traits.GetDefinitionInfo = function(id) if id > 900000 then return { spellID = entries[id - 900000] } end return cDef(id) end
local legacySpent = 0
C_Traits.GetTreeCurrencyInfo = function(cfg, tree) if cfg == LCFG then return { { quantity = 16 - legacySpent, maxQuantity = 16, spent = legacySpent } } end return cCur(cfg, tree) end
C_Spell.GetSpellName = function(id) for _, tree in ipairs(real.trees) do for _, n in ipairs(tree.nodes) do if n.entries[1].spellID == id then return n.entries[1].name end end end end

local ach = {}
for _, c in ipairs(REAL_DUMP_DB.legacyDump.achievements.categories) do for _, a in ipairs(c.achievements) do ach[a.id] = a end end
ach[62012].criteria[1].quantity = 120   -- Journeyman Alchemist: 120/150
ach[62031].criteria[1].done = true; ach[62031].criteria[2].done = true   -- 2 dungeons of Novice Spelunker
GetAchievementInfo = function(id) local a = ach[id] if not a then return nil end return id, a.name, a.points, a.completed, nil, nil, nil, a.description, a.flags, "Interface\Icons\ach_" .. id end
GetAchievementNumCriteria = function(id) return ach[id] and #ach[id].criteria or 0 end
GetAchievementCriteriaInfo = function(id, c) local cr = ach[id].criteria[c] return cr.text, nil, cr.done, cr.quantity, cr.required end
C_EventUtils = { IsEventValid = function(e) return e ~= "CRITERIA_UPDATE" end }
ns.Toggle(); ZbuildsFrame.scripts.OnShow()
local f = ZbuildsFrame
local function tab(mode) for _, t in ipairs(f.modeTabs) do if t.mode == mode then return t end end end
tab("legacy").scripts.OnClick(tab("legacy"))
out[#out+1] = "views: talents shown=" .. tostring(f.talentsView.shown) .. " legacy shown=" .. tostring(f.legacyView.shown)
local lv = f.legacyView
out[#out+1] = "points: " .. strip(lv.points.text)
local plansShown = {} for _, o in ipairs(ALL) do if o.plan ~= nil and o.title and o.shown then plansShown[#plansShown+1] = strip(o.title.text) end end
out[#out+1] = "plan title: " .. strip(lv.planTitle.text) .. " | " .. strip(lv.planSub.text)
out[#out+1] = "status: " .. strip(lv.status.text)
local badges, mapped = {}, 0
for _, o in ipairs(ALL) do if o.badge and o.next and o.shown and o.badge.shown and o.name then badges[#badges+1] = o.name .. "=" .. strip(o.badge.text.text) end end
table.sort(badges)
out[#out+1] = "perk badges: " .. table.concat(badges, ", ")
local legacy = ns.ReadLegacy(ns.LegacyData())
for t = 1, 3 do for i in pairs(legacy.node[t]) do mapped = mapped + 1 end end
out[#out+1] = "nodes matched to perks by position: " .. mapped .. "/21"
-- spend the plan's first 3 points in the game: the next step and colours follow
local plan = ns.LegacyData().plans[1]
for k = 1, 3 do local t, i = plan.order[k][1], plan.order[k][2]; local n = legacyNodes[legacy.node[t][i]]; n.currentRank = n.currentRank + 1; n.ranksPurchased = n.ranksPurchased + 1 end
legacySpent = 3
ns.Refresh()
out[#out+1] = "after spending 3: " .. strip(lv.points.text) .. " | " .. strip(lv.status.text)
-- choose another plan, then no plan
local rows = {} for _, o in ipairs(ALL) do if o.sub and o.accent and o.title and o.shown and o.scripts.OnClick and not o.build and not o.group then rows[#rows+1] = o end end
for _, r in ipairs(rows) do if strip(r.title.text):find("Profesiones") or strip(r.title.text):find("Professions") then r.scripts.OnClick(r) end end
out[#out+1] = "chose: " .. strip(lv.planTitle.text) .. " | " .. strip(lv.planSub.text)
for _, r in ipairs(rows) do if r.plan == nil then r.scripts.OnClick(r) end end
out[#out+1] = "no plan: '" .. strip(lv.planTitle.text) .. "' order shown=" .. tostring(lv.order.shown)
-- the challenge tracker
local rows = {}
for _, o in ipairs(ALL) do if o.dots and o.shown then rows[#rows+1] = o end end
table.sort(rows, function(a, b) return a.id and b.id and false end)
out[#out+1] = "challenges: " .. strip(lv.challengeTitle.text)
local list = ns.LegacyChallenges()
local firsts = {}
for k = 1, 6 do firsts[#firsts+1] = list[k].name .. (list[k].progressText ~= "" and (" " .. list[k].progressText) or "") .. " [t" .. list[k].tier .. "]" end
out[#out+1] = "first pending: " .. table.concat(firsts, " | ")
out[#out+1] = "last: " .. list[#list].name .. " completed=" .. tostring(list[#list].completed) .. " | total " .. #list
out[#out+1] = "rows shown: " .. #rows
lv.hideDone.scripts.OnClick(lv.hideDone)
local after = 0 for _, o in ipairs(ALL) do if o.dots and o.shown then after = after + 1 end end
out[#out+1] = "hide done -> rows " .. after .. " | button '" .. strip(lv.hideDone.label.text) .. "'"
-- clicking a challenge: three kinds of client
local row1 for _, o in ipairs(ALL) do if o.dots and o.shown and o.id then row1 = o break end end
local function reopen() ZbuildsFrame.shown = true; ns.Refresh() end
PRINTED = {}
print = function(...) local t = {} for k = 1, select("#", ...) do t[#t+1] = tostring(select(k, ...)) end PRINTED[#PRINTED+1] = table.concat(t, " ") end
ShowLegacyChallenge = function(id) OPENED = "legacy window " .. id end
row1.scripts.OnClick(row1)
out[#out+1] = ("A) Forever: %s, links in chat %d, Zbuilds shown=%s"):format(tostring(OPENED), #PRINTED, tostring(ZbuildsFrame.shown))
OPENED = nil; ShowLegacyChallenge = function() error("bad id") end
ShowAchievementFrameForAchievement = function(id) OPENED = "achievement window " .. id end
row1.scripts.OnClick(row1)
out[#out+1] = ("B) first fails, next works: %s, links in chat %d"):format(tostring(OPENED), #PRINTED)
ShowLegacyChallenge, ShowAchievementFrameForAchievement = nil, nil
GetAchievementLink = function(id) return "|cffffff00|Hachievement:" .. id .. "|h[Achievement]|h|r" end
row1.scripts.OnClick(row1)
out[#out+1] = ("C) nothing: chat got '%s'"):format(strip(PRINTED[#PRINTED] or ""))
tab("talents").scripts.OnClick(tab("talents"))
out[#out+1] = "back to talents: talents shown=" .. tostring(f.talentsView.shown) .. " legacy shown=" .. tostring(f.legacyView.shown)
-- a challenge done: the Legacy banner names it and the perk the plan wants next
ZbuildsCharDB.legacyPlan = ns.LegacyData().plans[1].name
C_Timer.After = function(_, fn) fn() end
STANDARD_TEXT_FONT = "font"; SOUNDKIT = { RAID_WARNING = 1 }; PlaySound = function() end
for _, o in ipairs(ALL) do if o.scripts.OnEvent then o.scripts.OnEvent(o, "ACHIEVEMENT_EARNED", 62006) end end
local banner for _, o in ipairs(ALL) do if o.lines and o.anim then banner = o end end
local bl = {} for _, fs in ipairs(banner.lines) do if fs.shown and fs.text ~= "" then bl[#bl+1] = strip(fs.text) end end
out[#out+1] = "legacy banner: " .. tostring(banner.title.text) .. " | " .. tostring(banner.sub.text) .. " | " .. table.concat(bl, " | ")
banner.shown = false
for _, o in ipairs(ALL) do if o.scripts.OnEvent then o.scripts.OnEvent(o, "ACHIEVEMENT_EARNED", 12345) end end
out[#out+1] = "other achievement: banner shown " .. tostring(banner.shown)
ns.SetOption("legacyAlert", false)
for _, o in ipairs(ALL) do if o.scripts.OnEvent then o.scripts.OnEvent(o, "ACHIEVEMENT_EARNED", 62006) end end
out[#out+1] = "legacy alert off: banner shown " .. tostring(banner.shown)
ZbuildsDB.options = nil
-- the Options tab: toggles, the duration, the minimap button
Minimap = Minimap or CreateFrame("Frame")
tab("options").scripts.OnClick(tab("options"))
out[#out+1] = "options tab: options shown=" .. tostring(f.optionsView.shown) .. " legacy shown=" .. tostring(f.legacyView.shown)
local rowsByKey = {} for _, o in ipairs(ALL) do if o.key and o.box then rowsByKey[o.key] = o end end
local states = {}
for _, key in ipairs({ "banner", "sound", "talentAlert", "legacyAlert", "chat", "minimap" }) do states[#states+1] = key .. "=" .. tostring(rowsByKey[key].check.shown) end
out[#out+1] = "toggles: " .. table.concat(states, " ")
rowsByKey.sound.scripts.OnClick(rowsByKey.sound)
rowsByKey.minimap.scripts.OnClick(rowsByKey.minimap)
out[#out+1] = "after clicks: sound option " .. tostring(ns.Option("sound")) .. " check " .. tostring(rowsByKey.sound.check.shown)
    .. " | minimap shown " .. tostring(ns.MinimapButtonShown()) .. " check " .. tostring(rowsByKey.minimap.check.shown)
local durations = {}
for k = 1, 4 do f.optionsView.duration.scripts.OnClick(f.optionsView.duration) durations[#durations+1] = ns.Option("duration") end
out[#out+1] = "duration cycle: " .. table.concat(durations, ",") .. " | label " .. strip(f.optionsView.duration.label.text)
ZbuildsDB.options = nil
SlashCmdList.ZBUILDS("options")
out[#out+1] = "/zb options: options shown=" .. tostring(f.optionsView.shown)
return table.concat(out, "\n")
