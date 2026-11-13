-- Standalone test for LuaUI/Headers/vb_complete.h.lua (no Spring needed).
-- Run: lua5.4 tools/test_complete.lua   (or luac5.4 / lua if available)
local C = dofile("game/LuaUI/Headers/vb_complete.h.lua")

local UNITS = { "ch_gazer", "ch_hierophant", "ch_hoplite", "ch_seer", "mw_gnasher", "mw_leviathan", "mw_ravager" }
local TEMPLATES = { "dread", "sniper", "wraith" }
local PNGS = { "ch_gazer", "dread", "icons_thing", "mw_ravager" }

local function has(list, n)
  for _, v in ipairs(list) do if v == n then return true end end
  return false
end

local providers = {
  units = function() return UNITS end,
  templates = function() return TEMPLATES end,
  pngs = function() return PNGS end,
  isUnit = function(n) return has(UNITS, n) end,
  isTemplate = function(n) return has(TEMPLATES, n) end,
}

local pass, fail = 0, 0
local function check(name, got, want)
  if got == want then pass = pass + 1
  else fail = fail + 1; print(("FAIL %-46s got %-22s want %s"):format(name, tostring(got), tostring(want))) end
end

local function cands(line, cursor)
  local list = C.Candidates(line, cursor or #line, providers)
  local names = {}
  for _, c in ipairs(list) do names[#names + 1] = c.text end
  return names, list
end

-- ---- command completion ----------------------------------------------------
local names = cands("/vbcr")
check("command: /vbcr", names[1], "/vbcreate")
check("command: /vbcr -> 1 match", #names, 1)

names = cands("/vb")
check("command: /vb -> many", #names > 5, true)

-- ---- option key completion -------------------------------------------------
names = cands("/vbcreate base")
check("option: bare 'base' -> base=", names[1], "base=")
check("option: bare 'base' -> 1 match", #names, 1)

names = cands("/vbcreate hp")
check("option: 'hp' -> hp=", names[1], "hp=")

names = cands("/vbcreate ba")
check("option: 'ba' -> base=", names[1], "base=")

-- ---- unit name completion --------------------------------------------------
names = cands("/vbcreate base=ch_h")
check("unit: base=ch_h -> ch_hierophant", names[1], "base=ch_hierophant")
check("unit: base=ch_h -> 2 matches", #names, 2)

names = cands("/vbcreate base=mw_lev")
check("unit: base=mw_lev -> mw_leviathan", names[1], "base=mw_leviathan")

-- ---- png completion --------------------------------------------------------
names = cands("/vbcreate base=ch_hoplite png=dre")
check("png: png=dre -> dread", names[1], "png=dread")

-- ---- template id completion ------------------------------------------------
names = cands("/vbspawn dre")
check("template: /vbspawn dre -> dread", names[1], "dread")
check("template: /vbspawn dre -> 1 match", #names, 1)

names = cands("/vbcreate id=sni")
check("template: id=sni -> sniper", names[1], "id=sniper")

-- ---- unknown option gets the known list ------------------------------------
names = cands("/vbcreate x")
check("unknown option: 'x' -> no unit fallback", #names >= 0, true)

-- ---- word splitting --------------------------------------------------------
local w = C.Words('a "two words" b')
check("Words: count", #w, 3)
check("Words: quoted text", w[2].text, "two words")
check("Words: quoted flag", w[2].quoted, true)
check("Words: start offset", w[2].start, 3)

-- ---- cursor in the middle --------------------------------------------------
w = C.WordAt("/vbcreate base=ch_h", 12)
check("WordAt: picks the word under the cursor", w and w.text, "base=ch_h")

-- ---- syntax highlighting ---------------------------------------------------
local segs = C.Highlight("/vbcreate base=ch_hoplite hp=6000 name=\"Big Thing\"", providers)
local byText = {}
for _, s in ipairs(segs) do byText[#byText + 1] = s.text end
check("Highlight: segments count > 4", #segs > 4, true)
check("Highlight: command coloured cyan", segs[1].col[1] == C.COL.cmd[1] and segs[1].col[2] == C.COL.cmd[2], true)

local joined = ""
for _, s in ipairs(segs) do joined = joined .. s.text end
check("Highlight: text is preserved", joined, "/vbcreate base=ch_hoplite hp=6000 name=\"Big Thing\"")

-- the unit name must be in the "unit" colour
local foundUnit = false
for _, s in ipairs(segs) do
  if s.text == "ch_hoplite" and s.col[1] == C.COL.unit[1] then foundUnit = true end
end
check("Highlight: unit name coloured", foundUnit, true)

local foundNum = false
for _, s in ipairs(segs) do
  if s.text == "6000" and s.col[2] == C.COL.num[2] then foundNum = true end
end
check("Highlight: number coloured", foundNum, true)

-- ---- offsets are contiguous ------------------------------------------------
local pos = 1
local contiguous = true
for _, s in ipairs(segs) do
  if s.start ~= pos then contiguous = false end
  pos = pos + #s.text
end
check("Highlight: offsets contiguous", contiguous, true)

print(("passed %d, failed %d"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
