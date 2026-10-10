"""Collects WoW Forever talent builds from several sites and writes ../Data.lua for the addon.

Run:  python update_builds.py
Then /reload in game.

Sources
  - talentsforever.com: talent trees (canonical layout, CC BY 4.0) and its "popular builds" list.
  - icy-veins.com: the talent builds embedded in its WoW Forever class guides.
  - warcrafttavern.com, method.gg, wowforeverbuilds.com: the builds in their WoW Forever guides
    (PvE, PvP and leveling; the type comes from the guide URL, heading or title).
  - links.txt: extra guides and build links shipped to everyone ("Guías extra").

Every build is translated into the talentsforever tree layout: per tree a list of ranks in the same
order as that tree's talents, plus the point order (list of [tree, talent] pairs, 1-based) when known.
"""

import html
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE.parent / "Data.lua"
LINKS = HERE / "links.txt"

USER_AGENT = "Zbuilds-updater/1.0 (personal WoW addon data refresh)"
REQUEST_DELAY = 1.0  # seconds between requests to the same site

TF = "https://talentsforever.com"
IV = "https://www.icy-veins.com"
IV_JSON = "https://static.icy-veins.com/json/forever-talent-calculator/"

# talentsforever build code format v6 (see its page source): one symbol per talent, flat across the trees.
TF_CODE_VERSION = 6
TF_SYMS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz056789"
# Icy Veins calculator: one character per invested point, in order; talents numbered across trees.
IV_SYMS = [str(i) for i in range(10)] + list("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-._~[]()")

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
        self.by_pos, self.by_name = {}, {}
        for ti, t in enumerate(self.trees):
            for i, tal in enumerate(t["talents"]):
                self.by_pos[(ti, tal["row"], tal["col"])] = i
                self.by_name[tal["name"].lower()] = (ti, i)

    def empty_ranks(self):
        return [[0] * len(t["talents"]) for t in self.trees]

    # Sites keep their own copy of the trees, and some lag a patch (talents moved, renamed or
    # reshaped by a hotfix), so their builds are read with their own tree and placed here by name.
    def resolve(self, name):
        spot = self.by_name.get(RENAMES.get(name, name).lower())
        if not spot:
            raise ValueError(f"{name} is not in the current {self.name} tree")
        return spot

    def from_points(self, names):
        """Talent names, one per point in the order they are learned -> (ranks, order)."""
        ranks, order = self.empty_ranks(), []
        for name in names:
            ti, i = self.resolve(name)
            ranks[ti][i] += 1
            order.append((ti, i))
        return ranks, order

    def from_ranks(self, ranks_by_name):
        ranks = self.empty_ranks()
        for name, rank in ranks_by_name.items():
            if rank:
                ti, i = self.resolve(name)
                ranks[ti][i] = rank
        return ranks

    def validate(self, ranks):
        """Why the build cannot be learned in the current trees, or None."""
        for ti, t in enumerate(self.trees):
            per_row = {}
            for i, tal in enumerate(t["talents"]):
                if ranks[ti][i] > tal["max"]:
                    return f"{tal['name']} has {ranks[ti][i]} of {tal['max']} ranks"
                per_row[tal["row"]] = per_row.get(tal["row"], 0) + ranks[ti][i]
            # row r opens after 5 * (r - 1) points in the rows above: a talent that moved rows breaks old builds
            for row, points in per_row.items():
                above = sum(p for r, p in per_row.items() if r < row)
                if points and above < 5 * (row - 1):
                    return f"{t['name']} row {row} needs {5 * (row - 1)} points above it, the build has {above}"
        return None

    def to_lua(self):
        return {
            "trees": [
                {
                    "name": t["name"],
                    "icon": t.get("icon"),
                    "talents": [
                        {"name": x["name"], "row": x["row"], "col": x["col"], "max": x["max"], "icon": x.get("icon"),
                         "spell": x.get("spell")}
                        for x in t["talents"]
                    ],
                }
                for t in self.trees
            ]
        }


RENAMES = {}  # old talent name -> current name, from talentsforever


TF_DATA = {}  # talentsforever's data.json, read once (talent trees, and the Legacy trees and challenges)


def load_trees():
    data = json.loads(fetch(TF + "/data.json"))
    TF_DATA.update(data)
    try:
        m = re.search(r"TALENT_RENAMES\s*=\s*(\{[^}]*\})", fetch(TF + "/talents.js"))
        RENAMES.update(json.loads(m.group(1)))
    except Exception as e:  # without it, builds naming an old talent are skipped instead
        warn(f"talent renames: {e}")
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

def iv_symbols(slug, cache={}):
    """Icy Veins point symbol -> talent name, from its own calculator data (talents numbered across trees)."""
    if slug not in cache:
        data = json.loads(fetch(IV_JSON + slug + ".json"))
        names = [tal["name"] for group in data["talentGroups"] for tal in group["talents"] if tal]
        cache[slug] = dict(zip(IV_SYMS, names))
    return cache[slug]


def parse_iv_points(slug, points, classes):
    cls, symbols = class_by_slug(slug, classes), iv_symbols(slug)
    if any(ch not in symbols for ch in points):
        raise ValueError("point symbol with no talent")
    ranks, order = cls.from_points(symbols[ch] for ch in points)
    return cls, ranks, order


# ---------------------------------------------------------------- Warcraft Tavern (warcraftdb calculator)

TAVERN = "https://www.warcrafttavern.com"
TAVERN_TREES = "ABC"


def tavern_tree(slug, cache={}):
    """(tree, tier, column) -> talent name in warcraftdb's own copy of the trees (0-based grid)."""
    if slug not in cache:
        data = json.loads(fetch(f"https://forever.warcraftdb.com/api/v1/talents/{slug}"))
        cache[slug] = {(ti, t["tier"], t["column"]): t["name"]
                       for ti, tree in enumerate(data["trees"]) for t in tree["talents"]}
    return cache[slug]


def parse_tavern_points(slug, code, classes):
    """'A1111004466b': a tree letter, then one symbol per point, in order: tier*4 + column in base 36."""
    cls, grid = class_by_slug(slug, classes), tavern_tree(slug)
    names, tree = [], None
    for ch in code:
        if ch in TAVERN_TREES:
            tree = TAVERN_TREES.index(ch)
            continue
        value = int(ch, 36)
        name = grid.get((tree, value // 4, value % 4))
        if not name:
            raise ValueError(f"point {ch!r} has no talent in tree {tree}")
        names.append(name)
    ranks, order = cls.from_points(names)
    return cls, ranks, order


# ---------------------------------------------------------------- WoW Forever Builds (wowforeverbuilds.com)

WFB = "https://wowforeverbuilds.com"


def wfb_tree(slug, cache={}):
    """Talent names per tree, in the order of wowforeverbuilds' own calculator (embedded in its page)."""
    if slug not in cache:
        page = html.unescape(fetch(f"{WFB}/talents/{slug}"))
        cache[slug] = [re.findall(r'"name":\[0,"([^"]+)"\],"icon":\[0,"[^"]*"\],"row":', part)
                       for part in page.split('"talents":[1,[')[1:]]
    return cache[slug]


def parse_wfb_query(slug, query, classes):
    """'b=-0355...-2030...&o=2222...': b = rank per talent, one block per tree; o = point order,
    two characters per point (tree index, talent index in base 36)."""
    cls, trees = class_by_slug(slug, classes), wfb_tree(slug)
    params = urllib.parse.parse_qs(query)
    ranks_by_name = {}
    for ti, seg in enumerate(params.get("b", [""])[0].split("-")[:len(trees)]):
        for i, ch in enumerate(seg):
            if int(ch):
                ranks_by_name[trees[ti][i]] = int(ch)
    code = params.get("o", [""])[0]
    names = [trees[int(code[k])][int(code[k + 1], 36)] for k in range(0, len(code) - 1, 2)]
    if names and len(names) == sum(ranks_by_name.values()):
        ranks, order = cls.from_points(names)
    else:
        ranks, order = cls.from_ranks(ranks_by_name), []
    return cls, ranks, order


# ---------------------------------------------------------------- Method (Blizzard-style export string)

METHOD = "https://www.method.gg"
B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
TREE_ORIGIN_X, TREE_ORIGIN_Y, NODE_SPACING = (1020, 5020, 9080), 2130, 600  # same grid the game uses
_method_data = {}


def method_data():
    """Method's copy of the game's talent data (node positions, ranks, spell ids), read once."""
    if "data" not in _method_data:
        script = re.search(r'ForeverTalents\.min\.js\?version=([\d.]+)', fetch(METHOD + "/wow-forever/talent-calculator"))
        _method_data["data"] = json.loads(fetch(f"{METHOD}/dfc/ForeverTalentsData-{script.group(1)}.json"))
    return _method_data["data"]


def method_nodes(class_token):
    """Method's node list for a class, sorted by node id as its codes are: [(node id, tree, row, col, max)]."""
    data = method_data()
    nodes = []
    for tab in data["classes"][class_token]["tabs"]:
        for node_id, n in data[tab["treeID"]].items():
            if n["curFlag"] == tab["curFlag"] and n["spells"]:
                nodes.append((int(node_id), tab["order"], round((n["y"] - TREE_ORIGIN_Y) / NODE_SPACING) + 1,
                              round((n["x"] - TREE_ORIGIN_X[tab["order"]]) / NODE_SPACING) + 1, n["maxRank"]))
    return sorted(nodes)


def method_spells(classes):
    """[class, tree, index, spell id] for every talent whose Method node sits at the same place,
    with the same ranks and icon (so a node a hotfix moved never lends its spell to another talent)."""
    out = []
    for cls in classes.values():
        data = method_data()
        for tab in data["classes"][cls.token]["tabs"]:
            for n in data[tab["treeID"]].values():
                if n["curFlag"] != tab["curFlag"] or not n["spells"]:
                    continue
                t = tab["order"]
                i = cls.by_pos.get((t, round((n["y"] - TREE_ORIGIN_Y) / NODE_SPACING) + 1,
                                    round((n["x"] - TREE_ORIGIN_X[t]) / NODE_SPACING) + 1))
                spell = sorted(n["spells"], key=lambda sp: sp.get("index", 0))[0]
                tal = i is not None and cls.trees[t]["talents"][i]
                if tal and tal["max"] == n["maxRank"] and spell["icon"].rsplit(".", 1)[0].lower() == (tal.get("icon") or "").lower():
                    out.append([cls.token, t, i, spell["spellID"]])
    return out


METHOD_CLASS_IDS = {1: "WARRIOR", 2: "PALADIN", 4: "HUNTER", 8: "ROGUE", 16: "PRIEST", 64: "SHAMAN",
                    128: "MAGE", 256: "WARLOCK", 1024: "DRUID"}


def parse_method(code, classes):
    """'<export>;<leveling>': the export is a bit stream (6 bits per character, low bits first):
    version 8, class 16, tree hash 16x8, then per node: selected 1 [purchased 1 [partial 1 [rank 6]] choice 1 [2]].
    The leveling part is one character per point: the index of the node in id order."""
    export, _, leveling = code.partition(";")
    bits = [(B64.index(ch) >> b) & 1 for ch in export for b in range(6)]
    pos = 0

    def read(n):
        nonlocal pos
        if pos + n > len(bits):
            raise ValueError("export string too short")
        value = sum(bits[pos + k] << k for k in range(n))
        pos += n
        return value

    if read(8) != 1:
        raise ValueError("unknown Method export version")
    token = METHOD_CLASS_IDS.get(read(16))
    cls = next((c for c in classes.values() if c.token == token), None)
    if not cls:
        raise ValueError(f"unknown class in Method export: {token}")
    read(16 * 8)

    nodes = method_nodes(token)
    ranks, at = cls.empty_ranks(), []
    for _, tree, row, col, max_rank in nodes:
        i = cls.by_pos.get((tree, row, col))
        at.append((tree, i))
        if not read(1):  # not selected
            continue
        purchased = read(1)
        rank = max_rank if purchased else 1
        if purchased:
            if read(1):  # partial rank
                rank = read(6)
            if read(1):  # choice node
                read(2)
        if i is None or cls.trees[tree]["talents"][i]["max"] != max_rank:
            raise ValueError(f"Method talent at tree {tree} row {row} col {col} differs from the current tree")
        ranks[tree][i] = min(rank, max_rank)

    order = []
    for ch in leveling:
        tree, i = at[B64.index(ch)]
        if i is None:
            raise ValueError("leveling order points at an unknown talent")
        order.append((tree, i))
    return cls, ranks, order


# ---------------------------------------------------------------- Legacy (account-wide perk trees)
# Trees and challenges come from talentsforever (CC BY 4.0). No site publishes Legacy builds yet, so the
# plans are made here from wowforeverbuilds' perks grouped by goal: each goal's perks, in the site's
# order, get the 16 points, with the points each perk needs in its tree first and the perk it requires.

LEGACY_POINTS = 16


def slug(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def legacy_goals():
    """[(goal, [perk slug, ...])] from wowforeverbuilds' Legacy builds page, in the page's order."""
    page = html.unescape(fetch(WFB + "/legacy/builds"))
    start = page.find("Perks by goal")
    if start < 0:
        raise ValueError("no 'Perks by goal' section")
    page = page[start:]
    heads = [(m.start(), clean(m.group(1))) for m in re.finditer(r"<h3[^>]*>(.*?)</h3>", page, re.S)]
    goals = []
    for k, (at, name) in enumerate(heads):
        end = heads[k + 1][0] if k + 1 < len(heads) else len(page)
        perks = []
        for perk in re.findall(r'href="/legacy/tree/[a-z]+#([a-z0-9-]+)"', page[at:end]):
            if perk not in perks:
                perks.append(perk)
        if perks:
            goals.append((name, perks))
    return goals


def legacy_plan(trees, wanted):
    """Ranks and point order (16 points at most) for a goal: wanted is a list of (tree, perk) indexes."""
    ranks = [[0] * len(t["perks"]) for t in trees]
    order, left = [], [LEGACY_POINTS]

    def in_tree(t):
        return sum(ranks[t])

    def buy(t, i, n):
        while n > 0 and left[0] > 0 and ranks[t][i] < trees[t]["perks"][i]["max"]:
            ranks[t][i] += 1
            order.append([t + 1, i + 1])
            left[0] -= 1
            n -= 1

    def ready(t, i):
        perk = trees[t]["perks"][i]
        req = perk.get("req")
        return in_tree(t) >= perk["gate"] and (req is None or ranks[t][req] >= trees[t]["perks"][req]["max"])

    def unlock(t, i):
        """Spends what perk i needs first: its required perk maxed, then points in its tree up to its gate."""
        perk = trees[t]["perks"][i]
        req = perk.get("req")
        if req is not None and ranks[t][req] < trees[t]["perks"][req]["max"]:
            if not unlock(t, req):
                return False
            buy(t, req, trees[t]["perks"][req]["max"])
            if ranks[t][req] < trees[t]["perks"][req]["max"]:
                return False
        while in_tree(t) < perk["gate"]:
            # fill the gate with the goal's own perks of that tree first, then any open perk of the tree
            mine = [j for tt, j in wanted if tt == t and j != i]
            others = [j for j in range(len(trees[t]["perks"])) if j != i and j not in mine]
            filler = next((j for j in mine + others
                           if ranks[t][j] < trees[t]["perks"][j]["max"] and ready(t, j)), None)
            if filler is None or left[0] == 0:
                return False
            buy(t, filler, 1)
        return True

    for t, i in wanted:
        if left[0] == 0:
            break
        saved = ([r[:] for r in ranks], order[:], left[0])
        if unlock(t, i) and ready(t, i) and left[0] > 0:  # at least one rank of the perk itself
            buy(t, i, trees[t]["perks"][i]["max"])
        else:  # it does not fit: undo whatever the attempt spent
            ranks[:], order[:], left[0] = saved[0], saved[1], saved[2]
    return ranks, order


def legacy_data():
    raw = TF_DATA["legacy"]
    trees = []
    for tree in sorted(raw["trees"], key=lambda tr: tr["id"]):
        perks = [p for p in tree["perks"] if not p.get("placeholder")]
        index = {p["name"]: k for k, p in enumerate(perks)}
        trees.append({
            "id": tree["id"], "name": tree["name"], "icon": tree.get("icon"),
            "perks": [{"name": p["name"], "max": p["max"], "row": p["row"], "col": p["col"], "icon": p.get("icon"),
                       "gate": p.get("gate", 0), "req": index.get(p.get("req")),
                       "desc": (p.get("ranks") or [None])[-1]} for p in perks],
        })
    by_slug = {slug(p["name"]): (t, i) for t, tree in enumerate(trees) for i, p in enumerate(tree["perks"])}

    plans = []
    for goal, slugs in legacy_goals():
        wanted = [by_slug[s] for s in slugs if s in by_slug]
        missing = [s for s in slugs if s not in by_slug]
        if missing:
            warn(f"Legacy goal '{goal}': perks not in the trees: {missing}")
        ranks, order = legacy_plan(trees, wanted)
        plans.append({"name": goal, "source": "WoW Forever Builds", "url": f"{WFB}/legacy/builds",
                      "ranks": ["".join(str(r) for r in t) for t in ranks], "points": [sum(t) for t in ranks],
                      "order": order})

    for tree in trees:  # the game's Lua tables are 1-based
        for perk in tree["perks"]:
            perk["req"] = perk["req"] + 1 if perk["req"] is not None else None
    return {"points": LEGACY_POINTS, "trees": trees, "plans": plans,
            "challenges": [{"group": c["group"], "name": c["name"], "desc": c["desc"]} for c in raw["challenges"]]}


# ---------------------------------------------------------------- trainer spells
# Every spell rank a class trainer sells, with the level it is learned at and its spell id (talentsforever:
# nt marks the ranks the trainer does not sell: talents, tomes, quests), and its training cost in copper from
# Wowhead's Forever class abilities list (the base price; the addon prefers what it reads at the trainer).

def trainer_costs(cls):
    page = fetch(f"https://www.wowhead.com/forever/spells/abilities/{cls.lower()}")
    return {int(i): int(c) for i, c in re.findall(r'\{"cat":[^{}]*?"id":(\d+)[^{}]*?"trainingcost":(\d+)', page)}


def trainer_data():
    out = {}
    for key, v in TF_DATA["spell_desc"].items():
        cls, spell, rank = key.split("|", 2)
        level = re.search(r"(\d+)", v.get("lv") or "") if isinstance(v, dict) else None
        if not level or v.get("nt") or not v.get("id"):
            continue
        number = re.match(r"Rank (\d+)", rank)
        out.setdefault(cls.upper().replace(" ", ""), []).append(
            {"id": v["id"], "name": spell, "rank": int(number.group(1)) if number else 1, "level": int(level.group(1))})
    for cls, spells in out.items():
        spells.sort(key=lambda sp: (sp["level"], sp["name"], sp["rank"]))
        cost = trainer_costs(cls)
        priced = 0
        for sp in spells:
            if sp["id"] in cost:
                sp["cost"] = cost[sp["id"]]
                priced += 1
        print(f"  trainer {cls}: {len(spells)} ranks, {priced} with a cost")
    return out


# ---------------------------------------------------------------- decoders shipped to the game
# The in-game "Import link" reads links offline, so it gets each site's symbols already placed in our
# trees (by talent name, like the updater does): "symbol" -> {tree, index}, 1-based.

def link_decoders(classes):
    out = {"iv": {}, "tavern": {}, "wfb": {}}
    for cls in classes.values():
        slug = cls.name.lower()

        def spot(name):
            try:
                ti, i = cls.resolve(name)
                return [ti + 1, i + 1]
            except ValueError:
                return None  # a talent the current tree no longer has: links using it are refused

        out["iv"][cls.token] = {sym: spot(name) for sym, name in iv_symbols(slug).items() if spot(name)}
        out["tavern"][cls.token] = {TAVERN_TREES[t] + int_to36(tier * 4 + col): spot(name)
                                    for (t, tier, col), name in tavern_tree(slug).items() if spot(name)}
        out["wfb"][cls.token] = {f"{t}:{i}": spot(name) for t, names in enumerate(wfb_tree(slug))
                                 for i, name in enumerate(names) if spot(name)}
    return out


def int_to36(value):
    return "0123456789abcdefghijklmnopqrstuvwxyz"[value]


# ---------------------------------------------------------------- reading guide pages

TF_LINK = r'talentsforever\.com/(?P<tf>[a-z]+/\d+/[0-9A-Za-z-]+)'
IV_LINK = r'icy-veins\.com/wow-forever/(?P<ivc>[a-z-]+)-talent-calculator#tc-(?P<ivp>[0-9A-Za-z._~()\[\]-]+)'
TAVERN_LINK = r'/forever/tools/talent-calculator/(?P<tvc>[a-z]+)#\?t=(?P<tvp>[A-C][0-9a-zA-C]*)'
WFB_LINK = r'/talents/(?P<wfc>[a-z]+)\?(?P<wfq>b=[^"\'<\s]+)'
METHOD_EMBED = r'data-talent="(?P<mt>[A-Za-z0-9+/]+(?:;[A-Za-z0-9+/]*)?)"'
PAGE_TOKENS = re.compile(
    r'<h[1-4][^>]*>(?P<h>.*?)</h[1-4]>'
    r'|<span id="area_(?P<tabid>\d+)_button">(?P<tab>.*?)</span>'  # Icy Veins tabs ("21-Point Tree")
    r'|id="area_(?P<area>\d+)"'
    r'|' + '|'.join((TF_LINK, IV_LINK, TAVERN_LINK, WFB_LINK, METHOD_EMBED)),
    re.S)


def class_by_slug(slug, classes):
    cls = next((c for n, c in classes.items() if n.lower() == slug.lower()), None)
    if not cls:
        raise ValueError(f"unknown class {slug}")
    return cls


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
    m = re.search(TAVERN_LINK, url)
    if m:
        cls, ranks, order = parse_tavern_points(m.group("tvc"), m.group("tvp"), classes)
        return cls, None, ranks, order, f"{TAVERN}/forever/tools/talent-calculator/{m.group('tvc')}#?t={m.group('tvp')}"
    m = re.search(WFB_LINK, url)
    if m:
        cls, ranks, order = parse_wfb_query(m.group("wfc"), m.group("wfq"), classes)
        return cls, None, ranks, order, f"{WFB}/talents/{m.group('wfc')}?{m.group('wfq')}"
    return None


def heading_category(text):
    """Build type from a heading or title; None when it does not say."""
    text = text.lower()
    if "pvp" in text:
        return "PvP"
    if re.search(r"\b(leveling|levelling|leveo|solo|questing)\b", text):
        return "Leveo"
    if re.search(r"\b(pve|dungeon|raid|raiding|endgame)\b", text):
        return "PvE"
    return None


def page_builds(url, classes, source, category, spec=None, prefix="", title_name=False):
    """Every build linked or embedded in a guide page, named after the heading above it (or the page title).
    Without a fixed category, each build takes the type its heading or the page title mentions.
    With title_name, the page is about one build: the one whose points per tree match the
    "N pts" the page shows. Other builds it links (the rest of a group in a duo or 5-man guide)
    have pages of their own and are left out here."""
    page = fetch(url)
    title = clean((re.search(r"<h1[^>]*>(.*?)</h1>", page, re.S) or re.search(r"<title>(.*?)</title>", page, re.S)).group(1))
    shown = [int(p) for p in re.findall(r'>(\d+) pts<', page)[:3]]
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
            name = prefix + ((title if title_name else heading) or "Build") + (f" ({tabs[area]})" if area in tabs else "")
            if m.group(0) in seen:
                continue
            seen.add(m.group(0))
            try:
                if m.group("mt"):  # embedded tree with no link of its own: point at the guide
                    cls, ranks, order = parse_method(m.group("mt"), classes)
                    level, link = None, f"{url}#zb{len(builds) + 1}"
                else:
                    cls, level, ranks, order, link = link_build(html.unescape(m.group(0)), classes)
            except Exception as e:
                warn(f"{url} '{name}': {e}")
                continue
            if title_name and [sum(t) for t in ranks] != shown:
                continue
            builds.append(make_build(cls, ranks, order, level, name=name, spec=spec or lead_tree(cls, ranks),
                                     source=source, url=link, guide=url,
                                     category=category or heading_category(name) or heading_category(title)
                                     or heading_category(url.rsplit("/", 1)[-1].replace("-", " "))))
    return [b for b in builds if b]


def guide_category(url):
    m = re.search(r"-(pve|pvp|leveling)-guide", url)
    return CATEGORIES[m.group(1)] if m else None


# ---------------------------------------------------------------- site crawlers (one cache entry per page)

def crawl(source, key, classes, base, paths=(), index_urls=(), link_pattern=None, **options):
    """Read each guide page (given, or listed by the index pages); when the indexes fail,
    fall back to the pages read last time. One cache entry per page."""
    paths = list(paths)
    for index_url in index_urls:
        try:
            paths += re.findall(link_pattern, fetch(index_url))
        except Exception as e:
            warn(f"{source} index {index_url}: {e}")
    paths = sorted(set(paths)) or [k[len(key) + 1:] for k in cache_old if k.startswith(key + ":")]
    builds = []
    for path in paths:
        builds += cached(f"{key}:{path}", lambda: page_builds(base + path, classes, source, None, **options))
    return builds


def tavern_guides(classes):
    # one guide per class, with every build of the class in it
    return crawl("Warcraft Tavern", "tavern", classes, TAVERN,
                 paths=[f"/forever/guides/{name.lower()}/" for name in classes])


def method_guides(classes):
    return crawl("Method", "method", classes, METHOD,
                 index_urls=[f"{METHOD}/wow-forever", f"{METHOD}/wow-forever/leveling-guides"],
                 link_pattern=r'href="(?:https://www\.method\.gg)?(/wow-forever/[a-z0-9-]*guide[a-z0-9-]*)"')


def wfb_guides(classes):
    return crawl("WoW Forever Builds", "wfb", classes, WFB,
                 index_urls=[f"{WFB}/guides/{name.lower()}" for name in classes],
                 link_pattern=r'href="(/guide/[a-z0-9-]+)"', title_name=True)


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


PROBLEMS_FILE = HERE / "problems.txt"
problems = []  # what failed this run; the GitHub workflow turns a non-empty list into an issue


def cached(key, produce):
    """produce() now, or, if the site fails, the builds it gave last time (so a bad day loses nothing)."""
    try:
        found = [b for b in produce() if b]
        if not found and cache_old.get(key):
            raise ValueError(f"no builds now, {len(cache_old[key])} last time (the site may have changed)")
        cache_new[key] = found
    except Exception as e:
        warn(f"{key}: {e}")
        if key in cache_old:
            warn(f"{key}: using the copy from the last successful run")
            cache_new[key] = cache_old[key]
            problems.append(f"{key}: {e} (kept the copy from the last good run)")
        else:
            problems.append(f"{key}: {e}")
    return cache_new.get(key, [])


# ---------------------------------------------------------------- output

def lead_tree(cls, ranks):
    pts = [sum(t) for t in ranks]
    return cls.trees[pts.index(max(pts))]["name"]


BETA_POINTS = 21  # the beta stops at level 30: builds this small, or that say "beta", are for it


def make_build(cls, ranks, order, level, **fields):
    problem = cls.validate(ranks)
    if problem:
        # usually a code made against an older version of the site's tree: its symbols point at the wrong talents
        warn(f"{fields['source']} '{fields['name']}' skipped: {problem}")
        return None
    total = sum(map(sum, ranks))
    return {
        "class": cls.token,
        "ranks": ["".join(str(r) for r in t) for t in ranks],
        "points": [sum(t) for t in ranks],
        "order": [[ti + 1, i + 1] for ti, i in order] if order and total == len(order) else None,
        "level": level,
        "beta": True if total <= BETA_POINTS or "beta" in fields["name"].lower() else None,
        **fields,
    }


def merge_duplicates(builds):
    """Builds with the same talents become one, recommended by every site that has it.
    The first one found (sources run in a fixed order) leads; the others are listed in "also"."""
    merged, by_key = [], {}
    for b in builds:
        key = (b["class"], tuple(b["ranks"]))
        first = by_key.get(key)
        if not first:
            by_key[key] = b
            merged.append(b)
            continue
        first.setdefault("also", []).append({k: b.get(k) for k in ("source", "name", "url", "guide")})
        first["order"] = first["order"] or b["order"]
        first["category"] = first.get("category") or b.get("category")
        first["beta"] = first["beta"] and b["beta"]
    return merged


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
    def key(k):
        return k if isinstance(k, str) and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", k) else f"[{lua(k)}]"
    items = "".join(f"{inner}{key(k)} = {lua(v, inner)},\n" for k, v in value.items() if v is not None)
    return "{\n" + items + indent + "}"


def main():
    print("Talent trees: talentsforever.com")
    classes = load_trees()
    builds = []
    for label, collect in (("Talents Forever popular builds", lambda c: cached("popular", lambda: talentsforever_popular(c))),
                           ("Icy Veins guides", icy_veins_guides),
                           ("Warcraft Tavern guides", tavern_guides),
                           ("Method guides", method_guides),
                           ("WoW Forever Builds guides", wfb_guides),
                           ("links.txt", custom_links)):
        print(label)
        found = [b for b in collect(classes) if b]
        print(f"  {len(found)} builds")
        if not found and label != "links.txt":
            problems.append(f"{label}: no builds at all (the site may have changed)")
        builds += found

    for token, t, i, spell in cached("spells", lambda: method_spells(classes)):
        next(c for c in classes.values() if c.token == token).trees[t]["talents"][i]["spell"] = spell
    decoders = cached("decoders", lambda: [link_decoders(classes)])
    legacy = cached("legacy", lambda: [legacy_data()])
    trainer = cached("trainer", lambda: [trainer_data()])
    builds = merge_duplicates([dict(b) for b in builds])  # copies: the cache keeps each site's own builds
    PROBLEMS_FILE.write_text("\n".join(problems), encoding="utf-8")

    data = {
        "generated": datetime.now().strftime("%Y-%m-%d %H:%M"),
        "sources": [
            {"name": "Talents Forever", "url": TF, "note": "Talent data CC BY 4.0, talentsforever.com"},
            {"name": "Icy Veins", "url": IV + "/wow-forever/"},
            {"name": "Warcraft Tavern", "url": TAVERN + "/forever/guides/"},
            {"name": "Method", "url": METHOD + "/wow-forever"},
            {"name": "WoW Forever Builds", "url": WFB},
        ],
        "classes": {c.token: c.to_lua() for c in classes.values()},
        "builds": builds,
        "decoders": decoders[0] if decoders else {},
        "legacy": legacy[0] if legacy else None,
        "trainer": trainer[0] if trainer else None,
    }
    CACHE.write_text(json.dumps(cache_new, ensure_ascii=False, indent=0), encoding="utf-8")
    content = ("-- Generated by tools/update_builds.py. Do not edit; run the script again instead.\n"
               "ZbuildsData = " + lua(data) + "\n")
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
