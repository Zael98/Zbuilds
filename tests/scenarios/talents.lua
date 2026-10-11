local cd = ns.ClassData("SHAMAN")
local tree, err = ns.ReadTree(cd)
assert(tree, err)
local mapped = 0
for t = 1, 3 do for i in ipairs(cd.trees[t].talents) do if tree.node[t][i] then mapped = mapped + 1 end end end
local out = { "mapped " .. mapped .. " mismatches: " .. table.concat(tree.mismatches, ",") }
-- every mapped node must be the talent of the same name
local wrong = {}
for t = 1, 3 do for i, tal in ipairs(cd.trees[t].talents) do
  local id = tree.node[t][i]; if id then
    local n = C_Traits.GetNodeInfo(1, id)
    if n.name ~= tal.name then wrong[#wrong+1] = tal.name .. "~=" .. n.name end
  end end end
out[#out+1] = "name mismatches: " .. table.concat(wrong, ", ")
local builds = ns.BuildsFor("SHAMAN")
out[#out+1] = "shaman builds: " .. #builds
local b = builds[#builds]
out[#out+1] = "using: " .. b.name
local t, i, r = ns.NextStep(b, cd, tree)
out[#out+1] = ("next: %s r%d"):format(cd.trees[t].talents[i].name, r)
local n, e = ns.Apply(b, cd)
out[#out+1] = "apply1: " .. tostring(n) .. " " .. tostring(e) .. " -> " .. table.concat(PURCHASED, ",")
FREE = 100; PURCHASED = {}
n, e = ns.Apply(b, cd)
out[#out+1] = "apply2: " .. tostring(n) .. " " .. tostring(e)
tree = ns.ReadTree(cd)
out[#out+1] = "next after full: " .. tostring(ns.NextStep(b, cd, tree))
-- conflict: another build
local other = builds[2]
n, e = ns.Apply(other, cd)
out[#out+1] = "conflict (" .. other.name .. "): " .. tostring(n) .. " " .. tostring(e)
-- derived order for a build without order
for _, x in ipairs(builds) do if x.source == "Talents Forever" then
  local o = ns.Order(x, cd); out[#out+1] = x.name .. " derived order len " .. #o .. " first " .. cd.trees[o[1][1]].talents[o[1][2]].name; break end end
return table.concat(out, "\n")
