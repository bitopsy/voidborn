#!/usr/bin/env python3
"""Smoke test of the crater gadget and census drawer with a mock engine.   pip install lupa"""
import os, sys, lupa
try:
    from lupa import lua51 as _L   # the engine runs Lua 5.1
except ImportError:
    _L = lupa
root = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
rt = _L.LuaRuntime(); rt.globals().ROOT = root
try: rt.execute(open(os.path.join(root, "tools/test_crater_census.lua")).read())
except lupa.LuaError as e: sys.exit(str(e))
