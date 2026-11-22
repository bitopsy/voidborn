#!/usr/bin/env python3
"""Runs tools/test_t3.lua against the Tier 2 -> Tier 3 upgrade of the factory upgrade gadget with a mock engine.   pip install lupa"""
import os, sys, lupa
try:
    from lupa import lua51 as _L
except ImportError:
    _L = lupa
root = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
rt = _L.LuaRuntime()
rt.globals().GADGET = os.path.join(root, "game/LuaRules/Gadgets/vb_factory_upgrade.lua")
try:
    rt.execute(open(os.path.join(root, "tools/test_t3.lua")).read())
except lupa.LuaError as e:
    sys.exit(str(e))
