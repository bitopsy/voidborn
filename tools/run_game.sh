#!/bin/sh
# Quick iteration loop: rebuild the game archive, install it and run the engine
# on the bot-vs-bot script, then show what the log says.  Used while working on
# the gadgets, where every change needs a rebuild before the engine sees it.
#
#   sh tools/run_game.sh            # build, install, run, show the log
#
set -e
cd "$(dirname "$0")/.."
ENGINE="${ENGINE:-$HOME/.spring/engine/2026.11.02/spring-headless}"
python3 build_sdz.py --no-tests --no-engine-check > /tmp/opencode/build.log 2>&1 || {
  tail -20 /tmp/opencode/build.log; exit 1; }
cp dist/voidborn.sdz "$HOME/.spring/games/voidborn.sdz"
pkill -x spring 2>/dev/null || true
sleep 1
LOG=/tmp/opencode/run.log
timeout "${RUN_TIMEOUT:-90}" "$ENGINE" "${1:-Watch_Bot_vs_Bot.txt}" > "$LOG" 2>&1 || true
echo "--- errors ---"
grep -iE "error=2|LuaErrRun|Fatal|Call failure" "$LOG" | head -10 || true
echo "--- [VB] ---"
grep "\[VB\]" "$LOG" | head -20 || true
