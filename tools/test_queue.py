#!/usr/bin/env python3
"""Runs tools/test_queue.lua against the queue gadget with a mock engine.   pip install lupa"""
import os, sys, lupa
try:
    from lupa import lua51 as _L   # the engine runs Lua 5.1
except ImportError:
    _L = lupa
root = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
rt = _L.LuaRuntime()
g = rt.globals()
g.GADGET = os.path.join(root, "game/LuaRules/Gadgets/vb_dev_queue.lua")
g.HDR = os.path.join(root, "game/LuaRules/Headers/vb_cost.h.lua")
try:
    rt.execute(open(os.path.join(root, "tools/test_queue.lua")).read())
except lupa.LuaError as e:
    sys.exit(str(e))
