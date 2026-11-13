--[[
  Voidborn developer console: autocomplete, autofill and syntax highlighting.

  Shared by every /vb* command, not just /vbcreate:
    * completion of command names          /vbcre<tab>      -> /vbcreate
    * completion of option keys            base=<tab>       -> base=
    * completion of option values          base=ch_<tab>    -> base=ch_hoplite
    * completion of template ids           /vbspawn dre<tab>
    * completion of png file names         png=dre<tab>
    * syntax highlighting of the whole input line
    * an inline "ghost" hint showing the rest of the best candidate

  The data providers (unit names, template ids, png files) are supplied by the
  caller so this header stays free of any global state.
]]

local M = {}

--------------------------------------------------------------------------------
-- colour palette
--------------------------------------------------------------------------------
M.COL = {
  cmd    = { 0.35, 0.85, 1.00 },  -- /vbcreate ...
  opt    = { 1.00, 0.82, 0.30 },  -- key=          (option name)
  num    = { 0.45, 1.00, 0.55 },  -- 1234          (number)
  str    = { 0.72, 1.00, 0.58 },  -- "text"        (quoted string)
  unit   = { 1.00, 0.62, 0.32 },  -- ch_hoplite    (known unit name)
  tmpl   = { 1.00, 0.55, 0.88 },  -- dread         (saved template id)
  code   = { 0.85, 0.62, 1.00 },  -- lua=...      (inline Lua code)
  plain  = { 0.86, 0.88, 0.93 },  -- everything else
  ghost  = { 0.42, 0.48, 0.60 },  -- the inline completion hint
  bad    = { 1.00, 0.35, 0.35 },  -- unknown option / unit
}

--------------------------------------------------------------------------------
-- command table: every /vb* command of the developer console
--------------------------------------------------------------------------------
M.commands = {
  vbhelp     = { desc = "this help" },
  vbunits    = { desc = "list the selected units" },
  vbwidgets  = { desc = "list all known widgets" },
  vbclear    = { desc = "clear the console output" },
  vbautomex  = { desc = "explain the auto mex gadget" },
  vbexec     = { desc = "run a Lua snippet (vb.create / vb.spawn are available)" },
  vbcreate   = { desc = "create a new unit from a base unit",
                 opts = { "id", "base", "name", "hp", "metal", "energy", "buildtime", "sight",
                          "speed", "range", "dmg", "reload", "alt", "count", "team", "x", "z",
                          "png", "pngsize", "lua" } },
  vbspawn    = { desc = "spawn more units from a saved template",
                 opts = { "id", "count", "team" } },
  vbtemplates = { desc = "list the saved templates" },
  vbforget   = { desc = "delete a saved template", opts = { "id" } },
  vbbases    = { desc = "list every base unit name" },
  vbconsole  = { desc = "open / close this console" },
}

-- options whose value is a unit name
M.unitOpts = { base = true }
-- options whose value is a png file name
M.pngOpts  = { png = true }
-- options whose value is a saved template id
M.tmplOpts = { id = true }

--------------------------------------------------------------------------------
-- small string helpers
--------------------------------------------------------------------------------
local function lower(s) return (tostring(s):lower()) end

-- split the input into words, keeping track of the start offset of each word and
-- whether it was quoted.  Used for completion and for highlighting.
function M.Words(line)
  local words, i, n = {}, 1, #line
  while i <= n do
    local ch = line:sub(i, i)
    if ch:match("%s") then
      i = i + 1
    else
      local start = i
      local quoted = false
      local text = ""
      while i <= n and not line:sub(i, i):match("%s") do
        local c = line:sub(i, i)
        if c == '"' then
          quoted = true
          local j = line:find('"', i + 1, true) or (n + 1)
          text = text .. line:sub(i + 1, j - 1)
          i = j + 1
        else
          text = text .. c
          i = i + 1
        end
      end
      words[#words + 1] = { text = text, start = start, stop = i - 1, quoted = quoted }
    end
  end
  return words
end

-- the word the cursor sits in, plus its index
function M.WordAt(line, cursor)
  local words = M.Words(line)
  local idx, best
  for i, w in ipairs(words) do
    if cursor >= w.start and cursor <= w.stop + 1 then
      best = i
      break
    end
    best = i
  end
  if not words[best] then return nil, words end
  return words[best], words, best
end

--------------------------------------------------------------------------------
-- candidate providers (supplied by the caller)
--------------------------------------------------------------------------------
-- providers = {
--   units   = function() return { "ch_hoplite", ... } end,   -- sorted list
--   templates = function() return { "dread", ... } end,
--   pngs    = function() return { "dread.png", ... } end,
-- }

local function prefixFilter(list, prefix)
  local out = {}
  local lp = lower(prefix)
  for _, v in ipairs(list or {}) do
    if v:sub(1, #lp):lower() == lp then out[#out + 1] = v end
  end
  return out
end
M.prefixFilter = prefixFilter

-- The option key that the current word belongs to (e.g. "base" for "base=ch_"),
-- or nil when the word is a bare value.
local function OptionKeyOf(word)
  if not word then return nil end
  local k = word.text:match("^([%w_]+)=")
  return k and lower(k) or nil
end
M.OptionKeyOf = OptionKeyOf

-- The command the line is running (the first word, without the slash).
function M.CommandOf(line)
  local w = line:match("^%s*(%S+)")
  if not w then return nil end
  w = lower(w):gsub("^/", "")
  return w
end

-- Every completion candidate for the current cursor position.
-- Returns a list of { text = <replacement for the current word>, kind = <label> }
function M.Candidates(line, cursor, providers)
  providers = providers or {}
  local word, words, wIndex = M.WordAt(line, cursor or #line)
  if not word then return {} end

  local cmd = M.CommandOf(line)
  local cmdDef = cmd and M.commands[cmd]
  local opts = cmdDef and cmdDef.opts or {}

  -- first word: the command itself
  if (wIndex or 1) == 1 then
    local cands = {}
    for name in pairs(M.commands) do cands[#cands + 1] = name end
    table.sort(cands)
    local out = {}
    -- strip leading '/' from word text for prefix matching
    local wtext = word.text:gsub("^/", "")
    for _, c in ipairs(prefixFilter(cands, wtext)) do
      out[#out + 1] = { text = "/" .. c, kind = "command" }
    end
    return out
  end

  -- the word is the value of an option
  local key = OptionKeyOf(word)
  if key then
    local bare = word.text:match("^([%w_]+)=(.*)$")
    -- bare is the option key (e.g. "base"), value is after the '='
    local value = word.text:sub(#bare + 2)
    local list, kind
    if M.unitOpts[key] then list, kind = providers.units and providers.units(), "unit"
    elseif M.pngOpts[key] then list, kind = providers.pngs and providers.pngs(), "png"
    elseif M.tmplOpts[key] then list, kind = providers.templates and providers.templates(), "template"
    end
    if list then
      local out = {}
      for _, c in ipairs(prefixFilter(list, value)) do
        out[#out + 1] = { text = key .. "=" .. c, kind = kind }
      end
      return out
    end
    -- unknown option: offer the known ones that start with what was typed
    local out = {}
    for _, o in ipairs(opts) do
      if o:sub(1, #value):lower() == value:lower() then
        out[#out + 1] = { text = key .. "=" .. o .. "=", kind = "option" }
      end
    end
    return out
  end

  -- bare word: an option name (with or without '='), a template id or a unit name
  local out = {}
  local typed = word.text
  local eq = typed:find("=")
  local head = eq and typed:sub(1, eq - 1) or typed
  local hasEq = eq ~= nil

  -- option names
  for _, o in ipairs(opts) do
    if o:sub(1, #head):lower() == head:lower() then
      out[#out + 1] = { text = hasEq and (head .. "=" .. o .. "=") or (o .. "="), kind = "option" }
    end
  end

  -- template ids (for /vbspawn, /vbforget, and the id= option)
  if providers.templates then
    for _, t in ipairs(prefixFilter(providers.templates(), typed)) do
      out[#out + 1] = { text = t, kind = "template" }
    end
  end

  -- unit names (only when the command takes a base unit and nothing matched yet)
  if cmd == "vbcreate" and providers.units and #out == 0 then
    for _, u in ipairs(prefixFilter(providers.units(), typed)) do
      out[#out + 1] = { text = u, kind = "unit" }
    end
  end

  return out
end

--------------------------------------------------------------------------------
-- syntax highlighting
--------------------------------------------------------------------------------
-- Split a line into coloured segments.
-- returns { { text = "...", col = { r, g, b }, start = <char offset> }, ... }
function M.Highlight(line, providers)
  providers = providers or {}
  local segs = {}
  local function Push(text, col, start)
    if text == "" then return end
    segs[#segs + 1] = { text = text, col = col, start = start }
  end

  local words = M.Words(line)
  local cmdDone = false
  local pos = 1   -- current character offset in the line

  for _, w in ipairs(words) do
    -- the whitespace in front of this word
    local gap = line:sub(pos, w.start - 1)
    if gap ~= "" then Push(gap, M.COL.plain, pos); pos = w.start end

    local txt = w.text
    if not cmdDone then
      Push(txt, M.COL.cmd, w.start)
      cmdDone = true
    else
      local key = OptionKeyOf(w)
      if key then
        local bare = w.text:match("^([%w_]+)=(.*)$")
        -- bare is the option key (e.g. "base"), value is everything after '='
        local eqPart = bare and bare .. "=" or ""
        local value = w.text:sub(#bare + 2)
        -- if the original word was quoted, preserve the quotes in the highlight
        if w.quoted then value = '"' .. value .. '"' end
        Push(eqPart, M.COL.opt, w.start)
        if value ~= "" then
          local col = M.COL.plain
          if M.unitOpts[key] and providers.isUnit and providers.isUnit(value) then
            col = M.COL.unit
          elseif M.tmplOpts[key] and providers.isTemplate and providers.isTemplate(value) then
            col = M.COL.tmpl
          elseif value:match("^%-?%d+%.?%d*$") then
            col = M.COL.num
          elseif value:find('"') or w.quoted then
            col = M.COL.str
          elseif key == "lua" then
            col = M.COL.code
          end
          Push(value, col, w.start + #eqPart)
        end
      else
        local col = M.COL.plain
        if providers.isUnit and providers.isUnit(txt) then col = M.COL.unit
        elseif providers.isTemplate and providers.isTemplate(txt) then col = M.COL.tmpl
        elseif txt:match("^%-?%d+%.?%d*$") then col = M.COL.num
        end
        Push(txt, col, w.start)
      end
    end
    pos = w.stop + 1
  end
  -- trailing whitespace
  if pos <= #line then Push(line:sub(pos), M.COL.plain, pos) end
  return segs
end

return M
