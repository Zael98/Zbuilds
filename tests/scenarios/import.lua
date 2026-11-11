local total, same, failed = 0, 0, {}
local function ord(o) if not o then return "" end local x = {} for _, s in ipairs(o) do x[#x+1] = s[1] .. ":" .. s[2] end return table.concat(x, ",") end
local function check(b, url, label, compareOrder)
  if url:find("#zb") then return end -- Method builds have no link of their own
  if url:find("rankedboost%.com") or url:find("wowforevertalent%.com") then return end -- build pages, not calculator links
  total = total + 1
  local d, err = ns.DecodeLink(url, b.name, b.category)
  if not d then failed[#failed+1] = label .. ": " .. err return end
  local ok = d.class == b.class
  for t = 1, #b.ranks do ok = ok and d.ranks[t] == b.ranks[t] end
  if compareOrder and d.order and b.order then ok = ok and ord(d.order) == ord(b.order) end
  if ok then same = same + 1 else failed[#failed+1] = "MISMATCH " .. label .. " " .. url end
end
for _, b in ipairs(ZbuildsData.builds) do
  check(b, b.url, b.source .. " " .. b.name, true)
  for _, other in ipairs(b.also or {}) do check(b, other.url, "also " .. other.source .. " " .. other.name, false) end
end
local bad = { "https://example.com/x", "https://talentsforever.com/shaman/60/050033-0510-2", "https://www.icy-veins.com/wow-forever/druid-talent-calculator#tc-zzzzzzz" }
for _, u in ipairs(bad) do local d, e = ns.DecodeLink(u) failed[#failed+1] = "expected error: " .. tostring(e) end
-- import + list + delete through the API, with the first link of the data that decodes: a fixed link stops fitting
-- when a game patch changes its class tree (as build 1.60.1.70753 did to the shaman's)
local link
for _, b in ipairs(ZbuildsData.builds) do
  if not link and ns.DecodeLink(b.url) then link = b.url end
end
local d = assert(link and ns.DecodeLink(link, "Prueba", "PvP"), "no build of the data has a link that decodes")
-- Icy Veins links end in "~<data version>" since 2026-11: the same build as without it
local suffix = "no Icy Veins link"
for _, b in ipairs(ZbuildsData.builds) do
  local base = b.url:find("#tc%-") and b.url:gsub("~%d+%-%x+$", "")
  local plain = base and ns.DecodeLink(base)
  if plain and suffix == "no Icy Veins link" then
    local versioned = ns.DecodeLink(base .. "~70888-0650090c")
    local same = versioned ~= nil and versioned.class == plain.class
    for t = 1, #plain.ranks do same = same and versioned.ranks[t] == plain.ranks[t] end
    suffix = tostring(same)
  end
end
ns.AddImport(d)
local found = 0 for _, b in ipairs(ns.BuildsFor(d.class)) do if b == d then found = found + 1 end end
ns.RemoveImport(d)
local after = 0 for _, b in ipairs(ns.BuildsFor(d.class)) do if b == d then after = after + 1 end end
return ("decoded identical: %d/%d\n%s\nimport listed %d, after delete %d, spec %s, category %s\nversion suffix same: %s"):format(same, total, table.concat(failed, "\n"), found, after, d.spec, d.category, suffix)
