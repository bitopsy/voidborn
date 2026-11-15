function gadget:GetInfo()
	return { name = "Voidborn build info", desc = "Logs the build stamp of the game archive the engine really loaded (build_sdz.py greps it)",
		author = "goddot info@bitopsy.com", date = "2026", license = "GPL", layer = -1000, enabled = true }
end
if not gadgetHandler:IsSyncedCode() then return false end

-- vb_build.txt is written into the archive by build_sdz.py: "<date-time>-<content hash>".
-- Reading it through the VFS gives the stamp of the archive that is MOUNTED, whatever other copies exist on disk.
function gadget:Initialize()
	local st = VFS.LoadFile("vb_build.txt")
	st = (type(st) == "string" and st:gsub("%s+", "") or "") 
	if st == "" then st = "unknown" end
	Spring.Echo("[VB] build " .. st)
	Spring.SetGameRulesParam("vb_build", st, { public = true })
end
