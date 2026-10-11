local out = {}
local strip = function(x) return (tostring(x):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
PlayerSpellsFrame = STUB(); PlayerSpellsFrame.GetWidth = function() return 1361 end; PlayerSpellsFrame.GetHeight = function() return 794 end
local nodes = ForeverBuildsProbeDB.trees[1].nodes
local buttons, MARKED = {}, {}
for k, n in ipairs(nodes) do
  local b = STUB(); b.slot = k
  b.GetNodeID = function(self) return nodes[self.slot].id end
  b.GetFrameLevel = function(self) MARKED[#MARKED+1] = nodes[self.slot].entries[1].name return 1 end
  buttons[#buttons+1] = b
end
local holder = STUB(); holder.GetChildren = function() return unpack(buttons) end
PlayerSpellsFrame.GetChildren = function() return holder end
MenuUtil = { CreateContextMenu = function(owner, gen)
  local root = { radios = {} }
  function root:SetScrollMode() end
  function root:CreateTitle(t) self.titles = self.titles or {} self.titles[#self.titles+1] = t end
  function root:CreateRadio(label, isSel, setSel) self.radios[#self.radios+1] = { label = label, setSel = setSel } end
  gen(owner, root); MENU = root end }
for _, o in ipairs(ALL) do if o.scripts.OnEvent then o.scripts.OnEvent(o, "ADDON_LOADED", "Blizzard_PlayerSpells") end end
local bar for _, o in ipairs(ALL) do if o.pick and o.learn then bar = o end end
bar.pick.scripts.OnClick(bar.pick)
-- an Enhancement build whose first point is Thundering Strikes, like the screenshot
for _, r in ipairs(MENU.radios) do if strip(r.label):find("PvP guide") and strip(r.label):find("Enhancement") then r.setSel() end end
out[#out+1] = "bar next: " .. strip(bar.next.text.text) .. " | first mark on: " .. tostring(MARKED[1])
-- the game redraws: every button now shows another talent (pool reuse)
for _, b in ipairs(buttons) do b.slot = b.slot % #nodes + 1 end
wipe(MARKED)
ns.RefreshTalentBar()
out[#out+1] = "after the game reuses its buttons -> first mark on: " .. tostring(MARKED[1])
-- loadouts: save two builds from the Zbuilds window
ns.Toggle(); ZbuildsFrame.scripts.OnShow()
local f = ZbuildsFrame
local rowsB = {} for _, o in ipairs(ALL) do if o.build and o.shown then rowsB[#rowsB+1] = o end end
rowsB[1].scripts.OnClick(rowsB[1], "LeftButton"); f.loadout.scripts.OnClick(f.loadout)
local firstName = rowsB[1].build.name
rowsB[2].scripts.OnClick(rowsB[2], "LeftButton"); f.loadout.scripts.OnClick(f.loadout)
local stars = 0 for _, o in ipairs(ALL) do if o.star and o.star.shown and o.build then stars = stars + 1 end end
out[#out+1] = "bar after clicking builds in Zbuilds (must stay the PvP guide): " .. strip(bar.pick.text.text)
out[#out+1] = "saved 2 loadouts | stars in list: " .. stars .. " | window button now: '" .. strip(f.loadout.label.text) .. "'"
out[#out+1] = "bar sub: " .. strip(bar.pick.sub.text)
bar.rotate[2].scripts.OnClick(bar.rotate[2])
out[#out+1] = "rotate >: '" .. strip(bar.pick.text.text) .. "' (" .. strip(bar.pick.sub.text) .. ")"
bar.rotate[2].scripts.OnClick(bar.rotate[2])
out[#out+1] = "rotate > again: '" .. strip(bar.pick.text.text) .. "' (" .. strip(bar.pick.sub.text) .. ")  first saved was: " .. firstName
bar.pick.scripts.OnClick(bar.pick)
out[#out+1] = "menu: first title " .. tostring(MENU.titles[1]) .. " | " .. strip(MENU.radios[1].label) .. " | " .. strip(MENU.radios[2].label)
f.loadout.scripts.OnClick(f.loadout)
out[#out+1] = "after removing one: loadouts=" .. #ns.Loadouts("SHAMAN") .. " | button: '" .. strip(f.loadout.label.text) .. "'"
-- renaming: the game's text prompt, simulated
OKAY, CANCEL = "Okay", "Cancel"
local box = { text = "" }
function box:SetText(t) self.text = t end
function box:GetText() return self.text end
function box:HighlightText() end
function box:SetFocus() end
StaticPopup_Show = function(which, text1, text2, data)
  LAST_POPUP = { which = which, text = text1, data = data }
  local popup = { editBox = box, data = data }
  StaticPopupDialogs[which].OnShow(popup, data)
  return popup
end
rowsB[1].scripts.OnClick(rowsB[1], "LeftButton")
out[#out+1] = "rename button shown on the loadout: " .. tostring(f.rename.shown)
f.rename.scripts.OnClick(f.rename)
out[#out+1] = "prompt: " .. LAST_POPUP.text .. " | prefilled: " .. box.text
box.text = "Mi Elemental"
StaticPopupDialogs.ZBUILDS_RENAME_LOADOUT.OnAccept({ editBox = box }, LAST_POPUP.data)
out[#out+1] = "after rename: window title '" .. strip(f.buildTitle.text) .. "' | row '" .. strip(rowsB[1].title.text) .. "'"
bar.rotate[2].scripts.OnClick(bar.rotate[2])
out[#out+1] = "bar shows: '" .. strip(bar.pick.text.text) .. "'"
bar.pick.scripts.OnClick(bar.pick)
out[#out+1] = "menu loadout entry: " .. strip(MENU.radios[1].label)
bar.pick.scripts.OnClick(bar.pick, "RightButton")
out[#out+1] = "right-click on picker opens prompt for: " .. LAST_POPUP.data.name
box.text = "   "
StaticPopupDialogs.ZBUILDS_RENAME_LOADOUT.OnAccept({ editBox = box }, LAST_POPUP.data)
out[#out+1] = "blank name -> back to: '" .. strip(bar.pick.text.text) .. "'"
-- a loadout saved as a plain link (before names existed) still works
table.insert(ZbuildsCharDB.loadouts, rowsB[3].build.url)
out[#out+1] = "old-format entry read: loadouts=" .. #ns.Loadouts("SHAMAN") .. " entry type now " .. type(ZbuildsCharDB.loadouts[#ZbuildsCharDB.loadouts])
return table.concat(out, "\n")
