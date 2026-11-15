#!/usr/bin/env python3
"""Build, verify and install the Voidborn game archive.

Usage (from the repo root, the folder that CONTAINS game/):
    python3 build_sdz.py                      # check, build, verify, install into ~/.spring/games, check the engine
    python3 build_sdz.py /path/to/repo
    python3 build_sdz.py --games-dir DIR      # install somewhere else (or set SPRING_GAMES_DIR)
    python3 build_sdz.py --no-install         # only build + verify dist/voidborn.sdz
    python3 build_sdz.py --no-tests           # skip the smoke tests in tools/test_*.py
    python3 build_sdz.py --no-engine-check    # do not start the engine
    python3 build_sdz.py --engine /path/to/spring-headless
    python3 build_sdz.py --strict-engine      # fail (not just warn) when the engine could not be checked
    python3 build_sdz.py --keep-others        # only warn about other copies of the game, never rename them

Steps (the script stops with exit code 1 at the first failed step):
  1. every Lua file under game/ must compile (needs:  pip install lupa)
  2. the smoke tests in tools/test_*.py must pass
  3. dist/voidborn.sdz is built; game/vb_build.txt holds the build stamp  <date-time>-<content hash>
  4. the archive is re-opened and compared with the sources file by file (names, sha256, zip CRCs, Lua syntax of
     the archived copy, modinfo.lua at the root, the stamp)
  5. it is copied into the games folder atomically and the copy is compared with the build (sha256)
     other copies of the same game that could shadow it are renamed to *.disabled-<stamp> (or reported)
  6. the engine (spring-headless) is started on a bot match and its log must show the build stamp: this is
     the proof that the engine really loads the archive that was just built
"""
import argparse, glob, hashlib, os, re, shutil, subprocess, sys, tempfile, time, zipfile

OK, BAD, WARN = "ok", "FAIL", "warn"
USE_COLOR = sys.stdout.isatty()
def c(code, s): return f"\033[{code}m{s}\033[0m" if USE_COLOR else s
def say(kind, msg): print(f"  {c({'ok': 32, 'FAIL': 31, 'warn': 33}[kind], kind.upper().ljust(4))}  {msg}")
def head(n, title): print(f"\n[{n}/6] {title}")
def die(msg, hint=None):
    say(BAD, msg)
    if hint: print("        " + hint.replace("\n", "\n        "))
    print(c(31, "\nBUILD FAILED - nothing was installed from this run." if not die.installed else "\nBUILD FAILED."))
    sys.exit(1)
die.installed = False

def sha(data): return hashlib.sha256(data).hexdigest()
def sha_file(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""): h.update(chunk)
    return h.hexdigest()

ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument("repo", nargs="?", default=".")
ap.add_argument("--games-dir", default=os.environ.get("SPRING_GAMES_DIR") or os.path.expanduser("~/.spring/games"))
ap.add_argument("--no-install", action="store_true")
ap.add_argument("--no-tests", action="store_true")
ap.add_argument("--no-engine-check", action="store_true")
ap.add_argument("--engine", default=os.environ.get("SPRING_ENGINE"))
ap.add_argument("--strict-engine", action="store_true")
ap.add_argument("--keep-others", action="store_true")
ap.add_argument("--engine-timeout", type=int, default=90)
args = ap.parse_args()

repo = os.path.abspath(args.repo)
game = os.path.join(repo, "game")
dist = os.path.join(repo, "dist")
out = os.path.join(dist, "voidborn.sdz")
if not os.path.isfile(os.path.join(game, "modinfo.lua")):
    sys.exit(f"ERROR: {game}/modinfo.lua not found - run this from the folder that contains game/")
modinfo_src = open(os.path.join(game, "modinfo.lua"), encoding="utf-8").read()
m = re.search(r'\bname\s*=\s*"([^"]+)"', modinfo_src); GAME_NAME = m.group(1) if m else "Voidborn"
m = re.search(r'\bversion\s*=\s*"([^"]+)"', modinfo_src); GAME_VER = m.group(1) if m else "?"
print(f"Voidborn build: game '{GAME_NAME} {GAME_VER}'   repo {repo}")

# stale file from an old patch: it rewrites FontFile in the global config
stale = os.path.join(game, "LuaUI", "Widgets", "vb_fontconfig.lua")
if os.path.exists(stale): os.remove(stale); print("  removed stale", stale)

JUNK = (".DS_Store", "Thumbs.db")
def source_files():
    res = {}
    for root, dirs, files in os.walk(game):
        dirs.sort()
        for f in sorted(files):
            if f in JUNK: continue
            full = os.path.join(root, f)
            res[os.path.relpath(full, game).replace(os.sep, "/")] = full
    return res

# ------------------------------------------------------------------------------------------------ 1. Lua syntax
head(1, "Lua syntax of every file in game/")
try:
    import lupa
    rt = lupa.lua51.LuaRuntime() if hasattr(lupa, "lua51") else lupa.LuaRuntime()   # the engine runs Lua 5.1
except ImportError:
    die("the Python package 'lupa' is needed to compile-check the Lua files", "pip install lupa      (or: pip install --break-system-packages lupa)")
_check = rt.eval("function(s, n) local f, e = (loadstring or load)(s, n) return e end")
def lua_error(text, name): return _check(text, name)
files = source_files()
lua_files = [r for r in files if r.endswith(".lua")]
errors = []
for rel in lua_files:
    e = lua_error(open(files[rel], encoding="utf-8", errors="replace").read(), rel)
    if e: errors.append(str(e))
if errors: die(f"{len(errors)} Lua file(s) do not compile:\n" + "\n".join(errors[:20]))
say(OK, f"{len(lua_files)} Lua files compile")

# ------------------------------------------------------------------------------------------------ 2. smoke tests
head(2, "smoke tests (tools/test_*.py)")
if args.no_tests:
    say(WARN, "skipped (--no-tests)")
else:
    tests = sorted(glob.glob(os.path.join(repo, "tools", "test_*.py")))
    failed = []
    for t in tests:
        try:
            r = subprocess.run([sys.executable, t], cwd=repo, capture_output=True, text=True, timeout=300)
            ok = r.returncode == 0 and "FAILED" not in r.stdout
            tail = (r.stdout + r.stderr).strip().splitlines()[-12:]
        except subprocess.TimeoutExpired:
            ok, tail = False, ["timed out after 300 s"]
        say(OK if ok else BAD, os.path.relpath(t, repo))
        if not ok: failed.append((t, tail))
    if failed:
        die(f"{len(failed)} test(s) failed", "\n".join("%s:\n  %s" % (os.path.basename(t), "\n  ".join(tl)) for t, tl in failed))

# ------------------------------------------------------------------------------------------------ 3. build
head(3, "building dist/voidborn.sdz")
files = source_files()
files.pop("vb_build.txt", None)
h = hashlib.sha256()
for rel in sorted(files):
    h.update(rel.encode() + b"\0"); h.update(open(files[rel], "rb").read()); h.update(b"\0")
STAMP = time.strftime("%d%b-%H%M") + "-" + h.hexdigest()[:8]      # shown in the build panel title and logged by vb_buildinfo.lua
with open(os.path.join(game, "vb_build.txt"), "w") as f: f.write(STAMP)
files["vb_build.txt"] = os.path.join(game, "vb_build.txt")
os.makedirs(dist, exist_ok=True)
tmp_out = out + ".tmp"
with zipfile.ZipFile(tmp_out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for rel in sorted(files): z.write(files[rel], rel)
os.replace(tmp_out, out)
say(OK, f"{len(files)} files -> {out} ({os.path.getsize(out)} bytes)   stamp {STAMP}")

# ------------------------------------------------------------------------------------------------ 4. verify the archive
head(4, "verifying the archive against the sources")
problems = []
with zipfile.ZipFile(out) as z:
    bad = z.testzip()
    if bad: problems.append(f"corrupt member (CRC): {bad}")
    names = z.namelist()
    if "modinfo.lua" not in names: problems.append("modinfo.lua is not at the archive root")
    if any(n.startswith("/") or "\\" in n or ".." in n.split("/") for n in names): problems.append("unsafe or backslash paths in the archive")
    if len(names) != len(set(names)): problems.append("duplicate entries in the archive")
    missing = sorted(set(files) - set(names)); extra = sorted(set(names) - set(files))
    if missing: problems.append("missing from the archive: " + ", ".join(missing[:10]))
    if extra: problems.append("unexpected in the archive: " + ", ".join(extra[:10]))
    for rel in sorted(set(files) & set(names)):
        data = z.read(rel)
        if sha(data) != sha_file(files[rel]): problems.append(f"content differs from the source: {rel}")
        if rel.endswith(".lua"):
            e = lua_error(data.decode("utf-8", "replace"), rel)
            if e: problems.append(f"archived Lua does not compile: {e}")
    if "vb_build.txt" in names and z.read("vb_build.txt").decode().strip() != STAMP: problems.append("build stamp in the archive is wrong")
    if "LuaRules/Gadgets/vb_buildinfo.lua" not in names: problems.append("LuaRules/Gadgets/vb_buildinfo.lua is missing (the engine check needs it)")
if problems: die("the archive is not what the sources say:\n" + "\n".join(problems[:20]))
SDZ_SHA = sha_file(out)
say(OK, f"zip CRCs fine, {len(names)} entries match the sources byte for byte, modinfo.lua at the root")
say(OK, f"sha256 {SDZ_SHA[:16]}...")
if args.no_install:
    print(c(32, f"\nBUILT AND VERIFIED (not installed: --no-install)   stamp {STAMP}"))
    sys.exit(0)

# ------------------------------------------------------------------------------------------------ 5. install
head(5, f"installing into {args.games_dir}")
games_dir = os.path.abspath(os.path.expanduser(args.games_dir))
try: os.makedirs(games_dir, exist_ok=True)
except OSError as e: die(f"cannot create {games_dir}: {e}")
dest = os.path.join(games_dir, "voidborn.sdz")
tmp_dest = os.path.join(games_dir, ".voidborn.sdz.tmp")
try:
    shutil.copyfile(out, tmp_dest)
    os.replace(tmp_dest, dest)                                   # atomic: the engine never sees a half written archive
    os.utime(dest, None)
except OSError as e:
    if os.path.exists(tmp_dest): os.remove(tmp_dest)
    die(f"could not write {dest}: {e}")
die.installed = True
if not os.path.isfile(dest) or sha_file(dest) != SDZ_SHA:
    die(f"the copy in {games_dir} does not match the build", "check the free disk space and the permissions of the folder")
say(OK, f"{dest}  ({os.path.getsize(dest)} bytes, sha256 matches the build)")

# other copies of this game: the engine finds games by NAME, so a second archive of the same game can shadow ours
data_dirs = [games_dir]
for extra in [os.path.expanduser("~/.spring/games"), os.path.expanduser("~/.local/state/spring/games"),
              os.path.expanduser("~/.config/spring/games"), "/usr/share/games/spring/games", "/usr/local/share/games/spring/games"] \
             + [os.path.join(p, "games") for p in os.environ.get("SPRING_DATADIR", "").split(os.pathsep) if p] \
             + [os.path.join(p, "games") for p in glob.glob(os.path.expanduser("~/.spring/engine/*"))]:
    if os.path.isdir(extra) and not any(os.path.samefile(extra, d) for d in data_dirs): data_dirs.append(extra)
def archive_game(path):
    """the game name from the modinfo.lua of a Spring game archive (.sdz or .sdd), or None"""
    try:
        if os.path.isdir(path) and path.endswith(".sdd"): txt = open(os.path.join(path, "modinfo.lua"), encoding="utf-8", errors="replace").read()
        elif path.endswith(".sdz") and zipfile.is_zipfile(path): txt = zipfile.ZipFile(path).read("modinfo.lua").decode("utf-8", "replace")
        else: return None
    except (OSError, KeyError, zipfile.BadZipFile): return None
    n = re.search(r'\bname\s*=\s*"([^"]+)"', txt)
    return (n.group(1) if n else None)
shadow = 0
for d in data_dirs:
    for entry in sorted(os.listdir(d)):
        p = os.path.join(d, entry)
        if os.path.exists(dest) and os.path.exists(p) and os.path.samefile(p, dest): continue
        if archive_game(p) != GAME_NAME: continue
        same = os.path.isfile(p) and sha_file(p) == SDZ_SHA
        if args.keep_others or d != games_dir:
            say(WARN, f"another copy of '{GAME_NAME}': {p}" + ("  (identical to the build)" if same else "  (OLD - the engine may load this one!)")
                + ("" if d == games_dir else "\n        outside the games folder used here: remove or rename it yourself"))
            shadow += not same
        else:
            new = f"{p}.disabled-{STAMP}"
            try: os.rename(p, new); say(OK, f"old copy of the game moved out of the way: {entry} -> {os.path.basename(new)}")
            except OSError as e: say(WARN, f"could not rename {p}: {e}"); shadow += 1
if not shadow: say(OK, f"no other copy of '{GAME_NAME}' can shadow the new archive")
maps_dir = os.path.join(os.path.dirname(games_dir), "maps")
if not glob.glob(os.path.join(maps_dir, "voidborn_rift*")) and not glob.glob(os.path.join(maps_dir, "*oidborn*")):
    say(WARN, f"no Voidborn Rift map found in {maps_dir} (the Play_*.txt scripts need it; dist/voidborn_rift.sd7 is built by tools/package.sh)")

# ------------------------------------------------------------------------------------------------ 6. the engine
head(6, "does the engine load THIS build?")
def find_engine():
    cands = []
    if args.engine: cands.append(os.path.expanduser(args.engine))
    for n in ("spring-headless", "spring-dedicated"):
        w = shutil.which(n)
        if w: cands.append(w)
    for pat in ("~/.spring/engine/*/spring-headless", "/usr/games/spring-headless", "/usr/bin/spring-headless", "/usr/local/bin/spring-headless"):
        cands += sorted(glob.glob(os.path.expanduser(pat)), reverse=True)
    for cnd in cands:
        if os.path.isfile(cnd) and os.access(cnd, os.X_OK): return cnd
def engine_check():
    """returns (True, msg) loaded this build / (False, msg) loaded another build or failed / (None, msg) could not check"""
    if args.no_engine_check: return None, "skipped (--no-engine-check)"
    eng = find_engine()
    if not eng: return None, "no spring-headless found (use --engine /path/to/spring-headless)"
    script = os.path.join(repo, "Watch_Bot_vs_Bot.txt")
    if not os.path.isfile(script): return None, "Watch_Bot_vs_Bot.txt not found"
    write_dir = os.path.dirname(games_dir)
    infolog = os.path.join(write_dir, "infolog.txt")
    cmd = [eng]
    if os.path.abspath(write_dir) != os.path.abspath(os.path.expanduser("~/.spring")): cmd += ["--write-dir", write_dir]
    log = tempfile.NamedTemporaryFile("w+", suffix=".log", delete=False)
    cmd.append(script)
    say(OK, "starting " + " ".join(cmd))
    proc = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT, cwd=write_dir)
    pat = re.compile(r"\[VB\] build (\S+)")
    seen, t0 = None, time.time()
    try:
        while time.time() - t0 < args.engine_timeout and seen is None:
            time.sleep(0.5)
            for p in (log.name, infolog):
                try:
                    if p == infolog and os.path.getmtime(p) < t0 - 2: continue      # an old log from an earlier run
                    mm = pat.findall(open(p, encoding="utf-8", errors="replace").read())
                    if mm: seen = mm[-1]; break
                except OSError: pass
            if proc.poll() is not None and seen is None: break
    finally:
        if proc.poll() is None:
            proc.terminate()
            try: proc.wait(8)
            except subprocess.TimeoutExpired: proc.kill()
    tail = ""
    try: tail = "\n".join(open(log.name, errors="replace").read().strip().splitlines()[-12:])
    except OSError: pass
    os.unlink(log.name)
    if seen == STAMP: return True, f"the engine ({os.path.basename(eng)}) loaded the build stamped {STAMP}"
    if seen: return False, f"the engine loaded an OLD build ({seen}), not {STAMP}: another archive of the game wins - see the warnings in step 5"
    return False, f"the engine ran but never logged '[VB] build {STAMP}' (map missing? game failed to start?)\n" + tail
res, msg = engine_check()
if res is True: say(OK, msg)
elif res is False: die(msg)
else:
    say(WARN, "engine NOT verified: " + msg)
    print(f"        check by hand: start the game, the build panel title ends with  {STAMP}  and infolog.txt has  [VB] build {STAMP}")
    if args.strict_engine: die("--strict-engine: the engine could not be checked")

print(c(32, f"\nALL GOOD: built, verified, installed to {dest}" + ("" if res else " (engine not checked)") + f"\nstamp {STAMP}"))
