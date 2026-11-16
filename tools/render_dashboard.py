#!/usr/bin/env python3
"""Render the dashboard on the mock engine to PNG files (a way to look at the layout without the game).
   python3 tools/render_dashboard.py OUTDIR [teams=2] [minutes=30] [WxH=1920x1080]     needs lupa, pillow, playwright"""
import os, sys, glob, html
import lupa
from lupa import lua51 as L
from PIL import ImageFont
root = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/vb_dash"
teams = int(sys.argv[2]) if len(sys.argv) > 2 else 2
minutes = int(sys.argv[3]) if len(sys.argv) > 3 else 30
W, H = map(int, (sys.argv[4] if len(sys.argv) > 4 else "1920x1080").split("x"))
os.makedirs(out, exist_ok=True)
fonts = {"glyph": os.path.join(root, "game/fonts/VoidbornGlyph.ttf"), "mono": os.path.join(root, "game/fonts/VoidbornMono.ttf")}
pil = {k: ImageFont.truetype(v, 64) for k, v in fonts.items()}
rt = L.LuaRuntime(unpack_returned_tuples=True)
g = rt.globals()
g.ROOT = root
g.UNIT_FILES = rt.table_from(sorted(glob.glob(os.path.join(root, "game/units/*.lua"))))
g.py_measure = lambda kind, s: pil["mono" if kind == "mono" else "glyph"].getlength(s) / 64.0
rt.execute("Sim = dofile(ROOT .. '/tools/vb_sim.lua'); Sim.Mock.measure = py_measure")
rt.execute(f"R = Sim.run{{ teams = {teams}, minutes = {minutes}, seed = 3 }}; Sim.Mock.world.vsx, Sim.Mock.world.vsy = {W}, {H}")
# the glyph font draws lower case as capitals, so measuring the text as typed is right

def svg(ops):
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}"><rect width="{W}" height="{H}" fill="#0a0d14"/>']
    def col(c):
        return f"rgb({int(c[1]*255)},{int(c[2]*255)},{int(c[3]*255)})", c[4]
    for op in ops.values():
        k = op[1]
        if k == "rect":
            c, a = col(op[2]); x1, y1, x2, y2 = op[3], op[4], op[5], op[6]
            o.append(f'<rect x="{min(x1,x2):.1f}" y="{H-max(y1,y2):.1f}" width="{abs(x2-x1):.1f}" height="{abs(y2-y1):.1f}" fill="{c}" fill-opacity="{a:.3f}"/>')
        elif k == "poly":
            c, a = col(op[2]); mode = op[3]; w = op[4]; vt = op["v"]; v = [vt[i] for i in range(1, len(vt) + 1)]
            pts = [(v[i], H - v[i + 1]) for i in range(0, len(v), 2)]
            if not pts: continue
            P = lambda ps: " ".join(f"{x:.1f},{y:.1f}" for x, y in ps)
            if mode == "LINES":
                for i in range(0, len(pts) - 1, 2):
                    o.append(f'<line x1="{pts[i][0]:.1f}" y1="{pts[i][1]:.1f}" x2="{pts[i+1][0]:.1f}" y2="{pts[i+1][1]:.1f}" stroke="{c}" stroke-opacity="{a:.3f}" stroke-width="{max(w,1)}"/>')
            elif mode in ("LINE_STRIP", "LINE_LOOP"):
                tag = "polygon" if mode == "LINE_LOOP" else "polyline"
                o.append(f'<{tag} points="{P(pts)}" fill="none" stroke="{c}" stroke-opacity="{a:.3f}" stroke-width="{max(w,1)}" stroke-linejoin="round"/>')
            elif mode == "TRIANGLES":
                for i in range(0, len(pts) - 2, 3): o.append(f'<polygon points="{P(pts[i:i+3])}" fill="{c}" fill-opacity="{a:.3f}"/>')
            elif mode == "TRIANGLE_FAN":
                for i in range(1, len(pts) - 1): o.append(f'<polygon points="{P([pts[0], pts[i], pts[i+1]])}" fill="{c}" fill-opacity="{a:.3f}"/>')
            elif mode == "TRIANGLE_STRIP":
                for i in range(len(pts) - 2): o.append(f'<polygon points="{P(pts[i:i+3])}" fill="{c}" fill-opacity="{a:.3f}"/>')
        elif k == "text":
            c, a = col(op[2]); s, x, y, size, opts, kind = op[3], op[4], op[5], op[6], op[7], op[8]
            anchor = "middle" if "c" in opts else ("end" if "r" in opts else "start")
            fam = "VBMono" if kind == "mono" else "VBGlyph"
            o.append(f'<text x="{x:.1f}" y="{H-y-size*0.22:.1f}" font-family="{fam}" font-size="{size:.1f}" text-anchor="{anchor}" fill="{c}" fill-opacity="{a:.3f}">{html.escape(s)}</text>')
    o.append("</svg>")
    return "\n".join(o)

from playwright.sync_api import sync_playwright
css = "".join(f"@font-face{{font-family:{n};src:url('file://{fonts[k]}')}}" for n, k in (("VBGlyph", "glyph"), ("VBMono", "mono")))
shots = [("hud", "close", None)] + [(t, t, None) for t in ("overview", "graphs", "economy", "combat", "army", "report", "settings", "keys", "about")] + [("overview_cursor", "overview", 12)]
fogdone = [False]
shots += [("fog_hud", "close", None, "fog"), ("fog_overview", "overview", None, "fog")]
with sync_playwright() as p:
    b = p.chromium.launch(); pg = b.new_page(viewport={"width": W, "height": H})
    for shot in shots:
        name, tab, cursor = shot[:3]
        if len(shot) > 3 and not fogdone[0]:
            rt.execute(f"R = Sim.run{{ teams = {teams}, minutes = {minutes}, stopAt = 14, seed = 5 }}; Sim.Mock.world.vsx, Sim.Mock.world.vsy = {W}, {H}; Sim.Mock.world.fog = true; R.widget:Update(2)")
            fogdone[0] = True
        rt.execute("W = R.widget")
        if tab == "close": rt.execute("W:TextCommand('vbdash close')")
        else: rt.execute(f"W:TextCommand('vbdash tab {tab}')")
        if cursor: rt.execute(f"for i = 1, {cursor} do W:KeyPress(276, {{}}, false) end")
        else: rt.execute("W:KeyPress(279, {}, false)")
        rt.execute("Sim.Mock.world.mx, Sim.Mock.world.my = 1000, 600; Sim.Mock.ops = {}; W:DrawScreen()")
        ops = rt.eval("Sim.Mock.ops")
        hp = os.path.join(out, "_page.html")
        open(hp, "w").write(f"<style>{css}body{{margin:0;background:#000}}</style>" + svg({i: ops[i] for i in range(1, len(ops) + 1)}))
        pg.goto("file://" + hp)
        pg.evaluate("document.fonts.ready")
        pg.wait_for_timeout(400)
        pg.screenshot(path=os.path.join(out, f"{name}.png"))
        print(name, len(ops), "ops")
    b.close()
