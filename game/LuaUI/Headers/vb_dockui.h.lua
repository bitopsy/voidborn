--[[
  Panel kit for the widgets that live in the dock (see LuaUI/Widgets/vb_dock.lua): economy radar, army radar, unit census.

    local K = VFS.Include("LuaUI/Headers/vb_dockui.h.lua")
    local P = K.New("census", "UNIT CENSUS")
    ...
    function widget:DrawScreen()
        local x1, y1, x2, y2, S, folded = P:Frame(hOpen, hFolded)     -- dock units; nil = nothing to draw
        if not x1 then return end
        local top = P:Title(x1, y2, x2, S, "[3 units]")               -- title bar with the - / x buttons; returns the y below it
        if folded then return end
        P:Hit(rx1, ry1, rx2, ry2, function(x, y, button) end, "tooltip text")
        ...
    end
    widget:IsAbove / MousePress / MouseMove / MouseRelease / GetTooltip  ->  P:IsAbove / P:Press / P:Move / P:Release / P:Tip

  Every panel is self-contained: its own - (fold) and x (switch off) buttons, and a title bar that drags it to another slot.
]]
local K = {}
local okF, VBFont = pcall(VFS.Include, "LuaUI/Headers/vb_font.h.lua")
if not okF or type(VBFont) ~= "table" then
	VBFont = { Width = function(str, size) return #str * size * 0.6 end,
		Text = function(str, x, y, size, opts, r, g, b, a) gl.Color(r or 1, g or 1, b or 1, a or 1); gl.Text(str, x, y, size, opts or "o") end }
end
K.Font = VBFont
K.TITLE = 18                                  -- dock units
K.AMBER = { 0.85, 0.65, 0.2 }

function K.Box(x1, y1, x2, y2, r, g, b, a) gl.Color(r, g, b, a); gl.Rect(x1, y1, x2, y2) end
function K.Frame(x1, y1, x2, y2, r, g, b, a)
	gl.Color(r, g, b, a)
	gl.Rect(x1, y1, x2, y1 + 1); gl.Rect(x1, y2 - 1, x2, y2); gl.Rect(x1, y1, x1 + 1, y2); gl.Rect(x2 - 1, y1, x2, y2)
end
local function Inside(x, y, r) return x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4] end
function K.Dock() return WG and WG.VBDock end

function K.New(id, title)
	local P = { id = id, title = title, rect = nil, hits = {}, S = 1, folded = false }

	-- once per frame: tell the dock how tall the panel wants to be, ask where it goes
	function P:Frame(h1, h0)
		local Dock = K.Dock()
		self.hits = {}
		self.rect = nil
		if not Dock then return nil end
		if not Dock.IsOn(self.id) then Dock.Report(self.id, 0, 0); return nil end
		Dock.Report(self.id, h1, h0 or h1)
		local x1, y1, x2, y2, S, fold = Dock.Rect(self.id)
		if not x1 then return nil end
		self.rect = { x1, y1, x2, y2 }
		self.S = S
		self.folded = (fold or Dock.IsCollapsed(self.id)) and true or false
		K.Box(x1, y1, x2, y2, 0.06, 0.06, 0.09, 0.88)
		K.Frame(x1, y1, x2, y2, K.AMBER[1], K.AMBER[2], K.AMBER[3], 0.9)
		return x1, y1, x2, y2, S, self.folded
	end

	-- a clickable area of this frame; the last one registered wins
	function P:Hit(x1, y1, x2, y2, fn, tip) self.hits[#self.hits + 1] = { x1, y1, x2, y2, fn = fn, tip = tip } end

	function P:Button(x1, y1, x2, y2, label, size, fn, tip, active)
		local mx, my = Spring.GetMouseState()
		local over = mx >= x1 and mx <= x2 and my >= y1 and my <= y2
		if active then K.Box(x1, y1, x2, y2, 0.85, 0.65, 0.2, 0.30) else K.Box(x1, y1, x2, y2, 0.14, 0.12, 0.2, over and 1 or 0.85) end
		K.Frame(x1, y1, x2, y2, K.AMBER[1], K.AMBER[2], K.AMBER[3], over and 0.95 or 0.5)
		VBFont.Text(label, (x1 + x2) / 2, (y1 + y2) / 2 - size * 0.35, size, "oc", 1, 0.95, 0.8, 1)
		self:Hit(x1, y1, x2, y2, fn, tip)
	end

	-- the title bar: drag handle, a tag on the right (e.g. "[3 units]"), the - / + and x buttons
	function P:Title(x1, y2, x2, S, tag)
		local Dock = K.Dock()
		local th = K.TITLE * S
		local fs = 10 * S
		K.Box(x1 + 1, y2 - th, x2 - 1, y2 - 1, 0.14, 0.12, 0.2, 1)
		VBFont.Text(self.title, x1 + 6 * S, y2 - th + th * 0.28, fs, "o", 0.9, 0.85, 0.7, 1)
		local bx2 = x2 - 1
		local function Btn(label, fn, tip)
			self:Button(bx2 - th, y2 - th, bx2, y2 - 1, label, 11 * S, fn, tip)
			bx2 = bx2 - th - 1
		end
		Btn("x", function() Dock.SetOn(self.id, false) end, "Switch off (back on: dashboard > SETTINGS, or /vbdock " .. self.id .. ")")
		Btn(self.folded and "+" or "-", function() Dock.ToggleCollapsed(self.id) end, self.folded and "Expand" or "Minimize")
		if tag then
			local tw = VBFont.Width(tag, 9 * S)
			VBFont.Text(tag, bx2 - 4 * S, y2 - th + th * 0.3, 9 * S, "or", 0.65, 0.9, 1, 1)
			bx2 = bx2 - tw - 8 * S
		end
		self:Hit(x1, y2 - th, bx2, y2 - 1, function(x, y) Dock.BeginDrag(self.id, x, y); self.dragging = true end, "Drag to another slot of the column")
		return y2 - th
	end

	function P:IsAbove(x, y) return self.rect ~= nil and Inside(x, y, self.rect) end
	function P:Press(x, y, button)
		if not self.rect or not Inside(x, y, self.rect) then return false end
		if button == 1 then
			for i = #self.hits, 1, -1 do
				local h = self.hits[i]
				if Inside(x, y, h) then if h.fn then h.fn(x, y, button) end return true end
			end
		end
		return true
	end
	function P:Move(x, y) local Dock = K.Dock(); if self.dragging and Dock then Dock.DragMove(x, y) end end
	function P:Release() local Dock = K.Dock(); if self.dragging and Dock then Dock.DragEnd() end self.dragging = false end
	function P:Tip(x, y)
		if not self.rect or not Inside(x, y, self.rect) then return nil end
		for i = #self.hits, 1, -1 do local h = self.hits[i]; if Inside(x, y, h) then return h.tip end end
	end
	return P
end

return K
