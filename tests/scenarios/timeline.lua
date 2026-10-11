local cd = ns.ClassData("SHAMAN")
ns.Toggle(); ZbuildsFrame.scripts.OnShow()
local f, out = ZbuildsFrame, {}
local function visibleSteps() local n, s = 0 for _, o in ipairs(ALL) do if o.k and o.shown and o.level then n = n + 1 end end return n end
out[#out+1] = "timeline steps shown: " .. visibleSteps() .. " | title: " .. tostring(f.timelineTitle.text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
-- click point 20: the trees must show exactly 20 points
local target
for _, o in ipairs(ALL) do if o.k == 20 and o.level then target = o end end
target.scripts.OnClick(target)
local sum = 0
for _, o in ipairs(ALL) do if o.points and o.barA and o.shown then sum = sum + tonumber((tostring(o.points.text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))) end end
out[#out+1] = "preview at point 20 -> card points sum " .. sum .. " | " .. tostring(f.timelineTitle.text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
target.scripts.OnClick(target)
out[#out+1] = "after second click: " .. tostring(f.timelineTitle.text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
-- compare: right-click another visible build
local rowsB = {}
for _, o in ipairs(ALL) do if o.build and o.shown then rowsB[#rowsB+1] = o end end
rowsB[#rowsB].scripts.OnClick(rowsB[#rowsB], "RightButton")
local chips = 0
for _, o in ipairs(ALL) do if o.ranks and o.shown then chips = chips + 1 end end
out[#out+1] = "compare: diff chips " .. chips .. " | steps visible " .. visibleSteps() .. " | " .. tostring(f.timelineTitle.text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
return table.concat(out, "\n")
