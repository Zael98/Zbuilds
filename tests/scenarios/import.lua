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
-- import + list + delete through the API
local d = ns.DecodeLink("https://talentsforever.com/shaman/60/050033-051032031005112251--BEFRSUVXYbcdefgh-6", "Prueba", "PvP")
ns.AddImport(d)
local found = 0 for _, b in ipairs(ns.BuildsFor("SHAMAN")) do if b == d then found = found + 1 end end
ns.RemoveImport(d)
local after = 0 for _, b in ipairs(ns.BuildsFor("SHAMAN")) do if b == d then after = after + 1 end end
return ("decoded identical: %d/%d\n%s\nimport listed %d, after delete %d, spec %s, category %s"):format(same, total, table.concat(failed, "\n"), found, after, d.spec, d.category)
