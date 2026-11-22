function widget:GetInfo()
	return {
		name    = "Blueprints",
		desc    = "Save groups of buildings as blueprints (to file), load them back, pick them from a panel and place them with a ghost preview",
		author  = "goddot",
		date    = "2026",
		license = "GNU GPL, v2 or later",
		layer   = 10,
		enabled = false,
	}
end

--------------------------------------------------------------------------------
-- Usage
--   * Select some of your buildings, click [+ Save] (or /bind <key> blueprint_save)
--       -> the blueprint is added to the panel AND written to
--          LuaUI/Config/Blueprints/<name>.lua
--   * Click [Load] to list every .lua file in that folder, click one to import it
--       (or type /blueprint_load <name>)
--   * Click a blueprint row to select it -> a green/red ghost follows the cursor
--   * Select your builders, then Left-click on the map to place
--       - hold SHIFT : queue the blueprint and keep it active (place many)
--       - no SHIFT   : replace the builders' queue and deselect the blueprint
--   * [ and ] rotate (or /bind <key> blueprint_rotate), Right-click / Esc cancels
--   * Right-click a row to remove it from the panel (the file is kept)
--   * Drag the title bar to move the panel
--
-- File format (plain Lua, safe to hand-edit or share):
--   return {
--     name = "Solar block",
--     items = {
--       { def = "armsolar", dx = 0, dz = 0, facing = 0 },
--       { def = "armsolar", dx = 48, dz = 0, facing = 0 },
--     },
--   }
-- A file may also return a list of such tables.
--------------------------------------------------------------------------------

local glColor, glRect, glText = gl.Color, gl.Rect, gl.Text
local glTexture, glTexRect = gl.Texture, gl.TexRect
local floor, max, min = math.floor, math.max, math.min

local DIR = "LuaUI/Config/Blueprints/"

local PANEL_W, HEADER_H, ROW_H, ICON = 250, 26, 44, 36
local MAX_ICONS = 4
local FILE_W, FILE_HEADER_H, FILE_ROW_H = 190, 22, 22

local vsx, vsy = Spring.GetViewGeometry()
local px, py = 12, floor(vsy * 0.55) -- panel left / top, draggable
local defaultPos = true               -- not placed by the player yet: stays right of the default layout column (vb_layout.lua)

local blueprints = {}   -- { {name=, file=, items={ {def="armsolar", dx=, dz=, facing=} } } }
local active = nil      -- index of selected blueprint
local rotation = 0      -- 0..3 extra clockwise rotation
local dragging = false
local myTeam = Spring.GetMyTeamID()
local canBuildCache = {}
local keyRotL, keyRotR

local loadOpen = false
local files = {}        -- { {name=, path=} } found in DIR

--------------------------------------------------------------------------------
-- geometry / hit testing
--------------------------------------------------------------------------------

local function panelHeight()
	return HEADER_H + max(1, #blueprints) * ROW_H + 6
end

local function overMain(x, y)
	return x >= px and x <= px + PANEL_W and y <= py and y >= py - panelHeight()
end

local function fileX()
	local fx = px + PANEL_W + 4
	if fx + FILE_W > vsx then fx = px - FILE_W - 4 end
	return fx
end

local function filePanelHeight()
	return FILE_HEADER_H + max(1, #files) * FILE_ROW_H + 4
end

local function overFiles(x, y)
	if not loadOpen then return false end
	local fx = fileX()
	return x >= fx and x <= fx + FILE_W and y <= py and y >= py - filePanelHeight()
end

local function overPanel(x, y)
	return overMain(x, y) or overFiles(x, y)
end

local function rowAt(x, y)
	if not overMain(x, y) then return nil end
	local rel = py - HEADER_H - y
	if rel < 0 then return nil end
	local i = floor(rel / ROW_H) + 1
	if blueprints[i] then return i end
end

local function fileRowAt(x, y)
	if not overFiles(x, y) then return nil end
	local rel = py - FILE_HEADER_H - y
	if rel < 0 then return nil end
	local i = floor(rel / FILE_ROW_H) + 1
	if files[i] then return i end
end

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------

local function rotOffset(dx, dz, r)
	for _ = 1, r do dx, dz = dz, -dx end -- 90 deg clockwise seen from above
	return dx, dz
end

local function canBuild(builderDefID, targetDefID)
	local c = canBuildCache[builderDefID]
	if not c then
		c = {}
		for _, id in ipairs(UnitDefs[builderDefID].buildOptions or {}) do c[id] = true end
		canBuildCache[builderDefID] = c
	end
	return c[targetDefID]
end

--------------------------------------------------------------------------------
-- file I/O
--------------------------------------------------------------------------------

local function serialize(bp)
	local t = { "return {\n\tname = " .. string.format("%q", bp.name) .. ",\n\titems = {\n" }
	for _, it in ipairs(bp.items) do
		t[#t + 1] = string.format("\t\t{ def = %q, dx = %.2f, dz = %.2f, facing = %d },\n",
			it.def, it.dx, it.dz, it.facing)
	end
	t[#t + 1] = "\t},\n}\n"
	return table.concat(t)
end

local function writeBlueprint(bp)
	Spring.CreateDir(DIR)
	local ok, err = pcall(function()
		local f = assert(io.open(DIR .. bp.file .. ".lua", "w"))
		f:write(serialize(bp))
		f:close()
	end)
	if not ok then
		Spring.Echo("[Blueprints] Could not write " .. DIR .. bp.file .. ".lua (" .. tostring(err) ..
			"). The blueprint is still kept in the widget config.")
	end
	return ok
end

-- validate one raw blueprint table; returns clean blueprint (or nil) and #skipped items
local function cleanBlueprint(raw, fallbackName)
	if type(raw) ~= "table" or type(raw.items) ~= "table" then return nil, 0 end
	local items, skipped = {}, 0
	for _, it in ipairs(raw.items) do
		local dx, dz = tonumber(it.dx), tonumber(it.dz)
		if type(it.def) == "string" and UnitDefNames[it.def] and dx and dz then
			items[#items + 1] = { def = it.def, dx = dx, dz = dz, facing = floor(tonumber(it.facing) or 0) % 4 }
		else
			skipped = skipped + 1
		end
	end
	if #items == 0 then return nil, skipped end
	return { name = tostring(raw.name or fallbackName), items = items }, skipped
end

local function loadFile(path, base)
	local text = VFS.LoadFile(path, VFS.RAW)
	if not text then
		Spring.Echo("[Blueprints] Cannot read " .. path)
		return 0
	end
	local chunk, err = loadstring(text)
	if not chunk then
		Spring.Echo("[Blueprints] Syntax error in " .. path .. ": " .. tostring(err))
		return 0
	end
	setfenv(chunk, {}) -- empty environment: the file can only describe data
	local ok, data = pcall(chunk)
	if not ok or type(data) ~= "table" then
		Spring.Echo("[Blueprints] " .. path .. " did not return a table")
		return 0
	end

	local list = data.items and { data } or data
	local loaded, skippedTotal = 0, 0
	for _, raw in ipairs(list) do
		local bp, skipped = cleanBlueprint(raw, base)
		skippedTotal = skippedTotal + skipped
		if bp then
			bp.file = base
			local replaced = false
			for i, old in ipairs(blueprints) do
				if old.file == base and old.name == bp.name then
					blueprints[i] = bp
					replaced = true
					break
				end
			end
			if not replaced then blueprints[#blueprints + 1] = bp end
			loaded = loaded + 1
		end
	end

	if loaded == 0 then
		Spring.Echo("[Blueprints] No usable blueprint in " .. path)
	else
		Spring.Echo("[Blueprints] Loaded " .. loaded .. " blueprint(s) from " .. base ..
			(skippedTotal > 0 and (" (" .. skippedTotal .. " unknown unit(s) skipped)") or ""))
	end
	return loaded
end

local function scanFiles()
	files = {}
	for _, path in ipairs(VFS.DirList(DIR, "*.lua", VFS.RAW) or {}) do
		local base = path:match("([^/\\]+)%.lua$")
		if base then files[#files + 1] = { name = base, path = path } end
	end
	table.sort(files, function(a, b) return a.name:lower() < b.name:lower() end)
end

local function loadByName(name)
	if not name or name == "" then
		Spring.Echo("[Blueprints] Usage: /blueprint_load <file name>")
		return
	end
	name = name:gsub("%.lua$", "")
	loadFile(DIR .. name .. ".lua", name)
end

local function uniqueName()
	local n = #blueprints + 1
	while true do
		local name = "BP " .. n
		local taken = VFS.FileExists(DIR .. name .. ".lua", VFS.RAW)
		for _, bp in ipairs(blueprints) do
			if bp.name == name or bp.file == name then taken = true end
		end
		if not taken then return name end
		n = n + 1
	end
end

--------------------------------------------------------------------------------
-- blueprint actions
--------------------------------------------------------------------------------

local function saveSelected()
	local items, minx, maxx, minz, maxz = {}, math.huge, -math.huge, math.huge, -math.huge
	for _, uID in ipairs(Spring.GetSelectedUnits()) do
		local ud = UnitDefs[Spring.GetUnitDefID(uID)]
		if ud and ud.isBuilding and Spring.GetUnitTeam(uID) == myTeam then
			local x, _, z = Spring.GetUnitPosition(uID)
			items[#items + 1] = { def = ud.name, x = x, z = z, facing = Spring.GetUnitBuildFacing(uID) or 0 }
			minx, maxx = min(minx, x), max(maxx, x)
			minz, maxz = min(minz, z), max(maxz, z)
		end
	end
	if #items == 0 then
		Spring.Echo("[Blueprints] Select some of your buildings first.")
		return
	end
	local cx, cz = (minx + maxx) / 2, (minz + maxz) / 2
	for _, it in ipairs(items) do
		it.dx, it.dz = it.x - cx, it.z - cz
		it.x, it.z = nil, nil
	end
	local name = uniqueName()
	local bp = { name = name, file = (name:gsub("[^%w%-_ ]", "_")), items = items }
	blueprints[#blueprints + 1] = bp
	if writeBlueprint(bp) then
		Spring.Echo("[Blueprints] Saved " .. DIR .. bp.file .. ".lua")
	end
	if loadOpen then scanFiles() end
end

local function cancel()
	active = nil
	rotation = 0
end

local function rotate(step)
	if active then rotation = (rotation + (step or 1)) % 4 end
	return true
end

-- iterate resolved placements for a blueprint at world (wx, wz)
local function eachPlacement(bp, wx, wz, fn)
	for _, it in ipairs(bp.items) do
		local ud = UnitDefNames[it.def]
		if ud then
			local dx, dz = rotOffset(it.dx, it.dz, rotation)
			local facing = (it.facing + rotation) % 4
			local x, y, z = Spring.Pos2BuildPos(ud.id, wx + dx, 0, wz + dz, facing)
			y = Spring.GetGroundHeight(x, z)
			fn(ud, x, y, z, facing)
		end
	end
end

local function place(wx, wz)
	local bp = blueprints[active]
	if not bp then return end
	local builders = {}
	for _, uID in ipairs(Spring.GetSelectedUnits()) do
		local defID = Spring.GetUnitDefID(uID)
		if defID and #(UnitDefs[defID].buildOptions or {}) > 0 then builders[#builders + 1] = uID end
	end
	if #builders == 0 then
		Spring.Echo("[Blueprints] Select builder units first.")
		return
	end
	local _, _, _, shift = Spring.GetModKeyState()
	if not shift then Spring.GiveOrderToUnitArray(builders, CMD.STOP, {}, {}) end
	eachPlacement(bp, wx, wz, function(ud, x, y, z, facing)
		local capable = {}
		for _, b in ipairs(builders) do
			if canBuild(Spring.GetUnitDefID(b), ud.id) then capable[#capable + 1] = b end
		end
		if #capable > 0 then
			Spring.GiveOrderToUnitArray(capable, -ud.id, { x, y, z, facing }, { "shift" })
		end
	end)
	if not shift then cancel() end
end

--------------------------------------------------------------------------------
-- widget callins
--------------------------------------------------------------------------------

function widget:Initialize()
	if Spring.GetSpectatingState() then
		widgetHandler:RemoveWidget()
		return
	end
	keyRotL, keyRotR = Spring.GetKeyCode("["), Spring.GetKeyCode("]")
	widgetHandler:AddAction("blueprint_save", saveSelected, nil, "p")
	widgetHandler:AddAction("blueprint_rotate", function() return rotate(1) end, nil, "p")
	widgetHandler:AddAction("blueprint_cancel", cancel, nil, "p")
	widgetHandler:AddAction("blueprint_load", function(_, line, words)
		loadByName((words and words[1]) or line)
		return true
	end, nil, "t")
end

function widget:Shutdown()
	widgetHandler:RemoveAction("blueprint_save")
	widgetHandler:RemoveAction("blueprint_rotate")
	widgetHandler:RemoveAction("blueprint_cancel")
	widgetHandler:RemoveAction("blueprint_load")
end

function widget:ViewResize()
	vsx, vsy = Spring.GetViewGeometry()
	px = min(px, vsx - PANEL_W)
	py = min(py, vsy)
end

function widget:PlayerChanged()
	myTeam = Spring.GetMyTeamID()
	if Spring.GetSpectatingState() then widgetHandler:RemoveWidget() end
end

function widget:IsAbove(x, y)
	return overPanel(x, y)
end

function widget:MousePress(x, y, button)
	-- file list (Load) panel
	if overFiles(x, y) then
		if button == 1 then
			local i = fileRowAt(x, y)
			if i then loadFile(files[i].path, files[i].name) end
		end
		return true
	end

	if overMain(x, y) then
		if y > py - HEADER_H then
			if button == 1 then
				if x > px + PANEL_W - 70 then
					saveSelected()
				elseif x > px + PANEL_W - 134 then
					loadOpen = not loadOpen
					if loadOpen then scanFiles() end
				else
					dragging = true
				end
			end
			return true
		end
		local i = rowAt(x, y)
		if i then
			if button == 1 then
				active = (active == i) and nil or i
				rotation = 0
			elseif button == 3 then
				table.remove(blueprints, i)
				if active == i then cancel() elseif active and active > i then active = active - 1 end
			end
		end
		return true
	end

	if active then
		if button == 1 then
			local _, pos = Spring.TraceScreenRay(x, y, true)
			if pos then place(pos[1], pos[3]) end
			return true
		elseif button == 3 then
			cancel()
			return true
		end
	end
	return false
end

function widget:MouseMove(x, y, dx, dy)
	if dragging then
		defaultPos = false
		px = max(0, min(vsx - PANEL_W, px + dx))
		py = max(panelHeight(), min(vsy, py + dy))
	end
end

function widget:MouseRelease()
	dragging = false
end

function widget:KeyPress(key)
	if not active then return false end
	if key == KEYSYMS.ESCAPE then
		cancel()
		return true
	elseif key == keyRotL then
		return rotate(-1)
	elseif key == keyRotR then
		return rotate(1)
	end
	return false
end

--------------------------------------------------------------------------------
-- drawing
--------------------------------------------------------------------------------

local function drawButton(x1, y1, x2, y2, label, hot, r, g, b)
	glColor(r, g, b, hot and 1 or 0.7)
	glRect(x1, y1, x2, y2)
	glColor(1, 1, 1, 1)
	glText(label, x1 + 8, y1 + 5, 12, "o")
end

function widget:DrawScreen()
	if defaultPos and WG.VBLayout and WG.VBLayout.Right then
		px = WG.VBLayout.Right() or 12
	end
	local mx, my = Spring.GetMouseState()
	local hover = rowAt(mx, my)
	local h = panelHeight()
	local inHeader = my >= py - HEADER_H and my <= py

	glColor(0, 0, 0, 0.65)
	glRect(px, py - h, px + PANEL_W, py)
	glColor(0.15, 0.15, 0.18, 0.95)
	glRect(px, py - HEADER_H, px + PANEL_W, py)
	glColor(1, 1, 1, 1)
	glText("Blueprints", px + 8, py - HEADER_H + 8, 14, "o")

	local saveX, loadX = px + PANEL_W - 70, px + PANEL_W - 134
	drawButton(loadX + 2, py - HEADER_H + 3, saveX - 2, py - 3, "Load",
		inHeader and mx >= loadX and mx < saveX, loadOpen and 0.3 or 0.25, 0.45, 0.8)
	drawButton(saveX + 2, py - HEADER_H + 3, px + PANEL_W - 4, py - 3, "+ Save",
		inHeader and mx >= saveX and mx <= px + PANEL_W, 0.2, 0.6, 0.3)

	if #blueprints == 0 then
		glColor(1, 1, 1, 0.5)
		glText("Select buildings, then + Save", px + 10, py - HEADER_H - ROW_H / 2 - 4, 12, "o")
	end

	for i, bp in ipairs(blueprints) do
		local top = py - HEADER_H - (i - 1) * ROW_H
		if i == active then
			glColor(0.2, 0.6, 1, 0.45)
			glRect(px, top - ROW_H, px + PANEL_W, top)
		elseif i == hover then
			glColor(1, 1, 1, 0.12)
			glRect(px, top - ROW_H, px + PANEL_W, top)
		end

		-- unique unit icons
		local seen, n = {}, 0
		for _, it in ipairs(bp.items) do
			local ud = UnitDefNames[it.def]
			if ud and not seen[ud.id] and n < MAX_ICONS then
				seen[ud.id] = true
				local ix = px + 6 + n * (ICON + 2)
				glColor(1, 1, 1, 1)
				glTexture("#" .. ud.id)
				glTexRect(ix, top - ROW_H + 4, ix + ICON, top - ROW_H + 4 + ICON)
				glTexture(false)
				n = n + 1
			end
		end

		glColor(1, 1, 1, 1)
		glText(bp.name .. "  (" .. #bp.items .. ")", px + 6 + MAX_ICONS * (ICON + 2) + 6,
			top - ROW_H / 2 - 4, 13, "o")
	end

	-- file list (Load) panel
	if loadOpen then
		local fx = fileX()
		local fh = filePanelHeight()
		local fhover = fileRowAt(mx, my)
		glColor(0, 0, 0, 0.7)
		glRect(fx, py - fh, fx + FILE_W, py)
		glColor(0.15, 0.15, 0.18, 0.95)
		glRect(fx, py - FILE_HEADER_H, fx + FILE_W, py)
		glColor(1, 1, 1, 1)
		glText("Load from file", fx + 8, py - FILE_HEADER_H + 6, 12, "o")

		if #files == 0 then
			glColor(1, 1, 1, 0.5)
			glText("No .lua files in", fx + 8, py - FILE_HEADER_H - 16, 11, "o")
			glText(DIR, fx + 8, py - FILE_HEADER_H - 30, 10, "o")
		end
		for i, f in ipairs(files) do
			local top = py - FILE_HEADER_H - (i - 1) * FILE_ROW_H
			if i == fhover then
				glColor(1, 1, 1, 0.15)
				glRect(fx, top - FILE_ROW_H, fx + FILE_W, top)
			end
			glColor(1, 1, 1, 1)
			glText(f.name, fx + 8, top - FILE_ROW_H + 6, 12, "o")
		end
	end

	glColor(1, 1, 1, 1)
end

function widget:DrawWorld()
	if not active or not blueprints[active] then return end
	local mx, my = Spring.GetMouseState()
	if overPanel(mx, my) then return end
	local _, pos = Spring.TraceScreenRay(mx, my, true)
	if not pos then return end

	gl.DepthTest(true)
	eachPlacement(blueprints[active], pos[1], pos[3], function(ud, x, y, z, facing)
		local ok = Spring.TestBuildOrder(ud.id, x, y, z, facing) > 0

		gl.PushMatrix()
		gl.Translate(x, y, z)
		gl.Rotate(90 * facing, 0, 1, 0) -- flip sign here if ghosts look mirrored
		gl.Color(1, 1, 1, 0.6)
		gl.UnitShape(ud.id, myTeam, false, false, false)
		gl.PopMatrix()

		local hx, hz = ud.xsize * 4, ud.zsize * 4
		if facing % 2 == 1 then hx, hz = hz, hx end
		gl.LineWidth(2)
		if ok then gl.Color(0.2, 1, 0.3, 0.9) else gl.Color(1, 0.2, 0.2, 0.9) end
		gl.BeginEnd(GL.LINE_LOOP, function()
			gl.Vertex(x - hx, y + 2, z - hz)
			gl.Vertex(x + hx, y + 2, z - hz)
			gl.Vertex(x + hx, y + 2, z + hz)
			gl.Vertex(x - hx, y + 2, z + hz)
		end)
	end)
	gl.LineWidth(1)
	gl.Color(1, 1, 1, 1)
	gl.DepthTest(false)
end

--------------------------------------------------------------------------------
-- persistence (panel position + whatever is currently in the panel)
--------------------------------------------------------------------------------

function widget:GetConfigData()
	return { px = px, py = py, blueprints = blueprints }
end

function widget:SetConfigData(data)
	if not data then return end
	if data.px then defaultPos = false end
	px, py = data.px or px, data.py or py
	blueprints = data.blueprints or blueprints
end
