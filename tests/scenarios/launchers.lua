local cd = ns.ClassData("SHAMAN")
local out = {}
GetBuildInfo = function() return "1.60.1", "70205", "", 16001 end
PRINTED = {}
local realPrint = print
print = function(...) local t = {} for k = 1, select("#", ...) do t[#t+1] = tostring(select(k, ...)) end PRINTED[#PRINTED+1] = table.concat(t, " ") end
-- diag
SlashCmdList.ZBUILDS("diag")
out[#out+1] = "diag lines: " .. #PRINTED
for _, l in ipairs(PRINTED) do out[#out+1] = "   " .. l:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
-- minimap toggle (button created lazily)
Minimap = STUB(); Minimap.GetWidth = function() return 140 end; GetCursorPosition = function() return 0, 0 end
ns.ToggleMinimapButton(); out[#out+1] = "minimap hidden=" .. tostring(ZbuildsDB.minimap.hide) .. " shown=" .. tostring(ZbuildsMinimapButton.shown)
ns.ToggleMinimapButton(); out[#out+1] = "minimap hidden=" .. tostring(ZbuildsDB.minimap.hide) .. " shown=" .. tostring(ZbuildsMinimapButton.shown)
out[#out+1] = "compartment fn: " .. type(Zbuilds_OnCompartmentClick)
-- merged build in the UI
local merged
for _, x in ipairs(ZbuildsData.builds) do if x.also then merged = x break end end
UnitClass = function() return merged.class, merged.class end
ns.Toggle(); ZbuildsFrame.scripts.OnShow()
local f = ZbuildsFrame
if merged then
  for _, o in ipairs(ALL) do if o.label and o.label.text and tostring(o.label.text):find("^" .. merged.spec) then o.scripts.OnClick() end end
  for _, o in ipairs(ALL) do if o.build == merged then o.scripts.OnClick(o, "LeftButton") end end
  local row for _, o in ipairs(ALL) do if o.build == merged then row = o end end
  out[#out+1] = "merged row sub: " .. tostring(row and row.sub.text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  out[#out+1] = "merged header: " .. tostring(f.buildSub.text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end
-- beta filter
local function shown() local n = 0 for _, o in ipairs(ALL) do if o.build and o.shown then n = n + 1 end end return n end
local before = shown()
for _, o in ipairs(ALL) do if o.label and o.label.text == "Beta" then o.scripts.OnClick() end end
out[#out+1] = ("beta filter: rows %d -> %d"):format(before, shown())
print = realPrint
return table.concat(out, "\n")
