-- WoW API stubs for the scenarios: talents, then frames. The game's talent tree is laid out from Data.lua's
-- shaman tree (the game's grid: nodes 600 apart, trees far apart), so the scenarios test the addon, not
-- whether the sites' data still fits the game: the "game" scenario checks that against a real dump.
floor = math.floor; tinsert = table.insert; SlashCmdList = {}; StaticPopupDialogs = {}; GetLocale = function() return LOCALE end; CreateColor = function(...) return {...} end; strtrim = function(x) return (x:gsub('^%s+', ''):gsub('%s+$', '')) end
FREE = 11
local nodes = {}
for t, tree in ipairs(ZbuildsData.classes.SHAMAN.trees) do
  for i, tal in ipairs(tree.talents) do
    local id = t * 1000 + i
    nodes[id] = { ID = id, posX = (t - 1) * 3600 + tal.col * 600, posY = tal.row * 600, maxRanks = tal.max, currentRank = 0,
                  entryIDs = { id }, isVisible = true, visibleEdges = {}, spell = tal.spell or id, name = tal.name }
  end
end
TREE_NODES = nodes
local entries = {}
for _, n in pairs(nodes) do entries[n.entryIDs[1]] = n end
function UnitClass() return "Shaman", "SHAMAN" end
function UnitLevel() return 20 end
function InCombatLockdown() return false end
function CreateFrame() return { RegisterEvent = function() end, SetScript = function() end } end
C_Timer = { After = function() end }
C_Spell = { GetSpellName = function(id) for _, n in pairs(nodes) do if n.spell == id then return n.name end end end }
C_ClassTalents = { GetActiveConfigID = function() return 1 end, ImportLoadout = function(cfg, entries, name) for _, e in ipairs(entries) do for _, f in ipairs({'nodeID','ranksGranted','ranksPurchased','selectionEntryID'}) do if type(e[f]) ~= 'number' then error('bad argument (Current Field: [' .. f .. '])') end end end LOADOUT = { entries = entries, name = name } return true end }
PURCHASED = {}
C_Traits = {
  GetConfigInfo = function() return { treeIDs = { 1082 } } end,
  GetTreeNodes = function() local t = {} for id in pairs(nodes) do t[#t+1] = id end return t end,
  GetNodeInfo = function(_, id) return nodes[id] end,
  GetEntryInfo = function(_, id) return { definitionID = id } end,
  GetDefinitionInfo = function(id) return { spellID = entries[id].spell } end,
  GetTreeCurrencyInfo = function() return { { quantity = FREE } } end,
  PurchaseRank = function(_, id) local n = nodes[id]
     if FREE <= 0 or n.currentRank >= n.maxRanks then return false end
     n.currentRank = n.currentRank + 1; FREE = FREE - 1; PURCHASED[#PURCHASED+1] = n.name; return true end,
  CommitConfig = function() return true end,
  RollbackConfig = function() end,
}

local numbers = { GetVerticalScroll = 0, GetHeight = 400, GetStringWidth = 12, GetFrameLevel = 1, GetWidth = 120 }
local function stub()
  local o = { scripts = {}, shown = true, text = "" }
  return setmetatable(o, { __index = function(t, k)
    if not k:match("^%u") then return nil end
    if k == "SetScript" then return function(self, n, f) self.scripts[n] = f end end
    if k == "GetScript" then return function(self, n) return self.scripts[n] end end
    if k == "HookScript" then return function(self, n, f) self.hooks = self.hooks or {} self.hooks[n] = self.hooks[n] or {} table.insert(self.hooks[n], f) end end
    if k == "Show" then return function(self) self.shown = true end end
    if k == "Hide" then return function(self) self.shown = false end end
    if k == "SetShown" then return function(self, v) self.shown = not not v end end
    if k == "IsShown" then return function(self) return self.shown end end
    if k == "IsEnabled" then return function() return true end end
    if k == "SetText" then return function(self, v) self.text = v end end
    if k == "SetDesaturated" then return function(self, v) self.desaturated = v end end
    if k == "SetEnabled" then return function(self, v) self.enabled = v end end
    if k == "GetText" then return function(self) return self.text end end
    if k == "CreateTexture" or k == "CreateFontString" or k == "CreateLine" or k == "CreateAnimationGroup" or k == "CreateAnimation" then return function() return stub() end end
    if numbers[k] then return function() return numbers[k] end end
    return function(self) return nil end
  end })
end
STUB = stub
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
ALL = {}
function CreateFrame(_, name) local o = stub(); ALL[#ALL+1] = o; if name then _G[name] = o end return o end
UIParent = stub(); GameTooltip = stub(); GameTooltip_Hide = function() end
function hooksecurefunc() end
function Mixin(t) return t end
UISpecialFrames = {}; STANDARD_TEXT_FONT = "x"
RAID_CLASS_COLORS = { SHAMAN = { r = 0, g = 0.44, b = 0.87 } }
LOCALIZED_CLASS_NAMES_MALE = { SHAMAN = "Chamán" }
