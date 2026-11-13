function widget:GetInfo()
	return { name = "Voidborn Memory Graph", desc = "Dotted histogram of Lua memory consumption over time (widget / Spring engine / Lua heap)",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = 12, enabled = false,
		handler = true }  -- needs the real widgetHandler to list the active widgets
end

--------------------------------------------------------------------------------
-- A dotted time-series of the Lua memory usage.
--   cyan   = memory held by the widgets
--   orange = memory held by the Spring engine's own Lua tables
--   white  = the total Lua heap (collectgarbage("count"))
-- The graph auto-scales to the peak of the visible window.
--------------------------------------------------------------------------------

local REFRESH   = 1.5                     -- seconds between samples
local HIST_LEN  = 120                     -- samples kept (3 minutes)
local HIST_MAX  = 4 * 1024 * 1024         -- full-scale for the per-widget bars
local NODE_CAP  = 200000                  -- safety cap on objects visited per widget

local show      = true    -- the widget itself is disabled by default (see GetInfo)
local big       = false
local history   = {}
local histPos   = 0
local histFill  = 0
local timer     = nil
local widgetMem = {}
local skipSet   = nil

local function FmtBytes(n)
  if (n < 1024) then return string.format("%d B", n) end
  if (n < 1048576) then return string.format("%.1f KB", n / 1024) end
  return string.format("%.2f MB", n / 1048576)
end

-- Spring's LuaGL has no gl.Point(): points are drawn with
--   gl.BeginEnd(GL.POINTS, gl.Vertex, x, y)
local function DrawDots(pts, r, g, b, a, size)
  if (#pts == 0) then return end
  gl.Color(r, g, b, a)
  gl.PointSize(size or 2)
  for i = 1, #pts do
    gl.BeginEnd(GL.POINTS, gl.Vertex, pts[i][1], pts[i][2])
  end
  gl.PointSize(1)
end

local function BuildSkipSet()
  local skip = {}
  skip[_G] = true
  local sys = _G.System
  if (type(sys) == "table") then
    skip[sys] = true
    for _, v in pairs(sys) do
      local t = type(v)
      if (t == "table" or t == "function") then skip[v] = true end
    end
  end
  if (type(widgetHandler.WG) == "table") then skip[widgetHandler.WG] = true end
  skip[widgetHandler] = true
  return skip
end

-- Estimate the live Lua data a widget keeps (its tables, strings and closures).
local function EstimateBytes(root, skip)
  local getmt, nxt, tp = getmetatable, next, type
  local getup = debug and debug.getupvalue
  local getinfo = debug and debug.getinfo
  local seen = { [root] = true }
  local stack, sp = { root }, 1
  local bytes, nodes = 0, 0

  local function Push(v)
    local t = tp(v)
    if (t == "string") then
      if (not seen[v]) then seen[v] = true; bytes = bytes + 24 + #v end
    elseif (t == "table" or t == "function") then
      if (not seen[v] and not skip[v]) then
        seen[v] = true
        sp = sp + 1; stack[sp] = v
      end
    end
  end

  while (sp > 0 and nodes < NODE_CAP) do
    local o = stack[sp]; stack[sp] = nil; sp = sp - 1
    nodes = nodes + 1
    if (tp(o) == "table") then
      local narr, nhash = #o, 0
      if (getmt(o) == nil) then
        for k, v in nxt, o do
          nhash = nhash + 1
          Push(k); Push(v)
        end
      else
        for _ in nxt, o do nhash = nhash + 1 end
      end
      bytes = bytes + 40 + 16 * narr + 32 * math.max(0, nhash - narr)
    else
      local isLua = true
      if (getinfo) then
        local info = getinfo(o, "S")
        isLua = info and info.what ~= "C"
      end
      if (isLua) then
        bytes = bytes + 32
        if (getup) then
          local i = 1
          while (true) do
            local name, val = getup(o, i)
            if (name == nil) then break end
            bytes = bytes + 8
            Push(val)
            i = i + 1
          end
        end
      end
    end
  end
  return bytes
end

-- Memory of the Spring engine's own Lua tables (shared, non-widget).
local function EstimateSpringEngineMemory()
  local total = 0
  local function Charge(t)
    if (type(t) ~= "table") then return end
    total = total + 40
    for k, v in pairs(t) do
      total = total + 32
      if (type(k) == "string") then total = total + #k end
      if (type(v) == "string") then total = total + #v end
    end
  end
  for _, name in ipairs({ "Spring", "SpringLua", "WG", "UnitDefs", "WeaponDefs" }) do
    local t = _G[name]
    if (type(t) == "table") then Charge(t) end
  end
  return total
end

local function Sample()
  -- widgetHandler.knownWidgets does not exist yet while the widgets are being
  -- initialised, so bail out until it is there.
  local wh = widgetHandler
  if (type(wh) ~= "table" or type(wh.knownWidgets) ~= "table") then return end
  skipSet = skipSet or BuildSkipSet()
  local mem = 0
  for name, data in pairs(wh.knownWidgets) do
    if (data and data.active) then
      local w = wh:FindWidget(name)
      if (w) then
        local ok, b = pcall(EstimateBytes, w, skipSet)
        widgetMem[name] = ok and b or 0
        mem = mem + widgetMem[name]
      end
    else
      widgetMem[name] = nil
    end
  end
  local spring = EstimateSpringEngineMemory()
  local heap = collectgarbage("count") * 1024
  histPos = (histPos % HIST_LEN) + 1
  history[histPos] = { mem, spring, heap }
  if histFill < HIST_LEN then histFill = histFill + 1 end
  return mem, spring, heap
end

local function HistorySample(i)
  if (histFill == 0) then return nil end
  local idx = histPos - histFill + 1 + i
  while (idx < 1) do idx = idx + HIST_LEN end
  while (idx > HIST_LEN) do idx = idx - HIST_LEN end
  return history[idx]
end

function widget:Initialize()
  Spring.Echo("[VB] Memory graph widget loaded - /vbmem toggles it, /vbmem big makes it large")
  if widgetHandler and widgetHandler.AddAction then
    widgetHandler:AddAction("vbmem", function(cmd)
      if cmd == "big" then big = not big
      elseif cmd == "off" then show = false
      elseif cmd == "on" then show = true
      else show = not show end
      return true
    end, nil, "v")
  end
end

function widget:TextCommand(cmd)
  if cmd == "vbmem" then
    local _, _, arg = string.match(cmd, "^(%S+)%s+(%S+)%s*$")
    if arg == "big" then big = not big
    elseif arg == "off" then show = false
    elseif arg == "on" then show = true
    else show = not show end
    Spring.Echo("[VB] memory graph: " .. (show and "on" or "off") .. (big and " (large)" or ""))
    return true
  end
end

function widget:Update()
  -- do not sample until the game is actually running and the widget list exists
  if (Spring.GetGameFrame() < 60) then return end
  local now = Spring.GetTimer()
  if (timer and Spring.DiffTimers(now, timer) < REFRESH) then return end
  timer = now
  local ok, err = pcall(Sample)
  if (not ok) then
    timer = nil
    Spring.Echo("[VB] memgraph sample error: " .. tostring(err))
  end
end

function widget:DrawScreen()
  if (not show) then return end
  if (histFill < 2) then return end

  local vsx, vsy = Spring.GetViewGeometry()
  local w = big and 520 or 250
  local h = big and 190 or 100
  local x2 = vsx - 14
  local y1 = 14
  local x1 = x2 - w
  local y2 = y1 + h

  -- panel
  gl.Color(0.04, 0.04, 0.07, 0.90)
  gl.Rect(x1, y1, x2, y2)
  gl.Color(0.85, 0.65, 0.2, 0.9)
  gl.LineWidth(1)
  gl.Shape(GL.LINE_LOOP, { { v = { x1, y1 } }, { v = { x2, y1 } },
                            { v = { x2, y2 } }, { v = { x1, y2 } } })
  gl.LineWidth(1)

  gl.BeginText()
  gl.Text("MEMORY OVER TIME", x1 + 6, y2 - 12, 10, "o")
  gl.Text("white = lua heap    orange = spring engine    cyan = widgets",
          x1 + 6, y1 + 3, 8, "o")
  gl.EndText()

  -- auto-scale to the peak of the visible window
  local peak = 64 * 1024
  for i = 0, histFill - 1 do
    local s = HistorySample(i)
    if s then
      local tot = s[1] + s[2]
      if tot > peak then peak = tot end
      if s[3] > peak then peak = s[3] end
    end
  end
  peak = peak * 1.12

  local plotTop = y2 - 24
  local plotBot = y1 + 14
  local plotH = plotBot - plotTop
  local n = histFill

  local function Series(getter, r, g, b)
    local pts = {}
    for i = 0, n - 1 do
      local s = HistorySample(i)
      if s then
        local v = getter(s)
        local px = x1 + 6 + (w - 12) * (i / math.max(1, n - 1))
        local py = plotBot - plotH * math.min(1, v / peak)
        pts[#pts + 1] = { px, py }
      end
    end
    DrawDots(pts, r, g, b, 0.95, 2)
  end

  Series(function(s) return s[3] end, 1.0, 1.0, 1.0, 0.85)
  Series(function(s) return s[2] end, 1.0, 0.65, 0.15, 0.9)
  Series(function(s) return s[1] end, 0.0, 0.85, 1.0, 0.95)

  -- current values + peak label
  local last = HistorySample(histFill - 1)
  gl.BeginText()
  if (last) then
    gl.Text("widgets " .. FmtBytes(last[1]), x1 + 6, plotBot + 2, 9, "o")
    gl.Text("spring " .. FmtBytes(last[2]), x1 + 90, plotBot + 2, 9, "o")
    gl.Text("heap " .. FmtBytes(last[3]), x1 + 168, plotBot + 2, 9, "o")
  end
  gl.Text("peak " .. FmtBytes(peak), x2 - 6, y2 - 12, 9, "or")
  gl.EndText()
end
