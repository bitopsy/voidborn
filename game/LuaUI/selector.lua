--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  file:    selector.lua
--  brief:   the widget selector, loads and unloads widgets
--  author:  goddot info@bitopsy.com
--
--  Copyright (C) 2007.
--  Licensed under the terms of the GNU GPL, v2 or later.
--
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- changes:
--   jK (April@2009) - updated to new font system
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function widget:GetInfo()
  return {
    name      = "WidgetSelector",
    desc      = "Widget selection widget",
    author    = "goddot info@bitopsy.com",
    license   = "GNU GPL, v2 or later",
    layer     = -9,
    handler   = true, --  needs the real widgetHandler
    enabled   = true  --  loaded by default?
  }
end

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------

include("colors.h.lua")
include("keysym.h.lua")
include("fonts.lua")


local floor = math.floor

local widgetsList = {}        -- the visible slice (scrolled)
local fullWidgetsList = {}     -- every display row: category headers + widget entries
local entriesAll = {}          -- every widget entry { name, data, category }, sorted; no headers
local collapsed = {}           -- category name -> true when folded up (click its header)

local vsx, vsy = widgetHandler:GetViewSizes()

local maxEntries = 20
local startEntry = 1
local pageStep  = math.floor(maxEntries / 2) - 1

local fontSize = 11
local fontSpace = 5
local yStep = fontSize + fontSpace

local entryFont  = "LuaUI/Fonts/FreeMonoBold_12"
local headerFont  = "LuaUI/Fonts/FreeMonoBold_12"
--local headerFont = "LuaUI/Fonts/FreeMonoBold_16"
--local entryFont  = "LuaUI/Fonts/mephisto_12"
--local entryFont  = "LuaUI/Fonts/VeraMoBd_12"
--local entryFont  = "LuaUI/Fonts/fragileb_16"
--local entryFont  = "LuaUI/Fonts/edenmb___16"
--local headerFont = "LuaUI/Fonts/abaddon_22"
if (1 > 0) then
  entryFont  = ":n:" .. entryFont
  headerFont = ":n:" .. headerFont
end


local nameW   = 0      -- pixel width of the NAME column
local errW    = 0      -- pixel width of the ERROR column (0 = no widget has an error, column hidden)
local errCount = 0
local hdrTop  = 0      -- top of the table header strip
local xName, xHist, xMemR, xTrend, xSizeR, xErr = 0, 0, 0, 0, 0, 0   -- column anchors (set by UpdateGeometry)
local trendW  = 0          -- pixel width of the OVER TIME column (measured once, needs the font)
local borderx = yStep * 0.75
local bordery = yStep * 0.75

local midx = vsx * 0.5
local minx = vsx * 0.4
local maxx = vsx * 0.6
local midy = vsy * 0.5
local miny = vsy * 0.4
local maxy = vsy * 0.6

local sbposx = 0.0
local sbposy = 0.0
local sbsizex = 0.0
local sbsizey = 0.0
local sby1 = 0.0
local sby2 = 0.0
local sbsize = 0.0
local sbheight = 0.0
local activescrollbar = false
local scrollbargrabpos = 0.0

-------------------------------------------------------------------------------

local selectorOpen = false          -- true only while the selector is loaded/active (F11 open)

function widget:Initialize()
  widgetHandler.knownChanged = true
  selectorOpen = true
  Spring.Echo("[VB] WidgetSelector loaded (categories, size, memory histogram + ASCII memory-over-time, error column)")
end


-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Per-widget size and memory columns
--   size   = bytes of the widget's source file (recorded by widgets.lua when it loads the file)
--   memory = ESTIMATE of the live Lua data an ACTIVE widget keeps: its tables, strings and closures
--            (walked from the widget table). Engine/shared tables (Spring, gl, UnitDefs, WG, ...) are
--            not charged to any widget, and compiled bytecode is not included. Refreshed every 1.5 s
--            while this selector is open; it costs nothing when the selector is closed.
-------------------------------------------------------------------------------

local COL_SIZE_W = 64         -- pixel widths of the right-hand columns
local COL_MEM_W  = 80
local COL_GAP    = 14
local NAME_INDENT = 12          -- widget names sit this far in under their category header

-- ASCII memory-over-time, one character per sample (taken every MEM_REFRESH seconds, and ONLY while
-- this selector is open: the history starts empty each time you press F11).
-- Each widget is scaled between its own lowest and highest sample:  .  :  -  =  +  #
-- A flat widget stays on ".", a leaking one climbs. Orange = growing, green = shrinking.
local TREND_LEN  = 16
local TREND_RAMP = { ".", ":", "-", "=", "+", "#" }

-- dotted histogram: HIST_DOTS dots, each DOT_SZ px square, DOT_STEP px apart
local HIST_DOTS  = 20
local DOT_SZ     = 3
local DOT_STEP   = 5
local HIST_W     = HIST_DOTS * DOT_STEP - (DOT_STEP - DOT_SZ)
local HIST_LOG   = true           -- true: log scale (small widgets stay visible), false: linear
local ERR_MAX_W  = 440            -- widest the ERROR column may grow (px); longer text is cut with "..."

local MEM_REFRESH   = 1.5     -- seconds between estimates
local MEM_NODE_CAP  = 200000  -- safety cap on objects visited per widget

local memBytes   = {}         -- widget name -> estimated bytes (active widgets only)
local widgetHist = {}         -- widget name -> last TREND_LEN samples (bytes)
local trendText  = {}         -- widget name -> the ASCII string drawn in the OVER TIME column
local trendCol   = {}         -- widget name -> its colour escape
local memTimer   = nil
local totals     = { active = 0, src = 0, mem = 0, springMem = 0, maxMem = 0 }
local skipSet    = nil

local function FmtBytes(n)
  if (n < 1024) then return string.format("%d B", n) end
  if (n < 1048576) then return string.format("%.1f KB", n / 1024) end
  return string.format("%.2f MB", n / 1048576)
end

-- Spring's LuaGL has no gl.Point(): points are drawn with
--   gl.BeginEnd(GL.POINTS, gl.Vertex, x, y)
-- Calling a missing function inside DrawScreen aborts the whole widget, which is
-- why the histogram never showed up.
local function DrawDots(pts, r, g, b, a, size)
  if (#pts == 0) then return end
  gl.Color(r, g, b, a)
  gl.PointSize(size or 2)
  for i = 1, #pts do
    gl.BeginEnd(GL.POINTS, gl.Vertex, pts[i][1], pts[i][2])
  end
  gl.PointSize(1)
end

-- Fraction (0..1) of the histogram a widget fills, relative to the heaviest active widget.
local function MemFraction(b)
  if (not b or b <= 0) then return 0 end
  local top = math.max(totals.maxMem or 0, 64 * 1024)
  if (HIST_LOG) then
    return math.min(1, math.log(1 + b / 1024) / math.log(1 + top / 1024))
  end
  return math.min(1, b / top)
end

-- ---------------------------------------------------------------------------
-- errors: runtime errors (widgetHandler.widgetErrors, by widget name) and load
-- failures (widgetHandler.failedWidgets, by file name) recorded by widgets.lua
-- ---------------------------------------------------------------------------
local function GetWidgetError(name, data)
  local e = widgetHandler.widgetErrors and widgetHandler.widgetErrors[name]
  if (e) then return e.msg, e.where end
  local f = data.filename and widgetHandler.failedWidgets and widgetHandler.failedWidgets[data.filename]
  if (f) then return f.msg, "load" end
  return nil
end

local errTextCache = {}
local function ErrorText(msg, where)          -- single line, short paths, "[CallIn]" prefix
  local key = (where or "") .. "|" .. msg
  local c = errTextCache[key]
  if (c) then return c end
  local t = tostring(msg)
  t = t:match("^[^\n]*") or t
  t = t:gsub("LuaUI/[%w_/%-%.]-/", "")
  if (where and where ~= "load") then t = "[" .. where .. "] " .. t end
  errTextCache[key] = t
  return t
end

local errMeasure = {}
local fitCache, fitCacheW = {}, -1
local function FitError(text)                 -- cut to the ERROR column width
  if (fitCacheW ~= errW) then fitCache = {}; fitCacheW = errW end
  local c = fitCache[text]
  if (c) then return c end
  local out = text
  if (fontSize * gl.GetTextWidth(out) > errW) then
    local charW = math.max(1, fontSize * gl.GetTextWidth("M"))
    local n = math.max(4, math.floor(errW / charW))
    out = text:sub(1, n - 3) .. "..."
  end
  fitCache[text] = out
  return out
end

-- ---------------------------------------------------------------------------
-- memory history (over time): a ring buffer of samples taken every MEM_REFRESH
-- ---------------------------------------------------------------------------
local MEM_HIST_LEN = 120                 -- samples kept (120 * 1.5 s = 3 minutes)
local memHistory  = {}                   -- ring buffer
local memHistPos  = 0
local memHistFill = 0

local function PushHistory(widgetMem, springMem, heap)
  memHistPos = (memHistPos % MEM_HIST_LEN) + 1
  memHistory[memHistPos] = { widgetMem or 0, springMem or 0, heap or 0 }
  if memHistFill < MEM_HIST_LEN then memHistFill = memHistFill + 1 end
end

-- Sample i (0 = oldest kept, memHistFill-1 = newest) -> { w, s, h }
local function HistorySample(i)
  if (memHistFill == 0) then return nil end
  local idx = memHistPos - memHistFill + 1 + i
  while (idx < 1) do idx = idx + MEM_HIST_LEN end
  while (idx > MEM_HIST_LEN) do idx = idx - MEM_HIST_LEN end
  return memHistory[idx]
end

-- Draw the memory-over-time graph (dotted lines) in the bottom-right corner.
local function DrawMemGraph()
  if (not selectorOpen or memHistFill < 1) then return end
  local w, h = 240, 96
  local x1 = vsx - w - 16
  local y1 = 26
  local x2, y2 = x1 + w, y1 + h

  -- panel
  gl.Color(0.04, 0.04, 0.07, 0.88)
  gl.Rect(x1, y1, x2, y2)
  gl.Color(0.85, 0.65, 0.2, 0.8)
  gl.LineWidth(1)
  gl.Shape(GL.LINE_LOOP, { { v = { x1, y1 } }, { v = { x2, y1 } },
                            { v = { x2, y2 } }, { v = { x1, y2 } } })

  gl.BeginText()
  gl.Text("MEMORY OVER TIME", x1 + 6, y2 - 12, 10, "o")
  gl.EndText()

  -- find the peak of the plotted series so the graph auto-scales
  local peak = 1
  for i = 0, memHistFill - 1 do
    local s = HistorySample(i)
    if s then
      local tot = s[1] + s[2]
      if tot > peak then peak = tot end
      if s[3] > peak then peak = s[3] end
    end
  end
  peak = math.max(peak * 1.15, 64 * 1024)

  local plotTop, plotBot = y2 - 22, y1 + 12
  local plotH = plotBot - plotTop
  local n = memHistFill

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

  -- total Lua heap (white), Spring engine tables (orange), widget memory (cyan)
  Series(function(s) return s[3] end, 1.0, 1.0, 1.0, 0.9)
  Series(function(s) return s[2] end, 1.0, 0.65, 0.15, 0.9)
  Series(function(s) return s[1] end, 0.0, 0.85, 1.0, 0.95)

  -- scale label
  gl.BeginText()
  gl.Text("peak " .. FmtBytes(peak), x2 - 6, y1 + 4, 9, "or")
  gl.Text("white=lua heap  orange=spring  cyan=widgets", x1 + 6, y1 + 4, 8, "o")
  gl.EndText()
end

-- Estimate the memory of the Spring engine's own (non-widget) Lua tables.
-- These are shared globals such as Spring, UnitDefs and WeaponDefs.
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
  local engineTables = { "Spring", "SpringLua", "WG", "UnitDefs", "WeaponDefs" }
  for _, name in ipairs(engineTables) do
    local t = _G[name]
    if (type(t) == "table") then Charge(t) end
  end
  return total
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

  while (sp > 0 and nodes < MEM_NODE_CAP) do
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
        -- tables with a metatable are engine-provided views (unit defs and the like): charge the shell only
        for _ in nxt, o do nhash = nhash + 1 end
      end
      bytes = bytes + 40 + 16 * narr + 32 * math.max(0, nhash - narr)
    else
      -- Lua closure: object header + upvalues (C functions are engine API, not widget memory)
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

-- record one sample for a widget and rebuild its ASCII trend string
local function PushWidgetHist(name, b)
  local h = widgetHist[name]
  if (not h) then h = {}; widgetHist[name] = h end
  h[#h + 1] = b
  if (#h > TREND_LEN) then table.remove(h, 1) end

  local lo, hi = h[1], h[1]
  for i = 2, #h do
    if (h[i] < lo) then lo = h[i] end
    if (h[i] > hi) then hi = h[i] end
  end
  local range = hi - lo
  local flat = range < math.max(1024, 0.03 * hi)       -- changes under ~1 KB / 3% are noise
  local chars = {}
  for i = 1, #h do
    local idx = 1
    if (not flat) then
      idx = 1 + floor((h[i] - lo) / range * (#TREND_RAMP - 1) + 0.5)
    end
    chars[i] = TREND_RAMP[idx]
  end
  trendText[name] = table.concat(chars)

  local first, last = h[1], h[#h]
  if (#h >= 3 and last - first > math.max(2048, 0.10 * first)) then
    trendCol[name] = '\255\255\176\080'      -- growing: orange
  elseif (#h >= 3 and first - last > math.max(2048, 0.10 * first)) then
    trendCol[name] = '\255\128\255\160'      -- shrinking: green
  else
    trendCol[name] = '\255\150\190\220'      -- steady
  end
end

local function RefreshMemory(force)
  local now = Spring.GetTimer()
  if (not force and memTimer and Spring.DiffTimers(now, memTimer) < MEM_REFRESH) then return end
  memTimer = now
  skipSet = skipSet or BuildSkipSet()
  local active, src, mem, top = 0, 0, 0, 0
  local myName = widget:GetInfo().name
  for name, data in pairs(widgetHandler.knownWidgets) do
    if (data.active) then
      local w = widgetHandler:FindWidget(name)
      if (w) then
        local ok, b = pcall(EstimateBytes, w, skipSet)
        memBytes[name] = ok and b or 0
        PushWidgetHist(name, memBytes[name])
        mem = mem + memBytes[name]
        if (name ~= myName and memBytes[name] > top) then top = memBytes[name] end
      end
      active = active + 1
      src = src + (data.size or 0)
    else
      memBytes[name] = nil
      widgetHist[name], trendText[name], trendCol[name] = nil, nil, nil
    end
  end
  local springMem = EstimateSpringEngineMemory()
  totals.active, totals.src, totals.mem = active, src, mem
  totals.maxMem = top
  totals.springMem = springMem
  PushHistory(mem, springMem, collectgarbage("count") * 1024)
end

-------------------------------------------------------------------------------
-- Categories
--   A widget can name its own:   GetInfo() return { ..., category = "Economy" }
--   (widgets.lua passes it through). Otherwise the category is guessed from the widget name,
--   then from its description, using the keyword rules below (first rule that matches wins).
--   Click a category header to fold it up / open it again.
-------------------------------------------------------------------------------
local CATEGORY_FAILED = "Failed to load"

local CATEGORY_RULES = {
  { "Developer",       { "developer", "console", "memory", "profil", "debug", "hello", "selector" } },
  { "Audio",           { "sound", "audio", "music", "voice" } },
  { "Economy",         { "reclaim", "metal", "mex", "energy", "resource", "economy", "income", "storage" } },
  { "Units",           { "unit", "factory", "forge", "census", "commander", "builder", "army" } },
  { "Info & Overlays", { "timeseries", "3d", "shape", "health", "sensor", "range", "radar", "overlay", "minimap", "graph" } },
  { "Interface",       { "panel", "dashboard", "hotkey", "setting", "tooltip", "hover", "menu", "button", "bar", "hud", "font" } },
}

local CATEGORY_ORDER = {
  [CATEGORY_FAILED] = 0, ["Economy"] = 1, ["Units"] = 2, ["Info & Overlays"] = 3,
  ["Interface"] = 4, ["Audio"] = 5, ["Developer"] = 6, ["Other"] = 99,
}

local CATEGORY_COLOR = {
  [CATEGORY_FAILED] = '\255\255\112\112',
  ["Economy"]         = '\255\255\224\112',
  ["Units"]           = '\255\255\168\128',
  ["Info & Overlays"] = '\255\196\168\255',
  ["Interface"]       = '\255\128\224\255',
  ["Audio"]           = '\255\144\255\176',
  ["Developer"]       = '\255\255\144\208',
  ["Other"]           = '\255\200\200\200',
}

local function CatRank(cat) return CATEGORY_ORDER[cat] or 50 end
local function CatColor(cat) return CATEGORY_COLOR[cat] or CATEGORY_COLOR["Other"] end

local function CategoryOf(name, data)
  if (data.failed) then return CATEGORY_FAILED end
  if (type(data.category) == "string" and data.category ~= "") then return data.category end
  local n = string.lower(name)
  for pass = 1, 2 do                                  -- pass 1: name only, pass 2: name + description
    local hay = (pass == 1) and n or (n .. " " .. string.lower(data.desc or ""))
    for _, rule in ipairs(CATEGORY_RULES) do
      for _, kw in ipairs(rule[2]) do
        if (string.find(hay, kw, 1, true)) then return rule[1] end
      end
    end
  end
  return "Other"
end

-- the header row of a category: how many are on, their memory, and their source size
local function HeaderRow(data, posy)
  local act, src, mem = 0, 0, 0
  for _, m in ipairs(data.members) do
    local md = m[2]
    if (md.active) then
      act = act + 1
      mem = mem + (memBytes[m[1]] or 0)
    end
    src = src + (md.size or 0)
  end
  return {
    y = posy, header = true, active = false,
    nameText = CatColor(data.category) .. (collapsed[data.category] and "[+] " or "[-] ") ..
               string.upper(data.category) .. '\255\160\160\160' ..
               string.format("   %d/%d on", act, #data.members),
    memText  = (act > 0) and ("~" .. FmtBytes(mem)) or "",
    memCol   = '\255\128\224\255',
    sizeText = FmtBytes(src),
    sizeCol  = CatColor(data.category),
  }
end

local function UpdateGeometry()
  midx  = vsx * 0.5
  midy  = vsy * 0.5

  -- width of the OVER TIME column: TREND_LEN of the widest ramp character
  if (trendW == 0) then
    trendW = floor(fontSize * gl.GetTextWidth(string.rep("#", TREND_LEN))) + 2
  end

  -- width wanted by the ERROR column (only exists while some widget has an error)
  local want = 0
  errCount = 0
  for _, nd in ipairs(entriesAll) do
    local m, where = GetWidgetError(nd[1], nd[2])
    if (m) then
      errCount = errCount + 1
      local t = ErrorText(m, where)
      local ew = errMeasure[t]
      if (not ew) then ew = fontSize * gl.GetTextWidth(t); errMeasure[t] = ew end
      if (ew > want) then want = ew end
    end
  end

  local fixed = nameW + COL_GAP + HIST_W + COL_GAP + COL_MEM_W + COL_GAP + trendW + COL_GAP + COL_SIZE_W
  local cap = math.min(ERR_MAX_W, vsx * 0.96 - 2 * borderx - fixed - 2 * COL_GAP)
  errW = (want > 0) and floor(math.max(120, math.min(want, cap))) or 0
  local inner = fixed + ((errW > 0) and (2 * COL_GAP + errW) or 0)

  minx = floor(midx - inner * 0.5 - borderx)
  maxx = floor(midx + inner * 0.5 + borderx)

  -- column anchors:  NAME | histogram + MEMORY (right-aligned) | OVER TIME | SIZE (right-aligned) | ERROR
  xName  = minx + borderx
  xHist  = xName + nameW + COL_GAP
  xMemR  = xHist + HIST_W + COL_GAP + COL_MEM_W
  xTrend = xMemR + COL_GAP
  xSizeR = xTrend + trendW + COL_GAP + COL_SIZE_W
  xErr   = xSizeR + 2 * COL_GAP

  local ySize = yStep * (#widgetsList)
  miny = floor(midy - (0.5 * ySize) - bordery - fontSize * 0.5)
  maxy = floor(midy + (0.5 * ySize) + bordery)
  hdrTop = maxy + yStep + 4
end


local function UpdateListScroll()
  local wCount = #fullWidgetsList
  local lastStart = wCount - maxEntries + 1
  if (lastStart < 1) then lastStart = 1 end
  if (startEntry > lastStart) then startEntry = lastStart end
  if (startEntry < 1) then startEntry = 1 end
  
  widgetsList = {}
  local se = startEntry
  local ee = se + maxEntries - 1
  local n = 1
  for i = se, ee do
    widgetsList[n],n = fullWidgetsList[i],n+1
  end
end


local function ScrollUp(step)
  startEntry = startEntry - step
  UpdateListScroll()
end


local function ScrollDown(step)
  startEntry = startEntry + step
  UpdateListScroll()
end


function widget:MouseWheel(up, value)
  local a,c,m,s = Spring.GetModKeyState()
  if (a or m) then
    return false  -- alt and meta allow normal control
  end
  local step = (s and 4) or (c and 1) or 2
  if (up) then
    ScrollUp(step)
  else
    ScrollDown(step)
  end
  return true
end


-- entries are { name, data, category }: by category (failed files first), mod widgets first, then by name
local function SortWidgetListFunc(nd1, nd2)
  local r1, r2 = CatRank(nd1[3]), CatRank(nd2[3])
  if (r1 ~= r2) then
    return r1 < r2
  end
  if (nd1[3] ~= nd2[3]) then
    return nd1[3] < nd2[3]
  end
  local z1, z2 = nd1[2].fromZip and true or false, nd2[2].fromZip and true or false
  if (z1 ~= z2) then
    return z1  -- mod widgets first
  end
  return (nd1[1] < nd2[1]) -- sort by name
end


-- the rows actually listed: a header per category, then its widgets (unless the category is folded)
local function BuildDisplayList()
  fullWidgetsList = {}
  local last, members
  for _, e in ipairs(entriesAll) do
    if (e[3] ~= last) then
      last = e[3]
      members = {}
      fullWidgetsList[#fullWidgetsList + 1] = { last, { header = true, category = last, members = members } }
    end
    members[#members + 1] = e
    if (not collapsed[last]) then
      fullWidgetsList[#fullWidgetsList + 1] = e
    end
  end
end


local function ToggleCategory(cat)
  collapsed[cat] = not collapsed[cat]
  BuildDisplayList()
  UpdateListScroll()
  UpdateGeometry()
end


local function UpdateList()
  if (not widgetHandler.knownChanged) then
    return
  end
  widgetHandler.knownChanged = false

  local myName = widget:GetInfo().name
  nameW = 0
  widgetsList = {}
  fullWidgetsList = {}
  entriesAll = {}
  local knownFiles = {}
  local myCount = 0

  local function Measure(label)
    local width = fontSize * gl.GetTextWidth(label) + NAME_INDENT
    if (width > nameW) then nameW = width end
  end

  for name,data in pairs(widgetHandler.knownWidgets) do
    if (data.filename) then knownFiles[data.filename] = true end
    if (name ~= myName) then
      myCount = myCount + 1
      table.insert(entriesAll, { name, data, CategoryOf(name, data) })
      Measure(data.fromZip and ('*' .. name .. '*') or name)
    end
  end

  if (widgetHandler.knownCount ~= (myCount + 1)) then
    error('knownCount mismatch')
  end

  -- widget files that failed to load are not "known"; list them too so their error is visible
  for filename, f in pairs(widgetHandler.failedWidgets or {}) do
    if (not knownFiles[filename]) then
      local label = f.basename or filename
      table.insert(entriesAll, { label, {
        failed = true, active = false, filename = filename,
        basename = f.basename, fromZip = f.fromZip,
      }, CATEGORY_FAILED })
      Measure(label)
    end
  end

  table.sort(entriesAll, SortWidgetListFunc)
  BuildDisplayList()

  UpdateListScroll()
  UpdateGeometry()
end


function widget:Shutdown()
  selectorOpen = false
end


function widget:ViewResize(viewSizeX, viewSizeY)
  vsx = viewSizeX
  vsy = viewSizeY
  --UpdateList()
  --UpdateGeometry()
end


-------------------------------------------------------------------------------

local KEY_ESC = Spring.GetKeyCode("esc")
local KEY_F11 = Spring.GetKeyCode("f11")
local KEY_PGUP = Spring.GetKeyCode("pageup")
local KEY_PGDN = Spring.GetKeyCode("pagedown")

function widget:KeyPress(key, mods, isRepeat)
  if key == KEY_ESC then
    widgetHandler:RemoveWidget(self)
    return true
  end
  if (key == KEY_F11) and not (mods.alt or mods.ctrl or mods.meta or mods.shift) then
    -- This widget (selector table + memory graph) only exists while the selector is open.
    -- F11 while it is open closes it; F11 while it is closed is handled by the engine
    -- ("luaui selector"), which loads it again. Swallow repeats so holding F11 doesn't flicker.
    if (not isRepeat) then
      widgetHandler:RemoveWidget(self)
    end
    return true
  end
  if (key == KEY_PGUP) then
    ScrollUp(pageStep)
    return true
  end
  if (key == KEY_PGDN) then
    ScrollDown(pageStep)
    return true
  end
  return false
end


function widget:DrawScreen()
  UpdateList()
  RefreshMemory(memHistFill == 0)
  UpdateGeometry()

  local mx,my,lmb,mmb,rmb = Spring.GetMouseState()
  local nd = not widgetHandler.tweakMode and self:AboveLabel(mx, my)

  ---------------------------------------------------------------------------
  -- pass 0: work out what every visible row looks like
  ---------------------------------------------------------------------------
  local rows = {}
  local pointedY = nil
  local pointedEnabled = false
  local posy = maxy - yStep - bordery
  sby1 = posy + fontSize + fontSpace * 0.5
  for _,namedata in ipairs(widgetsList) do
    local name = namedata[1]
    local data = namedata[2]
    if (data.header) then
      rows[#rows + 1] = HeaderRow(data, posy)
    else
    local order = widgetHandler.orderList[name]
    local enabled = (not data.failed) and order and (order > 0)
    local active = data.active
    local pointed = (nd == namedata) and not data.failed
    local color
    if (pointed and not activescrollbar) then
      pointedY = posy
      pointedEnabled = data.active
      if (lmb or mmb or rmb) then
        color = WhiteStr
      else
        color = (active  and '\255\128\255\128') or
                (enabled and '\255\255\255\128') or '\255\255\128\128'
      end
    else
      color = (active  and '\255\064\224\064') or
              (enabled and '\255\200\200\064') or '\255\224\064\064'
    end

    local row = { y = posy, active = active }
    if (data.fromZip) then
      row.nameText = WhiteStr .. '*' .. color .. name .. WhiteStr .. '*'
    else
      row.nameText = color .. name
    end

    local mb = memBytes[name]
    if (data.failed) then
      row.memText, row.memCol = "failed", '\255\255\112\112'
      row.sizeText = "?"
    else
      if (active and mb) then
        row.mb = mb
        row.memText, row.memCol = "~" .. FmtBytes(mb), '\255\128\224\255'
      else
        row.memText, row.memCol = "off", '\255\128\128\128'
      end
      row.sizeText = data.size and FmtBytes(data.size) or "?"
    end

    local em, where = GetWidgetError(name, data)
    if (em and errW > 0) then
      row.err = FitError(ErrorText(em, where))
    end
    if (active and trendText[name]) then
      row.trend, row.trendCol = trendText[name], trendCol[name]
    end
    rows[#rows + 1] = row
    end  -- not a header
    posy = posy - yStep
  end

  ---------------------------------------------------------------------------
  -- pass 1: geometry (panel, stripes, column lines, dotted histograms, scrollbar)
  ---------------------------------------------------------------------------
  gl.Texture(false)
  gl.Color(0.3, 0.3, 0.3, 1.0)
  gl.Texture(":n:bitmaps/detailtex.bmp")
  local ts = (2.0 / 512)  --  texture scale
  gl.Shape(GL.QUADS, {
    { v = { minx, miny }, t = { minx * ts, miny * ts } },
    { v = { maxx, miny }, t = { maxx * ts, miny * ts } },
    { v = { maxx, hdrTop }, t = { maxx * ts, hdrTop * ts } },
    { v = { minx, hdrTop }, t = { minx * ts, hdrTop * ts } }
  })
  gl.Texture(false)

  -- header strip + rule under it
  gl.Color(0, 0, 0, 0.45)
  gl.Rect(minx, maxy, maxx, hdrTop)
  gl.Color(1, 1, 1, 0.35)
  gl.Rect(minx, maxy - 0.5, maxx, maxy + 0.5)

  -- zebra stripes; rows with an error get a red tint
  for i, row in ipairs(rows) do
    local y0 = row.y - fontSpace * 0.5
    local y1 = row.y + fontSize + fontSpace * 0.5
    if (row.header) then
      gl.Color(0.30, 0.42, 0.70, 0.30)
      gl.Rect(minx, y0, maxx, y1)
      gl.Color(1, 1, 1, 0.18)
      gl.Rect(minx, y0, maxx, y0 + 1)
    elseif (row.err) then
      gl.Color(0.85, 0.10, 0.10, 0.16)
      gl.Rect(minx, y0, maxx, y1)
    elseif (i % 2 == 0) then
      gl.Color(1, 1, 1, 0.045)
      gl.Rect(minx, y0, maxx, y1)
    end
  end

  -- thin column separators
  gl.Color(1, 1, 1, 0.10)
  local seps = { xHist - COL_GAP * 0.5, xMemR + COL_GAP * 0.5, xTrend + trendW + COL_GAP * 0.5 }
  if (errW > 0) then seps[#seps + 1] = xSizeR + COL_GAP end
  for _, sx in ipairs(seps) do
    gl.Rect(sx, miny, sx + 1, hdrTop)
  end

  -- dotted memory histogram: filled dots run cyan -> orange, empty slots are a faint track
  for _, row in ipairs(rows) do
   if (not row.header) then
    local y0 = row.y + fontSize * 0.5 - DOT_SZ * 0.5
    local filled = 0
    if (row.mb and row.mb > 0) then
      filled = math.max(1, floor(MemFraction(row.mb) * HIST_DOTS + 0.5))
    end
    for d = 1, HIST_DOTS do
      local x0 = xHist + (d - 1) * DOT_STEP
      if (d <= filled) then
        local t = (d - 1) / (HIST_DOTS - 1)
        gl.Color(0.10 + 0.90 * t, 0.85 - 0.25 * t, 1.0 - 0.80 * t, 0.9)
      else
        gl.Color(1, 1, 1, row.active and 0.12 or 0.06)
      end
      gl.Rect(x0, y0, x0 + DOT_SZ, y0 + DOT_SZ)
    end
   end  -- not a header
  end

  -- scrollbar
  if #widgetsList < #fullWidgetsList then
    sby2 = posy + yStep - fontSpace * 0.5
    sbheight = sby1 - sby2
    sbsize = sbheight * #widgetsList / #fullWidgetsList 
    if activescrollbar then
    	startEntry = math.max(0, math.min(
    	math.floor(#fullWidgetsList * 
    	((sby1 - sbsize) - 
    	(my - math.min(scrollbargrabpos, sbsize)))
    	 / sbheight + 0.5), 
                         #fullWidgetsList - maxEntries)) + 1
    end
    local sizex = maxx - minx
    sbposx = minx + sizex + 1.0
    sbposy = sby1 - sbsize - sbheight * (startEntry - 1) / #fullWidgetsList
    sbsizex = yStep
    sbsizey = sbsize
    
    gl.Color(0.0, 0.0, 0.0, 0.8)
    gl.Shape(GL.QUADS, {
      { v = { sbposx, miny } }, { v = { sbposx, maxy } },
      { v = { sbposx + sbsizex, maxy } }, { v = { sbposx + sbsizex, miny } }
    })    

    gl.Color(1.0, 1.0, 1.0, 0.8)
    gl.Shape(GL.TRIANGLES, {
      { v = { sbposx + sbsizex / 2, miny } }, { v = { sbposx, sby2 - 1 } },
      { v = { sbposx + sbsizex, sby2 - 1 } }
    })    

    gl.Shape(GL.TRIANGLES, {
      { v = { sbposx + sbsizex / 2, maxy } }, { v = { sbposx + sbsizex, sby2 + sbheight + 1 } },
      { v = { sbposx, sby2 + sbheight + 1 } }
    })
    
    if (sbposx < mx and mx < sbposx + sbsizex and miny < my and my < maxy) or activescrollbar then
      gl.Color(0.2, 0.2, 1.0, 0.6)
      gl.Blending(false)
      gl.Shape(GL.LINE_LOOP, {
        { v = { sbposx, miny } }, { v = { sbposx, maxy } },
        { v = { sbposx + sbsizex, maxy } }, { v = { sbposx + sbsizex, miny } }
      })    
      gl.Blending(GL.SRC_ALPHA, GL.ONE)
      gl.Shape(GL.QUADS, {
        { v = { sbposx + 0.5, miny + 0.5 } }, { v = { sbposx + 0.5, maxy - 0.5 } },
        { v = { sbposx + sbsizex - 0.5, maxy - 0.5 } }, { v = { sbposx + sbsizex - 0.5, miny + 0.5 } }
      })
      gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
    end      
    
    if (sbposx < mx and mx < sbposx + sbsizex and sby2 < my and my < sby2 + sbheight) then
      gl.Color(0.2, 0.2, 1.0, 0.2)
      gl.Blending(false)
      gl.Shape(GL.LINE_LOOP, {
        { v = { sbposx, sbposy } }, { v = { sbposx, sbposy + sbsizey } },
        { v = { sbposx + sbsizex, sbposy + sbsizey } }, { v = { sbposx + sbsizex, sbposy } }
      })    
      gl.Blending(GL.SRC_ALPHA, GL.ONE)
      gl.Shape(GL.QUADS, {
        { v = { sbposx + 0.5, sbposy + 0.5 } }, { v = { sbposx + 0.5, sbposy + sbsizey - 0.5 } },
        { v = { sbposx + sbsizex - 0.5, sbposy + sbsizey - 0.5 } }, { v = { sbposx + sbsizex - 0.5, sbposy + 0.5 } }
      })
      gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
    end    

    gl.Color(0.25, 0.25, 0.25, 0.8)
    gl.Shape(GL.QUADS, {
      { v = { sbposx, sby2 } }, { v = { sbposx, sby2 + sbheight } },
      { v = { sbposx + sbsizex, sby2 + sbheight } }, { v = { sbposx + sbsizex, sby2 } }
    })    
    gl.Color(1.0, 1.0, 1.0, 0.4)
    gl.Shape(GL.LINE_LOOP, {
      { v = { sbposx, sby2 } }, { v = { sbposx, sby2 + sbheight } },
      { v = { sbposx + sbsizex, sby2 + sbheight } }, { v = { sbposx + sbsizex, sby2 } }
    })    

    gl.Color(0.8, 0.8, 0.8, 0.8)
    gl.Shape(GL.QUADS, {
      { v = { sbposx, sbposy } }, { v = { sbposx, sbposy + sbsizey } },
      { v = { sbposx + sbsizex, sbposy + sbsizey } }, { v = { sbposx + sbsizex, sbposy } }
    })    
    if activescrollbar or (sbposx < mx and mx < sbposx + sbsizex and sbposy < my and my < sbposy + sbsizey) then
      gl.Color(0.2, 0.2, 1.0, 0.2)
      gl.Blending(false)
      gl.Shape(GL.LINE_LOOP, {
        { v = { sbposx, sbposy } }, { v = { sbposx, sbposy + sbsizey } },
        { v = { sbposx + sbsizex, sbposy + sbsizey } }, { v = { sbposx + sbsizex, sbposy } }
      })    
      gl.Blending(GL.SRC_ALPHA, GL.ONE)
      gl.Shape(GL.QUADS, {
        { v = { sbposx + 0.5, sbposy + 0.5 } }, { v = { sbposx + 0.5, sbposy + sbsizey - 0.5 } },
        { v = { sbposx + sbsizex - 0.5, sbposy + sbsizey - 0.5 } }, { v = { sbposx + sbsizex - 0.5, sbposy + 0.5 } }
      })
      gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
    end  
  else
    sbposx = 0.0
    sbposy = 0.0
    sbsizex = 0.0
    sbsizey = 0.0
  end


  -- outline the highlighted label
  if (pointedY) then
    if (lmb or mmb or rmb) then
      if (pointedEnabled) then
        gl.Color(1.0, 0.2, 0.2, 0.2)
      else
        gl.Color(0.2, 1.0, 1.0, 0.2)
      end
    else
      gl.Color(0.2, 0.2, 1.0, 0.2)
    end
    local xn = minx + 0.5
    local xp = maxx - 0.5
    local yn = pointedY - fontSpace * 0.5
    local yp = pointedY + fontSize + fontSpace * 0.5
    gl.Blending(false)
    gl.Shape(GL.LINE_LOOP, {
      { v = { xn, yn } }, { v = { xp, yn } },
      { v = { xp, yp } }, { v = { xn, yp } }
    })
    xn = minx
    xp = maxx
    yn = yn + 0.5
    yp = yp - 0.5
    gl.Blending(GL.SRC_ALPHA, GL.ONE)
    gl.Shape(GL.QUADS, {
      { v = { xn, yn } }, { v = { xp, yn } },
      { v = { xp, yp } }, { v = { xn, yp } }
    })
    gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
  end


  -- outline the table (header strip included)
  local xn = minx - 0.5
  local yn = miny - 0.5
  local xp = maxx + 0.5
  local yp = hdrTop + 0.5
  gl.Color(1, 1, 1)
  gl.Shape(GL.LINE_LOOP, {
    { v = { xn, yn } }, { v = { xp, yn } },
    { v = { xp, yp } }, { v = { xn, yp } }
  })
  xn = xn - 1
  yn = yn - 1
  xp = xp + 1
  yp = yp + 1
  gl.Color(0, 0, 0)
  gl.Shape(GL.LINE_LOOP, {
    { v = { xn, yn } }, { v = { xp, yn } },
    { v = { xp, yp } }, { v = { xn, yp } }
  })

  ---------------------------------------------------------------------------
  -- pass 2: text
  ---------------------------------------------------------------------------
  gl.BeginText()

  gl.Text("Widget Selector", midx, hdrTop + 8, fontSize * 1.25, "oc")

  local hy = maxy + (hdrTop - maxy) * 0.5
  local hc = '\255\255\255\128'
  gl.Text(hc .. "WIDGET", xName,  hy, fontSize, "vo")
  gl.Text(hc .. "MEMORY", xHist,  hy, fontSize, "vo")
  gl.Text(hc .. "OVER TIME", xTrend, hy, fontSize, "vo")
  gl.Text(hc .. "SIZE",   xSizeR, hy, fontSize, "vor")
  if (errW > 0) then
    gl.Text('\255\255\128\128' .. "ERROR", xErr, hy, fontSize, "vo")
  end

  for _, row in ipairs(rows) do
    local ty = row.y + fontSize * 0.5
    gl.Text(row.nameText, xName + (row.header and 0 or NAME_INDENT), ty, fontSize, "v")
    gl.Text(row.memCol .. row.memText, xMemR, ty, fontSize, "vr")
    if (row.trend) then
      gl.Text(row.trendCol .. row.trend, xTrend, ty, fontSize, "v")
    end
    gl.Text((row.sizeCol or '\255\200\200\200') .. row.sizeText, xSizeR, ty, fontSize, "vr")
    if (row.err) then
      gl.Text('\255\255\112\112' .. row.err, xErr, ty, fontSize, "v")
    end
  end

  -- All / None buttons
  local tcol = WhiteStr
  if minx < mx and mx < minx + 30 and miny - 20 < my and my < miny then
    tcol = '\255\031\031\255'
  end
  gl.Text(tcol .. 'All', minx + 15, miny - 15, fontSize * 1.25, "oc")
  tcol = WhiteStr
  if maxx - 50 < mx and mx < maxx and miny - 20 < my and my < miny then
    tcol = '\255\031\031\255'
  end
  gl.Text(tcol .. 'None', maxx - 25, miny - 15, fontSize * 1.25, "oc")

  -- totals line under the table
  local totalsTxt = string.format('\255\200\200\200' .. "%d active   source %s   widget memory ~%s   (Lua heap %s)   Spring: %s",
                                  totals.active, FmtBytes(totals.src), FmtBytes(totals.mem),
                                  FmtBytes(collectgarbage("count") * 1024),
                                  FmtBytes(totals.springMem))
  if (errCount > 0) then
    totalsTxt = totalsTxt .. '\255\255\112\112' .. string.format("   %d with errors", errCount)
  end
  gl.Text(totalsTxt, midx, miny - 36, fontSize, "oc")
  gl.Text('\255\160\160\160' .. "memory = live tables/strings/closures held by the widget (estimate, excludes compiled code)",
          midx, miny - 52, fontSize * 0.85, "oc")
  gl.Text('\255\160\160\160' .. string.format("dots: %s scale, full row = heaviest widget (%s)",
                                                 HIST_LOG and "log" or "linear", FmtBytes(totals.maxMem)),
          midx, miny - 66, fontSize * 0.85, "oc")
  gl.Text('\255\160\160\160' .. string.format("over time: last %d samples (1 per %.1f s, only while this list is open), . low  # high per widget, orange = growing, green = shrinking",
                                                 TREND_LEN, MEM_REFRESH),
          midx, miny - 80, fontSize * 0.85, "oc")
  gl.Text('\255\160\160\160' .. "click a category header to fold it   |   size = source file, memory = live Lua data",
          midx, miny - 94, fontSize * 0.85, "oc")

  gl.EndText()

  -- memory-over-time graph (dotted lines) in the bottom-right corner
  DrawMemGraph()
end


function widget:MousePress(x, y, button)
  if (Spring.IsGUIHidden()) then
    return false
  end

  UpdateList()

  if button == 1 then
    if minx < x and x < minx + 30 and miny - 20 < y and y < miny then
      return true
    end
    if maxx - 50 < x and x < maxx and miny - 20 < y and y < miny then  
      return true
    end
  
    if sbposx < x and x < sbposx + sbsizex and sbposy < y and y < sbposy + sbsizey then
      activescrollbar = true
      scrollbargrabpos = y - sbposy
      return true
    elseif sbposx < x and x < sbposx + sbsizex and sby2 < y and y < sby2 + sbheight then
      if y > sbposy + sbsizey then
        startEntry = math.max(1, math.min(startEntry - maxEntries, #fullWidgetsList - maxEntries + 1))
      elseif y < sbposy then
        startEntry = math.max(1, math.min(startEntry + maxEntries, #fullWidgetsList - maxEntries + 1))
      end
      UpdateListScroll()
      return true   
    end
  end

  if ((x >= minx) and (x <= maxx + yStep)) then
    if ((y >= (maxy - bordery)) and (y <= maxy)) then
      if x > maxx then
        ScrollUp(1)
      else
        ScrollUp(pageStep)
      end
      return true
    elseif ((y >= miny) and (y <= miny + bordery)) then
      if x > maxx then
        ScrollDown(1)
      else
        ScrollDown(pageStep)
      end
      return true
    end
  end
  
  local namedata = self:AboveLabel(x, y)
  if (not namedata) then
    return false
  end
  
  return true
  
end


function widget:MouseMove(x, y, dx, dy, button)
  if activescrollbar then
    startEntry = math.max(0, math.min(math.floor((#fullWidgetsList * ((sby1 - sbsize) - (y - math.min(scrollbargrabpos, sbsize))) / sbheight) + 0.5), 
    #fullWidgetsList - maxEntries)) + 1
    UpdateListScroll()
  end
  return false
end


function widget:MouseRelease(x, y, button)
  if (Spring.IsGUIHidden()) then
    return -1
  end

  UpdateList()
  
  if button == 1 and activescrollbar then
    activescrollbar = false
    scrollbargrabpos = 0.0
    return -1
  end

  if button == 1 then
    if minx < x and x < minx + 30 and miny - 20 < y and y < miny then
      for _,namedata in ipairs(entriesAll) do
        if (not namedata[2].failed) then widgetHandler:EnableWidget(namedata[1]) end
      end
      return -1
    end
    if maxx - 50 < x and x < maxx and miny - 20 < y and y < miny then
      for _,namedata in ipairs(entriesAll) do
        if (not namedata[2].failed) then
          widgetHandler:DisableWidget(namedata[1])
          widgetHandler.orderList[namedata[1]] = 0
        end
      end
      widgetHandler:SaveConfigData()    
      return -1
    end
  end
  
  local namedata = self:AboveLabel(x, y)
  if (not namedata) then
    return false
  end
  
  local name = namedata[1]
  local data = namedata[2]
  if (data.header) then                -- category header: left click folds / unfolds it
    if (button == 1) then ToggleCategory(data.category) end
    return -1
  end
  if (data.failed) then return -1 end  -- file never loaded: nothing to toggle
  
  if (button == 1) then
    widgetHandler:ToggleWidget(name)
  elseif ((button == 2) or (button == 3)) then
    local w = widgetHandler:FindWidget(name)
    if (not w) then return -1 end
    if (button == 2) then
      widgetHandler:LowerWidget(w)
    else
      widgetHandler:RaiseWidget(w)
    end
    widgetHandler:SaveConfigData()
  end
  return -1
end


function widget:AboveLabel(x, y)
  if ((x < minx) or (y < (miny + bordery)) or
      (x > maxx) or (y > (maxy - bordery))) then
    return nil
  end
  local count = #widgetsList
  if (count < 1) then return nil end
  
  local i = floor(1 + ((maxy - bordery) - y) / yStep)
  if     (i < 1)     then i = 1
  elseif (i > count) then i = count end
  
  return widgetsList[i]
end


function widget:IsAbove(x, y)
  UpdateList()
  if ((x < minx) or (x > maxx + yStep) or
      (y < miny - 20) or (y > hdrTop)) then
    return false
  end
  return true
end


function widget:GetTooltip(x, y)
  UpdateList()  
  local namedata = self:AboveLabel(x, y)
  if (not namedata) then
    return '\255\200\255\200'..'Widget Selector\n'    ..
           '\255\255\255\200'..'LMB: toggle widget\n' ..
           '\255\255\200\200'..'MMB: lower  widget\n' ..
           '\255\200\200\255'..'RMB: raise  widget'
  end

  local n = namedata[1]
  local d = namedata[2]

  if (d.header) then
    return CatColor(d.category) .. d.category .. '\n' ..
           WhiteStr .. #d.members .. ' widget(s) in this category\n' ..
           '\255\255\255\200' .. 'LMB: fold / unfold'
  end

  local order = widgetHandler.orderList[n]
  local enabled = order and (order > 0)
  
  local tt = (d.active and GreenStr) or (enabled  and YellowStr) or RedStr
  tt = tt..n..'\n'
  tt = d.desc   and tt..WhiteStr..d.desc..'\n' or tt
  tt = d.author and tt..BlueStr..'Author:  '..CyanStr..d.author..'\n' or tt
  tt = tt..MagentaStr..d.basename
  tt = tt..'\n'..WhiteStr..'Size: '..(d.size and FmtBytes(d.size) or '?')
  if (d.active and memBytes[n]) then
    tt = tt..'   Memory: ~'..FmtBytes(memBytes[n])
  end
  tt = tt..'\n'..WhiteStr..'Category: '..CatColor(d.category or CategoryOf(n, d))..(d.category or CategoryOf(n, d))
  if (d.active and trendText[n]) then
    tt = tt..'\n'..WhiteStr..'Over time: '..trendCol[n]..trendText[n]
  end
  if (d.fromZip) then
    tt = tt..RedStr..' (mod widget)'
  end
  local em, where = GetWidgetError(n, d)
  if (em) then
    local what = (where and where ~= "load") and (' in ' .. where .. '()') or ' while loading'
    if (#em > 500) then em = em:sub(1, 497) .. '...' end
    tt = tt..'\n'..RedStr..'Error'..what..':\n'..WhiteStr..em
  end
  return tt
end


-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
