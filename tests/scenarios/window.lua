-- give the character some talents so edges/compare have something to show
for _, n in pairs(C_Traits.GetTreeNodes and {} or {}) do end
local cd0 = ns.ClassData("SHAMAN")
FREE = 5
ns.Apply(ns.BuildsFor("SHAMAN")[1], cd0)    -- 5 points into Enhancement: current spec = Enhancement
ns.Toggle()
ZbuildsFrame.scripts.OnShow()
local cd = ns.ClassData("SHAMAN")
local tree = ns.ReadTree(cd)
local out = { "edges: " .. #tree.edges }
local builds = ns.BuildsFor("SHAMAN")
-- compare with another build and with my talents
local f = ZbuildsFrame
local function visible() local n = {} for _, o in ipairs(ALL) do if o.build and o.shown then n[#n+1] = o.build.name end end return n end
local function tab(prefix) for _, o in ipairs(ALL) do if o.label and type(o.label.text) == "string" and o.label.text:find("^" .. prefix) then return o end end end
out[#out+1] = "open tab -> " .. #visible() .. " builds: " .. table.concat(visible(), " | ")
out[#out+1] = "enh tab label: " .. tab("Enhancement").label.text
tab("Restoration").scripts.OnClick()
out[#out+1] = "resto tab -> " .. table.concat(visible(), " | ")
tab("PvE").scripts.OnClick()
out[#out+1] = "resto PvE -> " .. table.concat(visible(), " | ")
tab(ns.L.CAT_all).scripts.OnClick()
tab("Enhancement").scripts.OnClick()
local function rowFor(b) for _, o in ipairs(ALL) do if o.build == b then return o end end end
-- select build 3, compare (right click) build 5, then compare with my talents, then clear
rowFor(builds[3]).scripts.OnClick(rowFor(builds[3]), "LeftButton")
out[#out+1] = "title: " .. f.buildTitle.text
rowFor(builds[5]).scripts.OnClick(rowFor(builds[5]), "RightButton")
out[#out+1] = "legend: " .. f.legend.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
f.apply.scripts.OnClick()
f.compareMine.scripts.OnClick()
out[#out+1] = "legend2: " .. f.legend.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
f.clearCompare.scripts.OnClick()
out[#out+1] = "status: " .. f.status.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
-- group collapse + search + other class
for _, o in ipairs(ALL) do if o.group == "Icy Veins" then o.scripts.OnClick(o, "LeftButton") break end end
local shownRows = 0 for _, o in ipairs(ALL) do if o.build and o.shown then shownRows = shownRows + 1 end end
out[#out+1] = "rows shown after collapsing Icy Veins: " .. shownRows
out[#out+1] = "edges now: " .. #ns.ReadTree(cd).edges
ns.ShowImport()
local dlg = ZbuildsImport
dlg.url.text = "no es un enlace"
for _, o in ipairs(ALL) do if o.label and o.label.text == ns.L.IMPORT then o.scripts.OnClick() end end
out[#out+1] = "dialog error: " .. dlg.error.text
dlg.url.text = "https://www.icy-veins.com/wow-forever/shaman-talent-calculator#tc-111114442267772a99988"
dlg.name.text = "Mi elemental"
for _, o in ipairs(ALL) do if o.label and o.label.text == "PvP" and o.key then o.scripts.OnClick() end end
for _, o in ipairs(ALL) do if o.label and o.label.text == ns.L.IMPORT then o.scripts.OnClick() end end
out[#out+1] = "after import: " .. f.buildTitle.text .. " | " .. f.buildSub.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. " | remove shown " .. tostring(f.remove.shown)
f.remove.scripts.OnClick()
out[#out+1] = "after delete: " .. f.buildTitle.text .. " | imports " .. #ns.Imports()
return table.concat(out, "\n")
