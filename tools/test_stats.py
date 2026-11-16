#!/usr/bin/env python3
"""Smoke test of the stats gadget + dashboard widget with a mock engine.   pip install lupa"""
import os, sys, lupa
try:
    from lupa import lua51 as _L
except ImportError:
    _L = lupa
root = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import glob
rt = _L.LuaRuntime(); rt.globals().ROOT = root
rt.globals().UNIT_FILES = rt.table_from(sorted(glob.glob(os.path.join(root, "game/units/*.lua"))))
try: rt.execute(open(os.path.join(root, "tools/test_stats.lua")).read())
except lupa.LuaError as e: sys.exit(str(e))
