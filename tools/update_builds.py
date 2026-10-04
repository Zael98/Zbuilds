"""Collects WoW Forever talent builds from several sites and writes ../Data.lua for the addon.

Run:  python update_builds.py
Then /reload in game.

Sources
  - talentsforever.com: talent trees (canonical layout, CC BY 4.0) and its "popular builds" list.
  - icy-veins.com: the talent builds embedded in its WoW Forever class guides.
  - links.txt: extra guides and build links shipped to everyone ("Guías extra").

Every build is translated into the talentsforever tree layout: per tree a list of ranks in the same
order as that tree's talents, plus the point order (list of [tree, talent] pairs, 1-based) when known.
"""

import html
import json
import re
import sys
import time
import urllib.request
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE.parent / "Data.lua"
LINKS = HERE / "links.txt"

USER_AGENT = "ForeverBuilds-updater/1.0 (personal WoW addon data refresh)"
REQUEST_DELAY = 1.0  # seconds between requests to the same site

TF = "https://talentsforever.com"
IV = "https://www.icy-veins.com"
IV_JSON = "https://static.icy-veins.com/json/forever-talent-calculator/"

# talentsforever build code format v6 (see its page source): one symbol per talent, flat across the trees.
TF_CODE_VERSION = 6
TF_SYMS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz056789"
# Icy Veins calculator: one character per invested point, in order; talents numbered across trees.
IV_SYMS = [str(i) for i in range(10)] + list("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-._~[]()")
IV_GRID_COLUMNS = 4

# Build types shown in the addon. Icy Veins says it in the guide URL; Talents Forever's popular list does not.
CATEGORIES = {"leveling": "Leveo", "leveo": "Leveo", "pve": "PvE", "pvp": "PvP"}

_last_request = {}


def fetch(url):
    host = url.split("/")[2]
    wait = REQUEST_DELAY - (time.time() - _last_request.get(host, 0))
    if wait > 0:
        time.sleep(wait)
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=30) as resp:
        body = resp.read().decode("utf-8", errors="replace")
    _last_request[host] = time.time()
    return body


def warn(msg):
    print("  ! " + msg, file=sys.stderr)


# ---------------------------------------------------------------- canonical trees (talentsforever)

class ClassTrees:
    def __init__(self, name, data):
        self.name = name                      # "Shaman"
        self.token = name.upper().replace(" ", "")  # "SHAMAN", matches UnitClass() file name
        self.trees = data["trees"]
        self.flat = [(ti, i) for ti, t in enumerate(self.trees) for i in range(len(t["talents"]))]
        self.by_pos = {}
        for ti, t in enumerate(self.trees):
            for i, tal in enumerate(t["talents"]):
                self.by_pos[(ti, tal["row"], tal["col"])] = i

    def empty_ranks(self):
        return [[0] * len(t["talents"]) for t in self.trees]

    def validate(self, ranks):
        for ti, t in enumerate(self.trees):
            for i, tal in enumerate(t["talents"]):
                if ranks[ti][i] > tal["max"]:
                    return f"{tal['name']} has {ranks[ti][i]} of {tal['max']} ranks"
        return None

    def to_lua(self):
        return {
            "trees": [
                {
                    "name": t["name"],
                    "icon": t.get("icon"),
                    "talents": [
                        {"name": x["name"], "row": x["row"], "col": x["col"], "max": x["max"], "icon": x.get("icon")}
                        for x in t["talents"]
                    ],
                }
                for t in self.trees
            ]
        }


def load_trees():
    data = json.loads(fetch(TF + "/data.json"))
    return {name: ClassTrees(name, c) for name, c in data["talents"].items()}


# ---------------------------------------------------------------- talentsforever build codes

def parse_tf_code(code, classes):
    """'shaman/60/050033-0510...--BEFR-6' -> (ClassTrees, level, ranks, order) or raises ValueError."""
    m = re.match(r"^/?([a-z ]+)/(\d+)/([0-9A-Za-z-]*)$", code.strip(), re.I)
    if not m:
        raise ValueError("not a talentsforever build code")
    cls = next((c for n, c in classes.items() if n.lower() == m.group(1).lower()), None)
    if not cls:
        raise ValueError(f"unknown class {m.group(1)}")
    level = min(60, max(10, int(m.group(2))))
    parts = m.group(3).split("-")
    nt = len(cls.trees)
    version = int(parts[-1]) if len(parts) > nt and parts[-1] in "23456" else 1
    if version != TF_CODE_VERSION:
        raise ValueError(f"code version {version} was written for older trees (only v{TF_CODE_VERSION} is read)")
    segs = parts[:-1]

    ranks = cls.empty_ranks()
    for ti, seg in enumerate(segs[:nt]):
        for i, ch in enumerate(seg):
            if i < len(ranks[ti]):
                ranks[ti][i] = min(int(ch), cls.trees[ti]["talents"][i]["max"])

    extra = segs[nt:]  # [legacy1, legacy2, legacy3, order] or [order]
    order_seg = extra[3] if len(extra) >= 4 else (extra[0] if len(extra) == 1 else "")
    order, taken, k = [], {}, 0
    while k < len(order_seg):
        f = TF_SYMS.find(order_seg[k])
        if f < 0 or f >= len(cls.flat):
            k += 1
            continue
        ti, i = cls.flat[f]
        n = ranks[ti][i] - taken.get((ti, i), 0)
        if k + 1 < len(order_seg) and order_seg[k + 1] in "1234":
            n = min(n, int(order_seg[k + 1]))
            k += 1
        order += [(ti, i)] * max(n, 0)
        taken[(ti, i)] = taken.get((ti, i), 0) + max(n, 0)
        k += 1
    return cls, level, ranks, order


def talentsforever_popular(classes):
    src = fetch(TF + "/popular.js")
    data = json.loads(src[src.index("{"): src.rindex("}") + 1])
    builds = []
    for cname, info in data["classes"].items():
        for entry in info.get("top", []):
            try:
                cls, level, ranks, order = parse_tf_code(entry["code"], classes)
            except ValueError as e:
                warn(f"talentsforever {cname} #{entry.get('rank')}: {e}")
                continue
            builds.append(make_build(
                cls, ranks, order, level,
                name=f"Popular #{entry['rank']}: {entry['lead']}",
                spec=entry["lead"], source="Talents Forever",
                url=f"{TF}/{entry['code']}",
            ))
    return builds


# ---------------------------------------------------------------- Icy Veins

def iv_class_map(slug, classes, cache={}):
    """Icy Veins point symbol -> (tree, talent index) in the canonical layout, checked by name."""
    if slug in cache:
        return cache[slug]
    data = json.loads(fetch(IV_JSON + slug + ".json"))
    cls = classes.get(data["class"])
    mapping = {}
    if not cls:
        warn(f"Icy Veins class {data['class']} has no talentsforever tree")
    else:
        sym = 0
        for ti, group in enumerate(data["talentGroups"]):
            for grid, tal in enumerate(group["talents"]):
                if not tal:
                    continue
                row, col = grid // IV_GRID_COLUMNS + 1, grid % IV_GRID_COLUMNS + 1
                i = cls.by_pos.get((ti, row, col))
                if i is None or cls.trees[ti]["talents"][i]["name"].lower() != tal["name"].lower():
                    warn(f"Icy Veins {data['class']}: {tal['name']} (tree {ti + 1}, row {row}, col {col}) "
                         "does not match talentsforever")
                else:
                    mapping[IV_SYMS[sym]] = (ti, i)
                sym += 1
    cache[slug] = (cls, mapping)
    return cache[slug]


def parse_iv_points(slug, points, classes):
    cls, mapping = iv_class_map(slug, classes)
    if not cls:
        raise ValueError("unknown class")
    ranks, order = cls.empty_ranks(), []
    for ch in points:
        if ch not in mapping:
            raise ValueError(f"point symbol {ch!r} has no matching talent")
        ti, i = mapping[ch]
        ranks[ti][i] += 1
        order.append((ti, i))
    return cls, ranks, order


TF_LINK = r'talentsforever\.com/(?P<tf>[a-z]+/\d+/[0-9A-Za-z-]+)'
IV_LINK = r'icy-veins\.com/wow-forever/(?P<ivc>[a-z-]+)-talent-calculator#tc-(?P<ivp>[0-9A-Za-z._~()\[\]-]+)'
PAGE_TOKENS = re.compile(
    r'<h[1-4][^>]*>(?P<h>.*?)</h[1-4]>'
    r'|<span id="area_(?P<tabid>\d+)_button">(?P<tab>.*?)</span>'  # Icy Veins tabs ("21-Point Tree")
    r'|id="area_(?P<area>\d+)"'
    r'|' + TF_LINK + r'|' + IV_LINK,
    re.S)


def link_build(url, classes):
    """A single build link -> (cls, level, ranks, order, canonical url), or None when it is not one."""
    m = re.search(TF_LINK, url)
    if m:
        cls, level, ranks, order = parse_tf_code(m.group("tf"), classes)
        return cls, level, ranks, order, f"{TF}/{m.group('tf')}"
    m = re.search(IV_LINK, url)
    if m:
        cls, ranks, order = parse_iv_points(m.group("ivc"), m.group("ivp"), classes)
        return cls, None, ranks, order, f"{IV}/wow-forever/{m.group('ivc')}-talent-calculator#tc-{m.group('ivp')}"
    return None


def page_builds(url, classes, source, category, spec=None, prefix=""):
    """Every talentsforever / Icy Veins build linked from a guide page, named after the heading above it."""
    page = fetch(url)
    builds, seen = [], set()
    heading, tabs, area = "", {}, None
    for m in PAGE_TOKENS.finditer(page):
        if m.group("h") is not None:
            heading, tabs, area = clean(m.group("h")), {}, None
        elif m.group("tab") is not None:
            tabs[m.group("tabid")] = clean(m.group("tab"))
        elif m.group("area"):
            area = m.group("area")
        else:
            name = prefix + (heading or "Build") + (f" ({tabs[area]})" if area in tabs else "")
            if m.group(0) in seen:
                continue
            seen.add(m.group(0))
            try:
                cls, level, ranks, order, link = link_build(html.unescape(m.group(0)), classes)
            except Exception as e:
                warn(f"{url} '{name}': {e}")
                continue
            builds.append(make_build(cls, ranks, order, level, name=name, spec=spec or lead_tree(cls, ranks),
                                     source=source, category=category, url=link, guide=url))
    return [b for b in builds if b]


def guide_category(url):
    m = re.search(r"-(pve|pvp|leveling)-guide", url)
    return CATEGORIES[m.group(1)] if m else None


def icy_veins_guides(classes):
    try:
        index = fetch(IV + "/wow-forever/")
        paths = sorted(set(re.findall(r'href="(/wow-forever/[a-z-]+-(?:pve|pvp|leveling)-guide)"', index)))
    except Exception as e:  # without the index, fall back to every guide read last time
        warn(f"Icy Veins index: {e}")
        paths = [k[3:] for k in cache_old if k.startswith("iv:")]
    builds = []
    for path in paths:
        builds += cached("iv:" + path, lambda: page_builds(
            IV + path, classes, "Icy Veins", guide_category(path), spec=guide_spec(path, "")))
    return builds


def guide_spec(path, title):
    # "/wow-forever/elemental-shaman-ranged-dps-pve-guide" -> "Elemental"
    words = path.rsplit("/", 1)[1].split("-")
    classes = {"warrior", "paladin", "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid"}
    spec = []
    for w in words:
        if w in classes:
            break
        spec.append(w.capitalize())
    return " ".join(spec) or clean(title)


def clean(fragment):
    return html.unescape(re.sub(r"<[^>]+>", "", fragment)).strip()


# ---------------------------------------------------------------- your own links

def custom_links(classes):
    if not LINKS.exists():
        return []
    builds = []
    for n, line in enumerate(LINKS.read_text(encoding="utf-8").splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        # "Nombre | enlace" or "Nombre | PvE | enlace"
        fields = [f.strip() for f in line.split("|")]
        name, url = fields[0] if len(fields) > 1 else "", fields[-1]
        category = guide_category(url)
        if len(fields) == 3:
            category = CATEGORIES.get(fields[1].lower())
            if not category:
                warn(f"links.txt line {n}: unknown type {fields[1]!r} (use Leveo, PvE or PvP)")

        def collect(name=name, url=url, category=category):
            single = link_build(url, classes)
            if single:  # a calculator link: one build
                cls, level, ranks, order, link = single
                return [b for b in [make_build(cls, ranks, order, level, name=name or "Mi build", spec=lead_tree(cls, ranks),
                                               source="Guías extra", url=link, category=category)] if b]
            # any other page is read as a guide: every build it links, fetched again on every run
            found = page_builds(url, classes, "Guías extra", category, prefix=f"{name}: " if name else "")
            if not found:
                raise ValueError("no talentsforever.com or Icy Veins build links on that page")
            return found

        builds += cached("link:" + url, collect)
    return builds


# ---------------------------------------------------------------- last good copy per source

CACHE = HERE / "cache.json"
cache_old = json.loads(CACHE.read_text(encoding="utf-8")) if CACHE.exists() else {}
cache_new = {}


def cached(key, produce):
    """produce() now, or, if the site fails, the builds it gave last time (so a bad day loses nothing)."""
    try:
        cache_new[key] = [b for b in produce() if b]
    except Exception as e:
        warn(f"{key}: {e}")
        if key in cache_old:
            warn(f"{key}: using the copy from the last successful run")
            cache_new[key] = cache_old[key]
    return cache_new.get(key, [])


# ---------------------------------------------------------------- output

def lead_tree(cls, ranks):
    pts = [sum(t) for t in ranks]
    return cls.trees[pts.index(max(pts))]["name"]


def make_build(cls, ranks, order, level, **fields):
    problem = cls.validate(ranks)
    if problem:
        # usually a code made against an older version of the site's tree: its symbols point at the wrong talents
        warn(f"{fields['source']} '{fields['name']}' skipped: {problem}")
        return None
    return {
        "class": cls.token,
        "ranks": ["".join(str(r) for r in t) for t in ranks],
        "points": [sum(t) for t in ranks],
        "order": [[ti + 1, i + 1] for ti, i in order] if order and sum(map(sum, ranks)) == len(order) else None,
        "level": level,
        **fields,
    }


def lua(value, indent=""):
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'
    inner = indent + "  "
    if isinstance(value, (list, tuple)):
        if all(isinstance(v, (int, float)) for v in value):
            return "{" + ", ".join(lua(v) for v in value) + "}"
        return "{\n" + "".join(f"{inner}{lua(v, inner)},\n" for v in value) + indent + "}"
    items = "".join(f"{inner}{k} = {lua(v, inner)},\n" for k, v in value.items() if v is not None)
    return "{\n" + items + indent + "}"


def main():
    print("Talent trees: talentsforever.com")
    classes = load_trees()
    builds = []
    for label, collect in (("Talents Forever popular builds", lambda c: cached("popular", lambda: talentsforever_popular(c))),
                           ("Icy Veins guides", icy_veins_guides),
                           ("links.txt", custom_links)):
        print(label)
        found = [b for b in collect(classes) if b]
        print(f"  {len(found)} builds")
        builds += found

    data = {
        "generated": datetime.now().strftime("%Y-%m-%d %H:%M"),
        "sources": [
            {"name": "Talents Forever", "url": TF, "note": "Talent data CC BY 4.0, talentsforever.com"},
            {"name": "Icy Veins", "url": IV + "/wow-forever/"},
        ],
        "classes": {c.token: c.to_lua() for c in classes.values()},
        "builds": builds,
    }
    CACHE.write_text(json.dumps(cache_new, ensure_ascii=False, indent=0), encoding="utf-8")
    content = ("-- Generated by tools/update_builds.py. Do not edit; run the script again instead.\n"
               "ForeverBuildsData = " + lua(data) + "\n")
    # rewrite only when a build or tree changed, so the timestamp alone never makes a new release
    old = OUT.read_text(encoding="utf-8") if OUT.exists() else ""
    stamp = re.compile(r'^  generated = ".*",$', re.M)
    if stamp.sub("", old) == stamp.sub("", content):
        print(f"No changes ({len(builds)} builds)")
        return
    OUT.write_text(content, encoding="utf-8")
    print(f"Wrote {len(builds)} builds to {OUT}")


if __name__ == "__main__":
    main()
