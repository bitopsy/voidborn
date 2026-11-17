--[[
  A radar chart panel for the dock: the radar of one statistic group (economy or combat) for every team, with a
  legend that ranks the teams by one headline figure.  vb_hud_econ.lua and vb_hud_army.lua are two thin widgets
  on top of this.  The numbers come from the dashboard (WG.VBStats), the placement from the dock (WG.VBDock).

    HudRadar.Install(widget, { id = "econ", title = "ECONOMY RADAR", radar = "economy", headline = "mi", open = "economy" })
]]
local HudRadar = {}
local okK, K = pcall(VFS.Include, "LuaUI/Headers/vb_dockui.h.lua")
local okD, D = pcall(VFS.Include, "LuaUI/Headers/vb_stats_draw.h.lua")

local BODY_H = 150          -- dock units
local H_OPEN = K and (K.TITLE + BODY_H + 8) or 0

function HudRadar.Install(widget, cfg)
	if not (okK and okD and type(K) == "table" and type(D) == "table") then
		Spring.Echo("[VB] " .. cfg.title .. ": could not load its headers: " .. tostring(okK and D or K))
		return
	end
	local P = K.New(cfg.id, cfg.title)
	local C, lastClock = D.C, os.clock()

	local function Api() return WG and WG.VBStats end

	function widget:Initialize()
		if not (WG and WG.VBDock) then Spring.Echo("[VB] " .. cfg.title .. ": needs the Voidborn Dock widget (vb_dock)") end
	end

	function widget:DrawScreen()
		if Spring.IsGUIHidden and Spring.IsGUIHidden() then return end
		local x1, y1, x2, y2, S, folded = P:Frame(H_OPEN, K.TITLE)
		if not x1 then return end
		local api = Api()
		local ctx = api and api.Ctx and api.Ctx()
		local teams = ctx and ctx.all or {}
		local top = P:Title(x1, y2, x2, S, (#teams > 0 and not folded) and (#teams .. (#teams == 1 and " team" or " teams")) or nil)
		if folded then return end

		local now = os.clock()
		local mx, my = Spring.GetMouseState()
		local vsx, vsy = Spring.GetViewGeometry()
		D.S = S
		D.Stats = api and api.Stats
		D.BeginFrame(mx, my, vsx, vsy, math.min(0.1, now - lastClock))
		lastClock = now

		if #teams == 0 then
			K.Font.Text("waiting for the first statistics...", (x1 + x2) / 2, top - 40 * S, 9 * S, "oc", 0.55, 0.58, 0.65, 1)
			D.EndFrame()
			return
		end
		local Stats = api.Stats
		local def
		for _, r in ipairs(Stats.RADARS) do if r.id == cfg.radar then def = r end end
		if not def then D.EndFrame() return end

		-- the radar on the left
		local R = 54 * S
		local rcx, rcy = x1 + 86 * S, top - (BODY_H / 2 + 1) * S
		local axes = {}
		for _, id in ipairs(def.axes) do
			local m = Stats.M[id]
			axes[#axes + 1] = { label = def.hud[id] or m.label, fmt = function(v) return Stats.Format(m, v) end }
		end
		local rows = {}
		for _, t in ipairs(teams) do
			local vals = {}
			for k, id in ipairs(def.axes) do vals[k] = Stats.Value(t, id, ctx.idx[t.id]) end
			rows[#rows + 1] = { team = t, name = t.name, color = Stats.ViewColor(t), vals = vals, head = Stats.Value(t, cfg.headline, ctx.idx[t.id]) }
		end
		D.Radar(rcx, rcy, R, axes, rows, { small = true })
		P:Hit(x1 + 4 * S, y1 + 4 * S, x1 + 172 * S, top - 2 * S, function() if api.Open then api.Open(cfg.open) end end, "Open the " .. def.name:lower() .. " page of the dashboard")

		-- the legend on the right: teams ranked by the headline figure
		table.sort(rows, function(a, b) return a.head > b.head end)
		local lx1, lx2 = x1 + 176 * S, x2 - 8 * S
		local hm = Stats.M[cfg.headline]
		K.Font.Text(hm.label:upper(), lx2, top - 14 * S, 8 * S, "or", 0.5, 0.55, 0.65, 1)
		local rh, maxRows = 15 * S, 8
		local myAlly = Spring.GetMyAllyTeamID and Spring.GetMyAllyTeamID()
		for i = 1, math.min(#rows, maxRows) do
			local r = rows[i]
			local ry = top - 14 * S - i * rh
			if r.team.ally == myAlly then K.Box(lx1 - 2 * S, ry - 2 * S, lx2 + 2 * S, ry + rh - 3 * S, 0.85, 0.65, 0.2, 0.10) end
			K.Box(lx1, ry + 1 * S, lx1 + 4 * S, ry + rh - 4 * S, r.color[1], r.color[2], r.color[3], 0.95)
			local txt = Stats.Format(hm, r.head)
			local tw = D.MW(txt, 9 * S)
			D.Text(D.Fit(r.name, 9 * S, lx2 - lx1 - tw - 14 * S), lx1 + 8 * S, ry + 2 * S, 9 * S, "o", r.team.dead and C.faint or r.color)
			D.Mono(txt, lx2, ry + 2 * S, 9 * S, "or", C.text)
		end
		if #rows > maxRows then K.Font.Text("+" .. (#rows - maxRows) .. " more", lx1 + 8 * S, top - 14 * S - (maxRows + 1) * rh, 8 * S, "o", 0.5, 0.55, 0.65, 1) end
		D.EndFrame()
	end

	function widget:IsAbove(x, y) return P:IsAbove(x, y) end
	function widget:MousePress(x, y, b) return P:Press(x, y, b) end
	function widget:MouseMove(x, y) P:Move(x, y) end
	function widget:MouseRelease() P:Release() end
	function widget:GetTooltip(x, y) return P:Tip(x, y) end
end

return HudRadar
