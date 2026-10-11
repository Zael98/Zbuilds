"""Zbuilds tests: loads the addon in Lua 5.1 (lupa) with stubs of the WoW API and runs each scenario in
tests/scenarios, checking its output. Run before every release: python tests/run.py (pip install lupa).
Exit code 1 when anything fails, so the workflow does not publish."""
import re
import sys
from pathlib import Path

from lupa import lua51

ROOT = Path(__file__).resolve().parent.parent
TESTS = Path(__file__).resolve().parent
LOCALES = ["enUS", "esES", "esMX", "deDE", "frFR", "ptBR", "itIT", "ruRU", "koKR", "zhCN", "zhTW"]

# what each scenario must print; the ones marked all run in every language
CHECKS = {
    "talents": (False, [r"name mismatches: $", r"apply2: \d+ nil", r"next after full: nil", r"derived order len 51"]),
    "import": (False, [r"decoded identical: (\d+)/\1$", r"import listed 1, after delete 0"]),
    "window": (False, [r"edges: \d+", r"dialog error: \S", r"after import: Mi elemental", r"imports 0"]),
    "launchers": (False, [r"Talent tree: 50/50 talents found", r"compartment fn: function", r"beta filter: rows \d+ -> \d+"]),
    "legacy_dump": (False, [r"legacy found by 'type 3'", r"/zbuildslegacydump prints 6 lines"]),
    "legacy_tab": (True, [r"by position: 21/21", r"hide done -> rows 65", r"A\) Forever: legacy window 62006, links in chat 0",
                          r"back to talents: talents shown=true legacy shown=false",
                          r"legacy banner: .+ \| Novice Shaman \| .*Well Rested", r"other achievement: banner shown false",
                          r"legacy alert off: banner shown false", r"options tab: options shown=true legacy shown=false",
                          r"toggles: banner=true sound=true talentAlert=true legacyAlert=true chat=true minimap=true",
                          r"after clicks: sound option false check false \| minimap shown false check false",
                          r"duration cycle: 10,15,4,6 \| label .*6", r"/zb options: options shown=true"]),
    "loadouts": (True, [r"entry type now table", r"after rename: window title 'Mi Elemental'"]),
    "timeline": (True, [r"timeline steps shown: 51", r"card points sum 20"]),
    "trainer": (True, [r"before the trainer: .+Searing Totem", r"train button: true",
                       r"train all: (?!.*Earth Shock 2).+", r"bought from the bottom up: true", r"shift: .*Earth Shock 2",
                       r"no gold: bought 0", r"banner: .+ \| .*12.* \| .*Convection", r"icons [1-9]\d* \| sounds [1-9]",
                       r"talent only: .+ \| .*12.* \| .*Convection", r"banner off: shown false", r"game banner on screen: ours shown false",
                       r"game banner gone: ours shown true", r"game banner never leaves: ours shown true",
                       r"sound off: new sounds 0 \| chat off: new lines [01] ", r"talent off: (?!.*Convection)",
                       r"after learning Earth Shock 3: (?!Earth Shock 2)", r"trainertest banner: .+Searing",
                       r"hunter: .*Bite.*3", r"warlock: .*Firebolt.*2", r"rogue without poisons: 0",
                       r"rogue with Instant Poison 1: .*Instant Poison 2",
                       r"by name and rank: [1-9]\d* costs", r"empty trainer: new messages 0 \| train button enabled false"]),
}


def read(path):
    return Path(path).read_text(encoding="utf-8")


def addon_files():
    toc = read(ROOT / "Zbuilds.toc").splitlines()
    return [line.strip() for line in toc if line.strip().endswith(".lua")]


def runtime(locale):
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    L.globals().LOCALE = locale
    L.execute(read(TESTS / "fixtures" / "probe.lua"))
    L.execute(read(ROOT / "Data.lua"))
    L.execute(read(TESTS / "stubs.lua"))
    L.execute(read(TESTS / "fixtures" / "legacy_dump.lua"))
    L.execute("print = function() end")  # the chat; scenarios that read it replace it
    ns = L.eval("{}")
    load = L.eval("function(src, name, ns) local f, e = loadstring(src, name); if not f then error(e) end f('Zbuilds', ns) end")
    for name in addon_files():
        if name != "Data.lua":
            load(read(ROOT / name), name, ns)
    L.globals().ns = ns
    return L


def syntax():
    """Every file of the toc compiles."""
    L = lua51.LuaRuntime()
    check = L.eval("function(src, name) local f, e = loadstring(src, name) return e end")
    return [f"{name}: {err}" for name in addon_files() if (err := check(read(ROOT / name), name))]


def formats():
    """Every text has the same %d/%s placeholders, in the same order, in every language."""
    L = lua51.LuaRuntime()
    src = read(ROOT / "Locales.lua")
    texts = {}
    for locale in LOCALES:
        L.execute(f"GetLocale = function() return '{locale}' end")
        ns = L.eval("{}")
        L.eval("function(src, ns) assert(loadstring(src))('Zbuilds', ns) end")(src, ns)
        texts[locale] = dict(ns.L.items())
    holes = lambda s: re.findall(r"%[ds]", s) if isinstance(s, str) else []
    return [f"{locale} {key}" for locale in LOCALES for key, text in texts["enUS"].items()
            if key not in texts[locale] or holes(texts[locale][key]) != holes(text)]


def main():
    failures = [f"syntax {e}" for e in syntax()] + [f"format {e}" for e in formats()]
    runs = 0
    for name, (every, patterns) in CHECKS.items():
        code = read(TESTS / "scenarios" / f"{name}.lua")
        for locale in LOCALES if every else ["enUS"]:
            runs += 1
            try:
                output = str(runtime(locale).execute(code))
            except Exception as e:  # a Lua error in the addon or the scenario
                failures.append(f"{name} [{locale}]: {str(e).splitlines()[0]}")
                continue
            for pattern in patterns:
                if not re.search(pattern, output, re.M):
                    failures.append(f"{name} [{locale}]: missing /{pattern}/")
            if "-v" in sys.argv and locale == "enUS":
                print(f"--- {name}\n{output}")
    for failure in failures:
        print("FAIL", failure)
    print(f"{runs} scenario runs, {len(failures)} failures")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
