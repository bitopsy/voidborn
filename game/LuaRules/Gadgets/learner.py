#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
learner.py - outer learning loop for ai_learner.lua

ai_learner.lua cannot write files, so the learning between matches happens here:

    loop:
        1. build a start script (genome -> lrn_<gene> mod options) and run one headless match
        2. read the  [LEARN_STATS] {json}  line the gadget prints at game over
        3. turn it into a FITNESS and update an ELO rating
        4. a champion/challenger search (1+1 evolution strategy) moves the genome

Everything is logged under  learner_data/ :
    games.csv            one row per match   (result, stats, fitness parts, elo before/after, genome)
    progress.csv         one row per generation (champion/challenger fitness, champion elo, sigma, genome)
    state.json           resume file (rerun the script and it carries on)
    best_genome.json     genome of the current champion
    best_modoptions.txt  the same genome as lrn_<gene>=value lines (paste into [MODOPTIONS])

ELO: every genome has its own rating. A new challenger starts at its parent's rating and is updated after
each of its matches against an opponent bot of fixed rating (CONFIG["opponent_elo"], default 1500).
So Elo here means "strength relative to that opponent"; change the opponent and the numbers change.

FITNESS: a blend of result (win/draw/loss), kill/loss balance, income, energy stalls, floating metal and
game length. Win/loss alone is far too noisy to learn from in a few matches. Weights are in FITNESS_W.

Usage
    python learner.py --simulate --generations 20     test the loop without the game (fake matches)
    python learner.py --dry-run                       print the start script that would be used
    python learner.py --generations 50                real run (fill in CONFIG below first)
    python learner.py --report                        summary of the progress so far
    python learner.py --set map=MyMap --set opponent_luaai=Darwin     override any CONFIG key
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import random
import re
import subprocess
import sys
import threading
import time
from datetime import datetime
from pathlib import Path

# =====================================================================================
# CONFIG - edit this (or override with --set key=value / --config file.json)
# =====================================================================================
CONFIG = {
    # --- how to launch a match ---------------------------------------------------
    "engine": "spring-headless",      # path to spring-headless / recoil-headless
    "write_dir": "",                  # passed as --write-dir if set (where games/maps are installed)
    "infolog": "",                    # optional: path to infolog.txt, used if stdout has no stats line
    "game": "",                       # GameType, exactly as the engine knows it (name + version)
    "map": "",                        # MapName
    "side_learner": "Voidborn",       # faction (Side=) of the learner team
    "side_opponent": "Voidborn",      # faction of the opponent team
    "speed": 20,                      # MinSpeed / MaxSpeed written to the start script
    "start_pos_type": 1,              # 0 fixed, 1 random, 2/3 choose (1 = random start positions)
    "extra_modoptions": {},           # e.g. {"vb_cmd_upgrade_t3": "34921"}
    # --- who controls what -------------------------------------------------------
    "learner_mode": "luaai",          # "luaai": LuaAI=Learner (needs a LuaAI.lua entry)
                                      # "modoption": lrn_teams=<id> + a placeholder native AI on that team
    "learner_luaai": "Learner",
    "placeholder_ai": "NullAI",       # only used when learner_mode == "modoption"
    "placeholder_ai_version": "",
    "opponent_luaai": "Darwin",       # the bot the learner is measured against
    "bot_skill": 2,                   # 1..3, same option the other bots read
    # --- match limits ------------------------------------------------------------
    "max_frames": 54000,              # lrn_max_frames: stalemates end as a draw (30 frames = 1 s)
    "wall_timeout": 1800,             # seconds of real time before a match is killed and ignored
    "max_failures": 5,                # abort after this many failed matches in a row
    # --- elo ---------------------------------------------------------------------
    "opponent_elo": 1500.0,           # fixed rating of the opponent (the anchor)
    "start_elo": 1500.0,              # rating of the very first genome
    "elo_k": 24.0,
    # --- search ------------------------------------------------------------------
    "games_per_eval": 6,              # matches a challenger plays
    "champ_games": 2,                 # extra matches the champion plays per generation (keeps its score fresh)
    "window": 12,                     # champion fitness = mean of its last N matches
    "margin": 0.05,                   # challenger must beat the champion by at least this much fitness ...
    "accept_z": 1.0,                  # ... AND by this many standard errors (guards against lucky streaks)
    "sigma": 0.10,                    # initial mutation size (fraction of each gene's range)
    "sigma_min": 0.02,
    "sigma_max": 0.25,
    "mut_rate": 0.35,                 # chance that a gene is mutated
    "lamarck": 0.5,                   # 0..1: how much of the in-match lessons (attack_mul, kind_mul, ...)
                                      # is baked into the next genome. 0 = ignore the lessons.
    "income_ref": 20.0,               # metal/s that counts as a "good" average income (fitness scale)
    # --- files -------------------------------------------------------------------
    "data_dir": "learner_data",
}

FITNESS_W = {"result": 1.0, "kd": 0.6, "eco": 0.3, "stall": 0.4, "float": 0.2, "time": 0.3}

# =====================================================================================
# GENOME - names, defaults and ranges. KEEP IN SYNC with GENE_DEFAULTS in ai_learner.lua.
#          name: (default, min, max, is_integer)
# =====================================================================================
GENES = {
    "w_raider":        (0.30, 0.0, 1.5, False),
    "w_assault":       (0.30, 0.0, 1.5, False),
    "w_art":           (0.25, 0.0, 1.5, False),
    "w_heavy":         (0.50, 0.0, 1.5, False),
    "w_support":       (0.10, 0.0, 0.6, False),
    "eco_priority":    (0.50, 0.2, 1.2, False),
    "def_ratio":       (0.15, 0.0, 0.6, False),
    "expand_interval": (600, 200, 1800, True),
    "con_rate":        (1.0, 0.5, 2.0, False),
    "attack_value":    (2500, 800, 8000, True),
    "attack_interval": (1200, 400, 3600, True),
    "tech2_frame":     (12000, 6000, 24000, True),
    "tech3_frame":     (30000, 18000, 60000, True),
    "scout_rate":      (0.20, 0.0, 0.6, False),
    "retreat_hp":      (0.25, 0.05, 0.5, False),
}
ROLES = ["raider", "assault", "art", "heavy", "support"]

STATS_RE = re.compile(r"\[LEARN_STATS\]\s*(\{.*\})\s*$")


def default_genome():
    return sanitize({n: d for n, (d, lo, hi, i) in GENES.items()})


def sanitize(g):
    """clamp to range, round integers, 6 significant digits (the gadget prints %.6g), keep it playable"""
    out = {}
    for n, (d, lo, hi, isint) in GENES.items():
        v = min(hi, max(lo, float(g.get(n, d))))
        out[n] = int(round(v)) if isint else float(f"{v:.6g}")
    s = sum(out["w_" + r] for r in ("raider", "assault", "art", "heavy"))
    if s < 0.2:                                   # never end up with (almost) no army weights
        out["w_raider"] = float(f"{min(GENES['w_raider'][2], out['w_raider'] + 0.2 - s):.6g}")
    if out["tech3_frame"] < out["tech2_frame"] + 3000:
        out["tech3_frame"] = min(GENES["tech3_frame"][2], out["tech2_frame"] + 3000)
    return out


def fmt(v):
    return str(int(v)) if isinstance(v, int) else f"{v:.6g}"


def mutate(parent, sigma, rng, rate):
    child = dict(parent)
    names = list(GENES)
    hit = [n for n in names if rng.random() < rate] or [rng.choice(names)]
    for n in hit:
        _, lo, hi, _ = GENES[n]
        child[n] = child[n] + rng.gauss(0.0, sigma) * (hi - lo)
    return sanitize(child)


def geo_mean(xs):
    xs = [x for x in xs if x and x > 0]
    return math.exp(sum(math.log(x) for x in xs) / len(xs)) if xs else 1.0


def average_lessons(lessons):
    """geometric mean of the in-match multipliers over the recent matches of one genome"""
    if not lessons:
        return None
    return {
        "attack_mul": geo_mean([l.get("attack_mul", 1.0) for l in lessons]),
        "solar_mul": geo_mean([l.get("solar_mul", 1.0) for l in lessons]),
        "kind_mul": {r: geo_mean([(l.get("kind_mul") or {}).get(r, 1.0) for l in lessons]) for r in ROLES},
    }


def apply_lessons(genome, avg, strength):
    """Lamarckian step: what the bot learned inside the matches is written back into the genome."""
    if not avg or strength <= 0:
        return dict(genome)
    g = dict(genome)
    g["attack_value"] = g["attack_value"] * avg["attack_mul"] ** strength
    for r in ROLES:
        g["w_" + r] = g["w_" + r] * avg["kind_mul"][r] ** strength
    g["eco_priority"] = g["eco_priority"] * avg["solar_mul"] ** (strength * 0.5)
    return sanitize(g)


# =====================================================================================
# FITNESS and ELO
# =====================================================================================
def compute_fitness(rec, cfg):
    st = rec.get("stats", {})
    frames = max(1, int(rec.get("frames", 1)))
    won, draw = int(rec.get("won", 0)), int(rec.get("draw", 0))
    res = 1.0 if won else (0.0 if draw else -1.0)
    killed, lost = float(st.get("killed", 0)), float(st.get("lost", 0))
    kd = (killed - lost) / (killed + lost + 1.0)                       # -1 .. 1
    samples = max(1.0, float(st.get("samples", 1)))                    # frames covered by the samples
    calls = samples / 30.0                                             # the gadget samples once per second
    income = float(st.get("income", 0)) / max(1.0, calls)              # mean metal income per second
    eco = min(1.5, income / cfg["income_ref"])
    stall = min(1.0, float(st.get("stall", 0)) / samples)
    flt = min(1.0, float(st.get("float", 0)) / samples)
    t = min(1.0, frames / max(1, cfg["max_frames"]))
    tm = (1.0 - t) if won else (t if not draw else 0.0)               # win fast / lose slowly
    parts = {
        "result": FITNESS_W["result"] * res,
        "kd": FITNESS_W["kd"] * kd,
        "eco": FITNESS_W["eco"] * eco,
        "stall": -FITNESS_W["stall"] * stall,
        "float": -FITNESS_W["float"] * flt,
        "time": FITNESS_W["time"] * tm,
    }
    return sum(parts.values()), parts


def elo_expected(r, ro):
    return 1.0 / (1.0 + 10.0 ** ((ro - r) / 400.0))


def elo_update(r, score, ro, k):
    return r + k * (score - elo_expected(r, ro))


# =====================================================================================
# START SCRIPT + RUNNING THE ENGINE
# =====================================================================================
def build_script(cfg, genome, learner_team, game_id):
    mo = {f"lrn_{k}": fmt(v) for k, v in genome.items()}
    mo.update({"lrn_game_id": game_id, "lrn_max_frames": str(cfg["max_frames"]), "bot_skill": str(cfg["bot_skill"])})
    if cfg["learner_mode"] == "modoption":
        mo["lrn_teams"] = str(learner_team)
    mo.update({k: str(v) for k, v in cfg["extra_modoptions"].items()})

    L = ["[GAME]", "{",
         f"\tGameType={cfg['game']};", f"\tMapName={cfg['map']};",
         "\tIsHost=1;", "\tOnlyLocal=1;", "\tMyPlayerName=Observer;",
         f"\tStartPosType={cfg['start_pos_type']};",
         f"\tMinSpeed={cfg['speed']};", f"\tMaxSpeed={cfg['speed']};",
         "\tNumPlayers=1;", "\tNumTeams=2;", "\tNumAllyTeams=2;", "",
         "\t[MODOPTIONS]", "\t{"]
    L += [f"\t\t{k}={v};" for k, v in sorted(mo.items())]
    L += ["\t}", "", "\t[PLAYER0]", "\t{", "\t\tName=Observer;", "\t\tSpectator=1;", "\t}", ""]
    for t in (0, 1):
        is_l = (t == learner_team)
        lua = cfg["learner_luaai"] if (is_l and cfg["learner_mode"] == "luaai") else (None if is_l else cfg["opponent_luaai"])
        L += [f"\t[TEAM{t}]", "\t{", "\t\tTeamLeader=0;", f"\t\tAllyTeam={t};",
              f"\t\tSide={cfg['side_learner'] if is_l else cfg['side_opponent']};",
              "\t\tHandicap=0;", f"\t\tRGBColor={'0.2 0.4 1.0' if is_l else '1.0 0.3 0.2'};"]
        if lua:
            L.append(f"\t\tLuaAI={lua};")
        L += ["\t}", ""]
        if is_l and cfg["learner_mode"] == "modoption":
            L += [f"\t[AI{t}]", "\t{", "\t\tName=LearnerSlot;", f"\t\tShortName={cfg['placeholder_ai']};",
                  f"\t\tVersion={cfg['placeholder_ai_version']};", f"\t\tTeam={t};", "\t\tHost=0;", "\t}", ""]
    for t in (0, 1):
        L += [f"\t[ALLYTEAM{t}]", "\t{", "\t\tNumAllies=0;", "\t}", ""]
    L.append("}")
    return "\n".join(L) + "\n"


def run_engine(cfg, genome, learner_team, game_id, workdir):
    """run one headless match, return all output text (or None on failure/timeout)"""
    script = workdir / f"{game_id}.txt"
    script.write_text(build_script(cfg, genome, learner_team, game_id))
    cmd = [cfg["engine"]] + (["--write-dir", cfg["write_dir"]] if cfg["write_dir"] else []) + [str(script)]
    try:
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                                errors="replace", bufsize=1)
    except OSError as e:
        print(f"  ! cannot start the engine ({cmd[0]}): {e}")
        return None
    lines, found = [], threading.Event()

    def reader():
        for line in proc.stdout:
            lines.append(line)
            if "[LEARN_STATS]" in line and game_id in line:
                found.set()

    th = threading.Thread(target=reader, daemon=True)
    th.start()
    deadline = time.time() + cfg["wall_timeout"]
    while time.time() < deadline and not found.is_set() and proc.poll() is None:
        found.wait(1.0)
    timed_out = not found.is_set() and proc.poll() is None
    if found.is_set():
        time.sleep(1.5)                                   # let the other team's line arrive too
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(10)
        except subprocess.TimeoutExpired:
            proc.kill()
    th.join(5)
    text = "".join(lines)
    if game_id not in text and cfg["infolog"] and Path(cfg["infolog"]).exists():
        text += Path(cfg["infolog"]).read_text(errors="replace")      # some builds log only to infolog.txt
    if timed_out:
        print("  ! match timed out")
    try:
        script.unlink()
    except OSError:
        pass
    return text


def parse_stats(text, game_id):
    out = []
    for line in (text or "").splitlines():
        m = STATS_RE.search(line)
        if m:
            try:
                d = json.loads(m.group(1))
            except ValueError:
                continue
            if d.get("game_id") == game_id:
                out.append(d)
    return out


def genome_mismatch(sent, echoed, tol=1e-3):
    return [k for k, v in sent.items() if k not in echoed or abs(echoed[k] - v) > tol * max(1.0, abs(v))]


# =====================================================================================
# SIMULATOR (--simulate): fake matches so the whole loop can be tested without the game
# =====================================================================================
def _make_optimum():
    r = random.Random(1234)
    return {n: min(hi, max(lo, d + r.uniform(-0.3, 0.3) * (hi - lo))) for n, (d, lo, hi, _) in GENES.items()}


SIM_OPT = _make_optimum()


def sim_pwin(genome):
    dist = math.sqrt(sum(((genome[n] - SIM_OPT[n]) / (hi - lo)) ** 2 for n, (_, lo, hi, _) in GENES.items()) / len(GENES))
    return 1.0 / (1.0 + math.exp((dist - 0.10) * 18.0))


def simulate_match(cfg, genome, learner_team, game_id, rng):
    if rng.random() < 0.03:
        return None                                            # pretend some matches crash
    p = sim_pwin(genome)
    won = rng.random() < p
    frames = int(rng.uniform(15000, 45000))
    noise = lambda: math.exp(rng.gauss(0, 0.25))
    kill, lost = 8000 * (0.4 + 0.8 * p) * noise(), 8000 * (1.2 - 0.8 * p) * noise()
    clampf = lambda x, a, b: max(a, min(b, x))
    rec = {
        "game_id": game_id, "team": learner_team, "won": int(won), "draw": 0, "frames": frames,
        "skill": cfg["bot_skill"], "genome": genome,
        "stats": {"killed": kill, "lost": lost, "income": (frames / 30) * (8 + 14 * p) * noise(),
                  "stall": frames * rng.uniform(0, 0.25) * (1 - p), "float": frames * rng.uniform(0, 0.3),
                  "samples": frames, "waves": rng.randint(2, 9), "bad_waves": rng.randint(0, 3),
                  "good_waves": rng.randint(0, 4), "mex_peak": rng.randint(5, 14), "t2": 12000, "t3": -1},
        "lessons": {"attack_mul": clampf(SIM_OPT["attack_value"] / genome["attack_value"], 0.6, 2.0),
                    "solar_mul": clampf(SIM_OPT["eco_priority"] / genome["eco_priority"], 1.0, 1.8),
                    "spend_mul": 1.0,
                    "kind_mul": {r: clampf(SIM_OPT["w_" + r] / max(0.05, genome["w_" + r]), 0.5, 2.0) for r in ROLES}},
    }
    return "[LEARN_STATS] " + json.dumps(rec)


# =====================================================================================
# LOGGING
# =====================================================================================
GENE_COLS = ["g_" + n for n in GENES]
GAME_COLS = (["time", "game_id", "generation", "role", "genome_id", "learner_team", "result", "won", "draw",
              "frames", "skill", "fitness", "f_result", "f_kd", "f_eco", "f_stall", "f_float", "f_time",
              "killed", "lost", "income", "stall", "float", "samples", "waves", "bad_waves", "good_waves",
              "mex_peak", "t2", "t3", "attack_mul", "solar_mul", "spend_mul",
              "opponent", "opponent_elo", "elo_before", "elo_after"] + GENE_COLS)
PROG_COLS = (["time", "generation", "accepted", "sigma", "challenger_id", "challenger_fitness", "champion_fitness",
              "champion_id", "champion_elo", "challenger_elo", "elo_peak", "champion_games", "total_games"] + GENE_COLS)


def append_row(path, cols, row):
    new = not path.exists()
    with path.open("a", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore")
        if new:
            w.writeheader()
        w.writerow(row)


def now():
    return datetime.now().isoformat(timespec="seconds")


# =====================================================================================
# THE LEARNING LOOP
# =====================================================================================
class Ctx:
    def __init__(self, cfg, data, rng, run_id):
        self.cfg, self.data, self.rng, self.run_id = cfg, data, rng, run_id
        self.fail_streak = 0
        self.mismatch_streak = 0


def new_entity(state, genome, elo):
    state["next_id"] += 1
    return {"id": f"g{state['next_id']:04d}", "genome": genome, "elo": elo, "games": 0, "fit": [], "lessons": []}


def play_and_record(state, ctx, ent, role, gen):
    cfg = ctx.cfg
    state["game_counter"] += 1
    team = state["game_counter"] % 2                       # alternate sides: removes start-position bias
    game_id = f"L{ctx.run_id}_{state['game_counter']:05d}"
    if cfg["simulate"]:
        text = simulate_match(cfg, ent["genome"], team, game_id, ctx.rng)
    else:
        text = run_engine(cfg, ent["genome"], team, game_id, ctx.data)
    rec = next((r for r in parse_stats(text, game_id) if r.get("team") == team), None)
    if rec is None:
        ctx.fail_streak += 1
        print(f"  ! no [LEARN_STATS] line for {game_id} ({ctx.fail_streak} in a row)")
        if ctx.fail_streak >= cfg["max_failures"]:
            sys.exit("Too many failed matches in a row. Check engine path, game/map names, the Learner LuaAI entry "
                     "and that ai_learner.lua is loaded (run with --dry-run to see the start script).")
        return False
    ctx.fail_streak = 0

    bad = genome_mismatch(ent["genome"], rec.get("genome", {}))
    if bad:
        ctx.mismatch_streak += 1
        print(f"  ! the gadget used a different genome than the one sent (genes: {', '.join(bad[:4])}...)")
        if ctx.mismatch_streak >= 3:
            sys.exit("The gadget does not receive the lrn_* mod options, so nothing could be learned. "
                     "Check that the [MODOPTIONS] block reaches the game.")
    else:
        ctx.mismatch_streak = 0

    fitness, parts = compute_fitness(rec, cfg)
    score = 1.0 if rec.get("won") else (0.5 if rec.get("draw") else 0.0)
    before = ent["elo"]
    ent["elo"] = elo_update(before, score, cfg["opponent_elo"], cfg["elo_k"])
    ent["games"] += 1
    ent["fit"] = (ent["fit"] + [fitness])[-cfg["window"]:]
    ent["lessons"] = (ent["lessons"] + [rec.get("lessons", {})])[-cfg["window"]:]
    state["total_games"] += 1
    st, ls = rec.get("stats", {}), rec.get("lessons", {})
    row = {"time": now(), "game_id": game_id, "generation": gen, "role": role, "genome_id": ent["id"],
           "learner_team": team, "result": "win" if rec.get("won") else ("draw" if rec.get("draw") else "loss"),
           "won": rec.get("won", 0), "draw": rec.get("draw", 0), "frames": rec.get("frames", 0),
           "skill": rec.get("skill", ""), "fitness": round(fitness, 4),
           **{f"f_{k}": round(v, 4) for k, v in parts.items()},
           **{k: st.get(k, "") for k in ("killed", "lost", "income", "stall", "float", "samples", "waves",
                                         "bad_waves", "good_waves", "mex_peak", "t2", "t3")},
           "attack_mul": ls.get("attack_mul", ""), "solar_mul": ls.get("solar_mul", ""),
           "spend_mul": ls.get("spend_mul", ""), "opponent": cfg["opponent_luaai"],
           "opponent_elo": cfg["opponent_elo"], "elo_before": round(before, 1), "elo_after": round(ent["elo"], 1),
           **{"g_" + k: v for k, v in ent["genome"].items()}}
    append_row(ctx.data / "games.csv", GAME_COLS, row)
    print(f"  {role:<10} {ent['id']}  {row['result']:<4}  fitness {fitness:+.3f}  elo {before:.0f} -> {ent['elo']:.0f}")
    return True


def mean(xs):
    return sum(xs) / len(xs) if xs else float("nan")


def variance(xs):
    return sum((v - mean(xs)) ** 2 for v in xs) / (len(xs) - 1) if len(xs) > 1 else 0.5


def is_better(xs, cs, margin, z):
    """challenger scores xs vs champion scores cs: needs a real margin AND a z-score (noisy matches!)"""
    if not xs or not cs:
        return False, 0.0
    se = math.sqrt(max(variance(xs), 0.1) / len(xs) + max(variance(cs), 0.1) / len(cs))
    diff = mean(xs) - mean(cs)
    return (diff > margin and diff / se > z), diff / se


def run_generation(state, ctx):
    cfg, champ = ctx.cfg, state["champion"]
    gen = state["generation"] + 1
    print(f"\n=== generation {gen}  (sigma {state['sigma']:.3f}) ===")

    n_champ = cfg["champ_games"] if len(champ["fit"]) >= cfg["games_per_eval"] else cfg["games_per_eval"]
    for _ in range(n_champ):
        play_and_record(state, ctx, champ, "champion", gen)

    base = apply_lessons(champ["genome"], average_lessons(champ["lessons"]), cfg["lamarck"])
    chal = new_entity(state, mutate(base, state["sigma"], ctx.rng, cfg["mut_rate"]), champ["elo"])
    for _ in range(cfg["games_per_eval"]):
        play_and_record(state, ctx, chal, "challenger", gen)

    cf, xf = mean(champ["fit"]), mean(chal["fit"])
    accepted, zscore = is_better(chal["fit"], champ["fit"], cfg["margin"], cfg["accept_z"])
    if accepted:
        state["champion"] = chal
        state["sigma"] = min(cfg["sigma_max"], state["sigma"] * 1.15)       # 1/5th success rule
    elif chal["fit"]:
        state["sigma"] = max(cfg["sigma_min"], state["sigma"] * 0.966)
    state["generation"] = gen
    champ = state["champion"]
    state["elo_peak"] = max(state["elo_peak"], champ["elo"])

    append_row(ctx.data / "progress.csv", PROG_COLS, {
        "time": now(), "generation": gen, "accepted": int(accepted), "sigma": round(state["sigma"], 4),
        "challenger_id": chal["id"], "challenger_fitness": round(xf, 4) if chal["fit"] else "",
        "champion_fitness": round(cf, 4) if not math.isnan(cf) else "", "champion_id": champ["id"],
        "champion_elo": round(champ["elo"], 1), "challenger_elo": round(chal["elo"], 1),
        "elo_peak": round(state["elo_peak"], 1), "champion_games": champ["games"], "total_games": state["total_games"],
        **{"g_" + k: v for k, v in champ["genome"].items()}})
    extra = f" | true win prob {sim_pwin(champ['genome']):.2f}" if cfg["simulate"] else ""
    print(f"  -> challenger {xf:+.3f} vs champion {cf:+.3f} (z {zscore:+.2f}): "
          f"{'ACCEPTED' if accepted else 'rejected'} | champion {champ['id']} elo {champ['elo']:.0f} "
          f"(peak {state['elo_peak']:.0f}){extra}")
    save_outputs(state, ctx.data)


def save_outputs(state, data):
    (data / "state.json").write_text(json.dumps(state, indent=1))
    g = state["champion"]["genome"]
    (data / "best_genome.json").write_text(json.dumps(
        {"id": state["champion"]["id"], "elo": round(state["champion"]["elo"], 1),
         "generation": state["generation"], "genome": g}, indent=1))
    (data / "best_modoptions.txt").write_text("\n".join(f"lrn_{k}={fmt(v)}" for k, v in g.items()) + "\n")


def new_state(cfg):
    st = {"version": 1, "generation": 0, "sigma": cfg["sigma"], "game_counter": 0, "total_games": 0,
          "next_id": 0, "elo_peak": cfg["start_elo"]}
    st["champion"] = new_entity(st, default_genome(), cfg["start_elo"])
    return st


def report(data):
    p = data / "progress.csv"
    if not p.exists():
        print("no progress.csv yet")
        return
    rows = list(csv.DictReader(p.open()))
    print(f"{len(rows)} generations, {rows[-1]['total_games']} matches\n")
    print(f"{'gen':>4} {'acc':>3} {'sigma':>6} {'champ fit':>10} {'chal fit':>9} {'champ elo':>10} {'peak':>6}")
    show = rows if len(rows) <= 20 else rows[:3] + rows[-15:]
    for r in show:
        print(f"{r['generation']:>4} {r['accepted']:>3} {r['sigma']:>6} {r['champion_fitness']:>10} "
              f"{r['challenger_fitness']:>9} {r['champion_elo']:>10} {r['elo_peak']:>6}")
    print(f"\nElo: {rows[0]['champion_elo']} -> {rows[-1]['champion_elo']}   "
          f"accepted {sum(int(r['accepted']) for r in rows)}/{len(rows)}")


def main():
    ap = argparse.ArgumentParser(description="outer learning loop for ai_learner.lua")
    ap.add_argument("--generations", type=int, default=20)
    ap.add_argument("--simulate", action="store_true", help="fake matches, no game needed (tests the loop)")
    ap.add_argument("--dry-run", action="store_true", help="print the start script and exit")
    ap.add_argument("--report", action="store_true", help="print a summary of progress.csv and exit")
    ap.add_argument("--reset", action="store_true", help="forget the saved state and start over")
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--config", help="JSON file with CONFIG overrides")
    ap.add_argument("--set", action="append", default=[], metavar="KEY=VALUE", help="override one CONFIG key")
    ap.add_argument("--data-dir")
    args = ap.parse_args()

    cfg = json.loads(json.dumps(CONFIG))
    if args.config:
        cfg.update(json.loads(Path(args.config).read_text()))
    for kv in args.set:
        k, _, v = kv.partition("=")
        if k not in cfg:
            sys.exit(f"unknown config key: {k}")
        try:
            cfg[k] = json.loads(v)
        except ValueError:
            cfg[k] = v
    if args.data_dir:
        cfg["data_dir"] = args.data_dir
    cfg["simulate"] = args.simulate
    data = Path(cfg["data_dir"])
    data.mkdir(parents=True, exist_ok=True)

    if args.report:
        return report(data)
    if args.dry_run:
        print(build_script(cfg, default_genome(), 0, "dryrun"))
        return
    if not args.simulate and not (cfg["game"] and cfg["map"]):
        sys.exit("Set CONFIG['game'] and CONFIG['map'] (or --set game=... --set map=...), or try --simulate.")

    sp = data / "state.json"
    if sp.exists() and not args.reset:
        state = json.loads(sp.read_text())
        print(f"resuming at generation {state['generation']} (champion {state['champion']['id']}, "
              f"elo {state['champion']['elo']:.0f})")
    else:
        state = new_state(cfg)
    rng = random.Random(args.seed)
    ctx = Ctx(cfg, data, rng, datetime.now().strftime("%m%d%H%M%S"))
    try:
        for _ in range(args.generations):
            run_generation(state, ctx)
    except KeyboardInterrupt:
        print("\ninterrupted - saving")
        save_outputs(state, data)
    print(f"\nlogs: {data / 'games.csv'}, {data / 'progress.csv'}; best genome: {data / 'best_modoptions.txt'}")


if __name__ == "__main__":
    main()
