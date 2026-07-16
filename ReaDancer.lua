--[[
  ReaDancer: a dancing character for REAPER, on ReaImGui.
  See FORMAT.md for the character pack format (version 1) this loader implements,
  and DESIGN.md for how the rest is built.

  Loads classic Fruity Dance packs and the extended format, renders the character
  transparent and chrome-less, and animates it tempo-synced. Moves can be picked
  by hand, followed from the arrangement (regions/markers), or triggered by MIDI
  notes on a track. All controls live in the right-click menu.
]]--

local FORMAT_VERSION = 1
local EXT_NAMESPACE  = 'ReaDancer'

-- Speed multiplier presets (tempo multiplier for the dance loop)
local SPEEDS = { 0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0 }
local function fmtSpeed(v) return ('%gx'):format(v) end

------------------------------------------------------------------------
-- small helpers
------------------------------------------------------------------------

local function trim(s)
  return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function floor(x) return math.floor(x) end

-- split "Foo.png" into dir, base ("Foo"), and the sibling ".txt" path
local function pathParts(path)
  local dir, file = path:match('^(.*[/\\])([^/\\]+)$')
  if not dir then dir, file = '', path end
  local base = file:gsub('%.[^.]+$', '')
  return dir, base
end

local function siblingTxt(pngPath)
  local dir, base = pathParts(pngPath)
  return dir .. base .. '.txt'
end

local function readLines(path)
  local f = io.open(path, 'r')
  if not f then return nil end
  local lines = {}
  for line in f:lines() do
    lines[#lines + 1] = (line:gsub('[\r\n]+$', ''))
  end
  f:close()
  return lines
end

------------------------------------------------------------------------
-- loader
------------------------------------------------------------------------

local loader = {}

-- Parse the .txt into { version, cols, beats, moves = {{name, frames?, beats?}} }.
-- Geometry and defaults are resolved later, once the image size is known.
local function parseTxt(lines, warnings)
  local parsed = { version = 0, cols = 8, beats = 1.0, moves = {} }

  -- mode selection: extended iff first non-blank line is the version header
  local firstIdx
  for i, line in ipairs(lines) do
    if trim(line) ~= '' then firstIdx = i break end
  end
  if firstIdx then
    local v = trim(lines[firstIdx]):match('^#readancer%s+(%d+)$')
    if v then
      parsed.version = tonumber(v)
      if parsed.version > FORMAT_VERSION then
        warnings[#warnings + 1] =
          ('pack declares #readancer %d, newer than this loader (%d); parsing best-effort')
          :format(parsed.version, FORMAT_VERSION)
      end
    end
  end

  local extended = parsed.version > 0

  for _, raw in ipairs(lines) do
    local line = trim(raw)
    if line == '' then
      -- ignored
    elseif not extended then
      -- classic: every non-empty line is a move name, verbatim
      parsed.moves[#parsed.moves + 1] = { name = (raw:gsub('[\r\n]+$', '')) }
    else
      local first = line:sub(1, 1)
      if first == '#' then
        local second = line:sub(2, 2)
        if second == '' or second == ' ' then
          -- comment, ignored
        else
          -- directive
          local key, val = line:match('^#([%w_%-]+)%s*(.*)$')
          key = key and key:lower() or ''
          val = trim(val or '')
          if key == 'readancer' then
            -- already handled
          elseif key == 'cols' then
            local n = tonumber(val)
            if n and n >= 1 then parsed.cols = floor(n)
            else warnings[#warnings + 1] = ('bad #cols value: %q'):format(val) end
          elseif key == 'beats' then
            local n = tonumber(val)
            if n and n > 0 then parsed.beats = n
            else warnings[#warnings + 1] = ('bad #beats value: %q'):format(val) end
          else
            warnings[#warnings + 1] = ('unknown directive: #%s'):format(key)
          end
        end
      else
        -- move line, optionally "NAME | key=value ..."
        local name, attrs = line, nil
        local sep = line:find(' | ', 1, true)
        if sep then
          name  = trim(line:sub(1, sep - 1))
          attrs = line:sub(sep + 3)
        end
        local move = { name = name }
        if attrs then
          for tok in attrs:gmatch('%S+') do
            local k, v = tok:match('^([%w_%-]+)=(.+)$')
            k = k and k:lower()
            if k == 'frames' then
              move.frames = tonumber(v)
            elseif k == 'beats' then
              move.beats = tonumber(v)
            elseif k then
              warnings[#warnings + 1] = ('unknown attribute on %q: %s'):format(name, tok)
            end
          end
        end
        parsed.moves[#parsed.moves + 1] = move
      end
    end
  end

  return parsed
end

-- Returns character table or nil, errorMessage.
function loader.load(pngPath)
  local warnings = {}

  local ok, image = pcall(reaper.ImGui_CreateImage, pngPath)
  if not ok or not image then
    return nil, 'could not open image: ' .. pngPath
  end
  local imgW, imgH = reaper.ImGui_Image_GetSize(image)

  local txtPath = siblingTxt(pngPath)
  local lines = readLines(txtPath)

  local parsed
  if not lines then
    warnings[#warnings + 1] = 'no .txt found, assuming a single "Held" strip'
    parsed = { version = 0, cols = 8, beats = 1.0, moves = { { name = 'Held' } } }
  else
    parsed = parseTxt(lines, warnings)
    if #parsed.moves == 0 then
      return nil, '.txt has no move lines: ' .. txtPath
    end
  end

  local cols = parsed.cols
  local rows = #parsed.moves
  local cellW = floor(imgW / cols)
  local cellH = floor(imgH / rows)
  if imgW % cols ~= 0 then
    warnings[#warnings + 1] = ('image width %d not divisible by %d columns'):format(imgW, cols)
  end
  if imgH % rows ~= 0 then
    warnings[#warnings + 1] = ('image height %d not divisible by %d rows'):format(imgH, rows)
  end

  -- finalize per-move defaults and clamps
  local heldIndex
  for i, m in ipairs(parsed.moves) do
    m.row    = i - 1
    m.frames = m.frames and floor(m.frames) or cols
    if m.frames > cols then
      warnings[#warnings + 1] = ('%q: frames %d > cols %d, clamping'):format(m.name, m.frames, cols)
      m.frames = cols
    elseif m.frames < 1 then
      m.frames = 1
    end
    m.beats = m.beats or parsed.beats
    if m.name:lower() == 'held' then heldIndex = i end
  end
  if not heldIndex then
    heldIndex = rows
    warnings[#warnings + 1] = 'no "Held" row, using the last row as the idle pose'
  end

  return {
    version   = parsed.version,
    path      = pngPath,
    image     = image,
    imgW      = imgW, imgH = imgH,
    cols      = cols, rows = rows,
    cellW     = cellW, cellH = cellH,
    beats     = parsed.beats,
    moves     = parsed.moves,
    heldIndex = heldIndex,
    warnings  = warnings,
  }
end

------------------------------------------------------------------------
-- engine: transport to (moveIndex, frame); section name to move
------------------------------------------------------------------------

local engine = {}

-- Returns (row, frame) for the given applied move selection. Tempo-synced: the
-- frame is a stateless function of the transport position in quarter notes.
function engine.compute(char, sel, speed, playing, qn)
  if not playing then
    return char.moves[char.heldIndex].row, 0
  end
  local move   = char.moves[sel] or char.moves[char.heldIndex]
  local loopQN = move.beats / speed
  local frame  = floor((qn / loopQN) * move.frames) % move.frames
  return move.row, frame
end

-- Section-following: match a section name (region/marker) to a move by
-- name. Case-insensitive and whitespace-trimmed; an exact match wins, otherwise
-- a move whose name is the leading word of the section (so a move "Drop" also
-- covers a section "Drop 2"). Returns the move index, or nil if nothing matches.
function engine.matchMove(char, name)
  local key = trim(name):lower()
  if key == '' then return nil end
  local prefix, prefixLen
  for i, m in ipairs(char.moves) do
    local mn = trim(m.name):lower()
    if mn == key then return i end
    if mn ~= '' and key:sub(1, #mn + 1) == mn .. ' ' and (not prefixLen or #mn > prefixLen) then
      prefix, prefixLen = i, #mn  -- longest (most specific) leading-word match wins
    end
  end
  return prefix
end

-- Resolve a section name to a move index using the user's section-to-move map,
-- falling back to auto name-matching. `map` is keyed by the normalised section
-- name; a value is a move name, `''` means "explicitly none", and a missing key
-- means "auto". Returns the move index, or nil.
function engine.resolveSection(char, sectionName, map)
  local key = trim(sectionName):lower()
  if key == '' then return nil end
  local mapped = map and map[key]
  if mapped == nil then return engine.matchMove(char, sectionName) end
  if mapped == '' then return nil end
  local target = trim(mapped):lower()
  for i, m in ipairs(char.moves) do
    if trim(m.name):lower() == target then return i end
  end
  return nil
end

-- Cycle a section's mapping value to the next in: auto (nil) to each move to
-- none ('') to auto. Used by the flat menu's click-to-cycle rows.
function engine.cycleSection(char, cur)
  if cur == nil then return char.moves[1] and char.moves[1].name or '' end
  if cur == '' then return nil end
  local key = trim(cur):lower()
  for i, m in ipairs(char.moves) do
    if trim(m.name):lower() == key then
      return char.moves[i + 1] and char.moves[i + 1].name or ''
    end
  end
  return nil  -- unknown, back to auto
end

-- Same order, backwards: auto to none to moveN .. move1 to auto. For the '<'
-- arrow in the section list.
function engine.cycleSectionBack(char, cur)
  if cur == nil then return '' end
  if cur == '' then return char.moves[#char.moves] and char.moves[#char.moves].name or nil end
  local key = trim(cur):lower()
  for i, m in ipairs(char.moves) do
    if trim(m.name):lower() == key then
      return (i > 1) and char.moves[i - 1].name or nil
    end
  end
  return nil
end

-- Map a MIDI note pitch to a move index: baseNote plays move 1, each semitone up
-- is the next move (piano-roll triggering). Returns the index, or nil if the
-- pitch is outside the pack's move range.
function engine.noteToMove(rows, pitch, baseNote)
  local idx = pitch - baseNote + 1
  if idx >= 1 and idx <= rows then return idx end
  return nil
end

------------------------------------------------------------------------
-- renderer: draw one cell at a fixed display height, alpha preserved
------------------------------------------------------------------------

local renderer = {}

-- displayed at `dispH` pixels tall, width from the cell aspect ratio. Drawn as
-- an ImGui_Image (a layout item) so the window can auto-size to it, and
-- its size is independent of the control strip.
function renderer.draw(ctx, char, row, frame, dispH)
  local cw, ch = char.cellW, char.cellH
  local h = dispH
  local w = dispH * (cw / ch)

  local u0 = (frame * cw) / char.imgW
  local v0 = (row * ch) / char.imgH
  local u1 = (frame * cw + cw) / char.imgW
  local v1 = (row * ch + ch) / char.imgH

  reaper.ImGui_Image(ctx, char.image, w, h, u0, v0, u1, v1)
end

------------------------------------------------------------------------
-- ui / main loop
------------------------------------------------------------------------

if not reaper.ImGui_CreateContext then
  reaper.MB('ReaDancer needs the ReaImGui extension.\n' ..
            'Install it via ReaPack (Browse packages, search "ReaImGui").',
            'ReaDancer', 0)
  return
end

local ctx = reaper.ImGui_CreateContext('ReaDancer')

local state = {
  char        = nil,
  selected    = 1,     -- applied move index
  pending     = nil,   -- requested move index, waiting on sync
  savedSel    = nil,   -- selected index restored from ExtState, applied on auto-load
  speed       = 1.0,
  syncChanges = false,
  pin         = false, -- keep window always on top
  dispH       = 240,   -- dancer display height in px (mouse-wheel zoom)
  followSections = false, -- pick the move from the region/marker section
  sectionMap  = {},    -- normalised section name to move name ('' = none)
  midiTrigger = false, -- pick the move from MIDI notes on a trigger track
  triggerGUID = '',    -- GUID of the trigger track
  midiIdle    = false, -- when no note is playing: idle (true) or hold last move (false)
  lastFrame   = 0,
  status      = 'Load a character (.png) to start.',
}

local BASE_NOTE = 60  -- MIDI note 60 (middle C) triggers move 1, ascending from there

local wantClose = false  -- set by the context menu's Close item

-- section map to/from string: "section\tmove" lines joined by newlines
local function serializeMap(m)
  local parts = {}
  for k, v in pairs(m) do parts[#parts + 1] = k .. '\t' .. v end
  return table.concat(parts, '\n')
end

local function deserializeMap(s)
  local m = {}
  for line in s:gmatch('[^\n]+') do
    local k, v = line:match('^(.-)\t(.*)$')
    if k then m[k] = v end
  end
  return m
end

-- persistence: restore on launch, save on exit
local function restoreSettings()
  local sp = tonumber(reaper.GetExtState(EXT_NAMESPACE, 'speed'))
  if sp then state.speed = sp end
  state.syncChanges   = reaper.GetExtState(EXT_NAMESPACE, 'sync') == '1'
  state.pin           = reaper.GetExtState(EXT_NAMESPACE, 'pin')  == '1'
  state.followSections = reaper.GetExtState(EXT_NAMESPACE, 'sections') == '1'
  state.sectionMap    = deserializeMap(reaper.GetExtState(EXT_NAMESPACE, 'map'))
  state.midiTrigger   = reaper.GetExtState(EXT_NAMESPACE, 'midi') == '1'
  state.triggerGUID   = reaper.GetExtState(EXT_NAMESPACE, 'miditrack')
  state.midiIdle      = reaper.GetExtState(EXT_NAMESPACE, 'mididle') == '1'
  local sz = tonumber(reaper.GetExtState(EXT_NAMESPACE, 'size'))
  if sz then state.dispH = sz end
  state.savedSel    = tonumber(reaper.GetExtState(EXT_NAMESPACE, 'selected'))
end

local function saveSettings()
  reaper.SetExtState(EXT_NAMESPACE, 'speed',    tostring(state.speed), true)
  reaper.SetExtState(EXT_NAMESPACE, 'sync',     state.syncChanges and '1' or '0', true)
  reaper.SetExtState(EXT_NAMESPACE, 'pin',      state.pin and '1' or '0', true)
  reaper.SetExtState(EXT_NAMESPACE, 'sections', state.followSections and '1' or '0', true)
  reaper.SetExtState(EXT_NAMESPACE, 'map',      serializeMap(state.sectionMap), true)
  reaper.SetExtState(EXT_NAMESPACE, 'midi',     state.midiTrigger and '1' or '0', true)
  reaper.SetExtState(EXT_NAMESPACE, 'miditrack', state.triggerGUID, true)
  reaper.SetExtState(EXT_NAMESPACE, 'mididle',  state.midiIdle and '1' or '0', true)
  reaper.SetExtState(EXT_NAMESPACE, 'size',     tostring(math.floor(state.dispH)), true)
  reaper.SetExtState(EXT_NAMESPACE, 'selected', tostring(state.selected), true)
end

local function loadCharacter(path, keepSel)
  local char, err = loader.load(path)
  if not char then
    state.status = 'Error: ' .. err
    return
  end
  state.char = char
  if keepSel and state.savedSel and char.moves[state.savedSel] then
    state.selected = state.savedSel
  else
    state.selected = char.heldIndex
  end
  state.pending  = nil
  reaper.SetExtState(EXT_NAMESPACE, 'lastPath', path, true)
  if #char.warnings > 0 then
    state.status = ('Loaded %s (%d moves, %d cols), %d warning(s)')
      :format(select(2, pathParts(path)), char.rows, char.cols, #char.warnings)
  else
    state.status = ('Loaded %s (%d moves, %d cols)')
      :format(select(2, pathParts(path)), char.rows, char.cols)
  end
end

local function pickFile()
  local ok, path = reaper.GetUserFileNameForRead('', 'ReaDancer: pick a character image', '.png')
  if ok then loadCharacter(path) end
end

-- Unique named sections (regions + markers) in the project, for the config menu.
local function projectSections()
  local list, seen = {}, {}
  local i = 0
  while true do
    local retval, _, _, _, name = reaper.EnumProjectMarkers3(0, i)
    if not retval or retval == 0 then break end
    if name and name ~= '' then
      local key = trim(name):lower()
      if not seen[key] then seen[key] = true; list[#list + 1] = trim(name) end
    end
    i = i + 1
  end
  return list
end

-- Find a track by its stored GUID (no SWS dependency: scan all tracks).
local function trackByGUID(guid)
  if not guid or guid == '' then return nil end
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    if reaper.GetTrackGUID(tr) == guid then return tr end
  end
  return nil
end

local function trackName(tr)
  if not tr then return nil end
  local _, name = reaper.GetTrackName(tr)
  return name
end

local midiErr = nil  -- last error from the MIDI scan, shown in the menu for debug

-- Pitch of the MIDI note active at project time `pos` on the trigger track: scans
-- the track's MIDI takes for a note whose span contains `pos`; if several are
-- active, the highest pitch wins. Returns the pitch, or nil. Wrapped so a bad
-- API call surfaces as text instead of freezing the defer loop.
local function activeTriggerPitch(pos)
  local tr = trackByGUID(state.triggerGUID)
  if not tr then return nil end
  local ok, result = pcall(function()
    local best
    for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
      local item   = reaper.GetTrackMediaItem(tr, i)
      local istart = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
      local ilen   = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
      if pos >= istart and pos < istart + ilen then
        local take = reaper.GetActiveTake(item)
        if take and reaper.TakeIsMIDI(take) then
          local ppq = reaper.MIDI_GetPPQPosFromProjTime(take, pos)
          local _, notes = reaper.MIDI_CountEvts(take)
          for n = 0, notes - 1 do
            local rv, _, muted, startppq, endppq, _, pitch = reaper.MIDI_GetNote(take, n)
            if rv and not muted and startppq <= ppq and ppq < endppq then
              if not best or pitch > best then best = pitch end
            end
          end
        end
      end
    end
    return best
  end)
  if ok then midiErr = nil; return result end
  midiErr = tostring(result)
  return nil
end

-- right-click menu: the only control surface. Everything lives here.

local ROW_ROUND = 6  -- corner radius shared by the menu rows, badges and highlights

-- menu colours, 0xRRGGBBAA
local WHITE       = 0xFFFFFFFF  -- highlight fill and normal text
local BLACK       = 0x000000FF  -- text on a white highlight
local OUTLINE     = 0x666666FF  -- badge and section-row outline
local DIVIDER     = 0x505050FF  -- divider line
local ARROW_IDLE  = 0xAAAAAAFF  -- inactive arrow triangle
local TRANSPARENT = 0x00000000  -- transparent window background and border

-- Tooltip with a rounded border (WindowRounding, so the border follows the
-- corners) and a fixed width + wrap, so switching between tooltips doesn't reuse
-- the previous one's size.
local function tip(text)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(),   6)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_PopupRounding(),    6)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowBorderSize(), 0)  -- no 1px border to break at the corners
  reaper.ImGui_SetNextWindowSize(ctx, 240, 0)
  if reaper.ImGui_BeginTooltip(ctx) then
    reaper.ImGui_PushTextWrapPos(ctx, 0)   -- wrap at the (fixed) window width
    reaper.ImGui_Text(ctx, text)
    reaper.ImGui_PopTextWrapPos(ctx)
    reaper.ImGui_EndTooltip(ctx)
  end
  reaper.ImGui_PopStyleVar(ctx, 3)
end

-- Tooltips only appear after the mouse rests on the same item for TIP_DELAY
-- seconds; the timer resets when moving to another item, so sweeping the menu
-- quickly never flashes tooltips (and the size-reuse artifact can't happen).
local TIP_DELAY = 0.8
local tipKey, tipStart, tipSeen = nil, 0, false
local function maybeTip(key, text)
  tipSeen = true
  local now = reaper.time_precise()
  if tipKey ~= key then
    tipKey, tipStart = key, now
  elseif now - tipStart >= TIP_DELAY then
    tip(text)
  end
end

-- A leaf menu row: rounded white highlight on hover/selected with inverted
-- (black) text, thin, keeps the menu open (InvisibleButton never closes popups).
-- Optional tooltip. Returns true if clicked.
local function row(id, label, selected, tooltip)
  local dl = reaper.ImGui_GetWindowDrawList(ctx)
  local tw, th = reaper.ImGui_CalcTextSize(ctx, label)
  local padx, pady = 8, 3
  local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
  local availW = reaper.ImGui_GetContentRegionAvail(ctx)
  local w = math.max(availW, tw + padx * 2)
  local h = th + pady * 2
  local clicked = reaper.ImGui_InvisibleButton(ctx, '##' .. id, w, h)
  local hovered = reaper.ImGui_IsItemHovered(ctx)
  local on = hovered or selected
  if on then
    reaper.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, WHITE, ROW_ROUND)
  end
  local tcol = on and BLACK or WHITE  -- black on the white highlight, else white
  reaper.ImGui_DrawList_AddText(dl, x + padx, y + pady, tcol, label)
  if hovered and tooltip then maybeTip(id, tooltip) end
  return clicked
end

-- Native checkbox (per request) with a hover tooltip. Returns the new value.
local function checkRow(label, value, tooltip)
  local _, v = reaper.ImGui_Checkbox(ctx, label, value)
  if tooltip and reaper.ImGui_IsItemHovered(ctx) then maybeTip(label, tooltip) end
  return v
end

-- A chip drawn at a fixed width `w` (text centered): same white inverse
-- highlight as `row` when hovered/selected, a faint outline otherwise. Uniform
-- width lets badges line up in a clean grid. Returns true if clicked.
local BADGE_PADX, BADGE_PADY = 9, 3
local function badgeWidth(label)
  local tw = reaper.ImGui_CalcTextSize(ctx, label)
  return tw + BADGE_PADX * 2
end
local function badgeCell(id, label, selected, w)
  local dl = reaper.ImGui_GetWindowDrawList(ctx)
  local tw, th = reaper.ImGui_CalcTextSize(ctx, label)
  local h = th + BADGE_PADY * 2
  local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
  local clicked = reaper.ImGui_InvisibleButton(ctx, '##' .. id, w, h)
  local on = reaper.ImGui_IsItemHovered(ctx) or selected
  if on then
    reaper.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, WHITE, ROW_ROUND)
  else
    reaper.ImGui_DrawList_AddRect(dl, x, y, x + w, y + h, OUTLINE, ROW_ROUND, 0, 1.0)
  end
  local tcol = on and BLACK or WHITE
  reaper.ImGui_DrawList_AddText(dl, x + (w - tw) * 0.5, y + BADGE_PADY, tcol, label)
  return clicked
end

-- Fixed grid: uniform badge width (widest label) and `cols` per row, uniform
-- spacing. `items` is a list of labels; isSel(i)/onClick(i) drive selection.
local function badgeGrid(prefix, items, cols, isSel, onClick)
  local w = 0
  for _, l in ipairs(items) do local bw = badgeWidth(l); if bw > w then w = bw end end
  for i, label in ipairs(items) do
    if badgeCell(prefix .. i, label, isSel(i), w) then onClick(i) end
    if i < #items and (i % cols) ~= 0 then reaper.ImGui_SameLine(ctx, 0.0, 6) end
  end
end

-- Full-width divider (edge to edge, over the window padding) with equal gaps
-- above and below, so the spacing around it matches on both sides.
local DIV_GAP = 6
local function divider()
  reaper.ImGui_Dummy(ctx, 1, DIV_GAP)
  local wx = reaper.ImGui_GetWindowPos(ctx)
  local ww = reaper.ImGui_GetWindowSize(ctx)
  local _, cy = reaper.ImGui_GetCursorScreenPos(ctx)
  reaper.ImGui_DrawList_AddLine(reaper.ImGui_GetWindowDrawList(ctx), wx, cy, wx + ww, cy, DIVIDER, 1.0)
  reaper.ImGui_Dummy(ctx, 1, DIV_GAP)
end

local function pushMenuStyle()
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_PopupRounding(), 10)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(),  3)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(),  8, 6)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(),   6, 2)  -- thin rows
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(),    6, 3)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_CheckMark(), WHITE)   -- white check
end
local function popMenuStyle()
  reaper.ImGui_PopStyleColor(ctx, 1)
  reaper.ImGui_PopStyleVar(ctx, 5)
end

-- how a section's mapping is shown inline: auto / none / <move name>
local function targetLabel(cur)
  if cur == nil then return 'auto' end
  if cur == '' then return 'none' end
  return cur
end

-- corner-rounding flags for the arrow hover fills (fall back to square if absent)
local ROUND_L = (reaper.ImGui_DrawFlags_RoundCornersLeft  and reaper.ImGui_DrawFlags_RoundCornersLeft())  or 0
local ROUND_R = (reaper.ImGui_DrawFlags_RoundCornersRight and reaper.ImGui_DrawFlags_RoundCornersRight()) or 0

-- One section row: name on the left, and a right-aligned badge holding the
-- current move between two triangle arrows. Only the arrows are clickable
-- (prev/next); the middle move label is display-only. `moveW` is the shared
-- middle width so the badges line up in a column.
local function arrowZone(id, key, char, dir, x, y, w, h, dl, flags)
  local clicked = reaper.ImGui_InvisibleButton(ctx, id, w, h)
  local hov = reaper.ImGui_IsItemHovered(ctx)
  local ax, ay = reaper.ImGui_GetItemRectMin(ctx)
  if hov then
    local r, f = 0, 0
    if flags ~= 0 then r, f = ROW_ROUND, flags end
    reaper.ImGui_DrawList_AddRectFilled(dl, ax, ay, ax + w, ay + h, WHITE, r, f)
  end
  local c  = hov and BLACK or ARROW_IDLE
  local cy = ay + h * 0.5
  if dir < 0 then
    reaper.ImGui_DrawList_AddTriangleFilled(dl, ax + w - 5, cy - 4, ax + w - 5, cy + 4, ax + 5, cy, c)
  else
    -- same vertex winding as the left arrow so ImGui's AA matches (not jagged)
    reaper.ImGui_DrawList_AddTriangleFilled(dl, ax + 5, cy + 4, ax + 5, cy - 4, ax + w - 5, cy, c)
  end
  return clicked
end

local SEC_INSET = 8  -- extra padding of both columns from the menu borders
local function sectionSelector(sec, key, char, moveW)
  local triW, gap = 18, 6
  local ctrlW = triW + gap + moveW + gap + triW
  local _, th = reaper.ImGui_CalcTextSize(ctx, sec)
  local h = th + BADGE_PADY * 2

  reaper.ImGui_AlignTextToFramePadding(ctx)
  reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + SEC_INSET)  -- inset left column
  reaper.ImGui_Text(ctx, sec)                                   -- left: section name
  reaper.ImGui_SameLine(ctx)
  local avail = reaper.ImGui_GetContentRegionAvail(ctx)         -- right-align the badge
  if avail > ctrlW + SEC_INSET then
    reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + (avail - ctrlW - SEC_INSET))
  end

  local dl = reaper.ImGui_GetWindowDrawList(ctx)
  local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
  local cur  = state.sectionMap[key]
  reaper.ImGui_DrawList_AddRect(dl, x, y, x + ctrlW, y + h, OUTLINE, ROW_ROUND, 0, 1.0)

  local back = arrowZone('##secp' .. key, key, char, -1, x, y, triW, h, dl, ROUND_L)

  reaper.ImGui_SameLine(ctx, 0.0, gap)
  local mx, my = reaper.ImGui_GetCursorScreenPos(ctx)
  reaper.ImGui_Dummy(ctx, moveW, h)                            -- middle: not clickable
  local label = targetLabel(cur)
  local tw = reaper.ImGui_CalcTextSize(ctx, label)
  reaper.ImGui_DrawList_AddText(dl, mx + (moveW - tw) * 0.5, my + BADGE_PADY, WHITE, label)

  reaper.ImGui_SameLine(ctx, 0.0, gap)
  local fwd = arrowZone('##secn' .. key, key, char, 1, 0, 0, triW, h, dl, ROUND_R)

  if back then state.sectionMap[key] = engine.cycleSectionBack(char, cur) end
  if fwd  then state.sectionMap[key] = engine.cycleSection(char, cur) end
end

-- Flat menu: no flyout submenus, every item is a custom `row` (consistent white
-- inverse hover). Section assignment is click-to-cycle instead of a submenu.
local function drawContextMenu()
  pushMenuStyle()
  -- open on right-click over the dancer; the popup window is TopMost so it is
  -- never hidden behind the dancer when it overflows into its own OS window
  if reaper.ImGui_IsWindowHovered(ctx) and reaper.ImGui_IsMouseClicked(ctx, 1) then
    reaper.ImGui_OpenPopup(ctx, 'rdmenu')
  end
  local pflags = (reaper.ImGui_WindowFlags_TopMost and reaper.ImGui_WindowFlags_TopMost()) or 0
  if reaper.ImGui_BeginPopup(ctx, 'rdmenu', pflags) then
    tipSeen = false  -- cleared at the end if no tooltip item was hovered (resets delay)
    local char = state.char
    if char then
      reaper.ImGui_TextDisabled(ctx, 'MOVE')
      local moveNames = {}
      for i, m in ipairs(char.moves) do moveNames[i] = m.name end
      badgeGrid('mv', moveNames, 4,
        function(i) return i == (state.pending or state.selected) end,
        function(i) state.pending = i end)

      divider()
      reaper.ImGui_TextDisabled(ctx, 'SPEED')
      local speedLabels = {}
      for i, s in ipairs(SPEEDS) do speedLabels[i] = fmtSpeed(s) end
      badgeGrid('sp', speedLabels, 4,   -- 8 presets in 2 rows x 4 cols
        function(i) return SPEEDS[i] == state.speed end,
        function(i) state.speed = SPEEDS[i] end)

      divider()
      state.syncChanges = checkRow('Sync changes', state.syncChanges,
        'Wait for the loop to reach frame 0 before switching moves.')
      state.pin = checkRow('Pin on top', state.pin,
        'Keep the dancer window always on top.')
      state.followSections = checkRow('Follow sections', state.followSections,
        'Pick the move from the region/marker under the play cursor.')
      state.midiTrigger = checkRow('MIDI triggers', state.midiTrigger,
        'Trigger moves from MIDI notes on a track. Note 60 (middle C) plays move 1, each semitone up the next.')

      -- Section to move: shown only when Follow sections is on. Two columns:
      -- section name | < [current move] > to navigate the choices.
      if state.followSections then
        local secs = projectSections()
        divider()
        reaper.ImGui_TextDisabled(ctx, 'SECTION MAPPING')
        if #secs == 0 then
          reaper.ImGui_TextDisabled(ctx, '(no regions or markers)')
        else
          local moveW = math.max(badgeWidth('auto'), badgeWidth('none'))
          for _, m in ipairs(char.moves) do
            local bw = badgeWidth(m.name); if bw > moveW then moveW = bw end
          end
          for _, sec in ipairs(secs) do
            sectionSelector(sec, sec:lower(), char, moveW)
          end
        end
      end

      -- MIDI trigger track: shown only when MIDI triggers is on.
      if state.midiTrigger then
        divider()
        reaper.ImGui_TextDisabled(ctx, 'MIDI TRIGGER TRACK')
        local tr = trackByGUID(state.triggerGUID)
        reaper.ImGui_TextWrapped(ctx, tr and (trackName(tr) or '(unnamed)') or '(none set)')
        if row('midiset', 'Use selected track', false) then
          local sel = reaper.GetSelectedTrack(0, 0)
          if sel then state.triggerGUID = reaper.GetTrackGUID(sel) end
        end
        state.midiIdle = checkRow('Idle between notes', state.midiIdle,
          'When no note is playing, return to the idle pose instead of holding the last move.')
        -- live status: what note is detected right now and where it maps
        local dbg
        if not tr then
          dbg = 'no track set'
        elseif midiErr then
          dbg = 'error: ' .. midiErr
        else
          local pitch = activeTriggerPitch(reaper.GetPlayPosition())
          if pitch then
            local idx = engine.noteToMove(char.rows, pitch, BASE_NOTE)
            dbg = ('note %d: %s'):format(pitch, idx and char.moves[idx].name or 'out of range')
          else
            dbg = 'no active note'
          end
        end
        reaper.ImGui_TextDisabled(ctx, dbg)
      end
      divider()
    end
    if row('load', 'Load character...', false) then pickFile(); reaper.ImGui_CloseCurrentPopup(ctx) end
    if row('close', 'Close ReaDancer', false) then wantClose = true end
    if not tipSeen then tipKey = nil end  -- moved off every tooltip item, reset delay
    reaper.ImGui_EndPopup(ctx)
  end
  popMenuStyle()
end

-- No character yet: a small normal window with a Load button, since there's no
-- dancer to right-click on. Has a title bar so it can be moved and closed.
local function drawLoaderPanel()
  reaper.ImGui_SetNextWindowSize(ctx, 260, 0, reaper.ImGui_Cond_FirstUseEver())
  local visible, open = reaper.ImGui_Begin(ctx, 'ReaDancer', true)
  if visible then
    reaper.ImGui_TextWrapped(ctx, 'Pick a character sprite sheet to start dancing.')
    reaper.ImGui_Spacing(ctx)
    if reaper.ImGui_Button(ctx, 'Load character...') then pickFile() end
    if state.status and state.status ~= '' then
      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_TextDisabled(ctx, state.status)
    end
    reaper.ImGui_End(ctx)
  end
  return open
end

-- Name of the arrangement section at `pos`. A region containing the position
-- wins (innermost, i.e. latest-starting); if none, the most recent marker at or
-- before the position. Returns the name, or nil if there is none.
local function currentSection(pos)
  local i = 0
  local regName, regStart = nil, -math.huge
  local mkName,  mkPos    = nil, -math.huge
  while true do
    local retval, isrgn, mpos, rgnend, name = reaper.EnumProjectMarkers3(0, i)
    if not retval or retval == 0 then break end
    if isrgn then
      if pos >= mpos and pos < rgnend and mpos > regStart then
        regName, regStart = name, mpos
      end
    else
      if mpos <= pos and mpos > mkPos then
        mkName, mkPos = name, mpos
      end
    end
    i = i + 1
  end
  local name = regName or mkName
  if name and name ~= '' then return name end
  return nil
end

local function drawDancer()
  local flags = reaper.ImGui_WindowFlags_AlwaysAutoResize()
    | reaper.ImGui_WindowFlags_NoTitleBar()
    | reaper.ImGui_WindowFlags_NoScrollbar()
    | reaper.ImGui_WindowFlags_NoBackground()
    | reaper.ImGui_WindowFlags_NoCollapse()
  if state.pin and reaper.ImGui_WindowFlags_TopMost then
    flags = flags | reaper.ImGui_WindowFlags_TopMost()
  end

  reaper.ImGui_SetNextWindowBgAlpha(ctx, 0.0)  -- transparent (blur is the WM's, see notes)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), TRANSPARENT)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(),   TRANSPARENT)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 0, 0)

  local visible, open = reaper.ImGui_Begin(ctx, 'ReaDancer', true, flags)

  reaper.ImGui_PopStyleVar(ctx)
  reaper.ImGui_PopStyleColor(ctx, 2)

  if visible then
    drawContextMenu()

    -- mouse-wheel zoom over the dancer scales it
    local wheel = reaper.ImGui_GetMouseWheel(ctx)
    if wheel and wheel ~= 0 and reaper.ImGui_IsWindowHovered(ctx) then
      state.dispH = math.max(48, math.min(1200, state.dispH + wheel * 16))
    end

    local char    = state.char
    local ps      = reaper.GetPlayState()
    local playing = (ps & 1) == 1
    local qn      = reaper.TimeMap2_timeToQN(0, reaper.GetPlayPosition())

    -- automatic move selection, precedence: MIDI triggers, then sections. Both
    -- set pending so the Sync-changes logic applies the switch at the loop
    -- boundary; speed and timing are untouched.
    if state.midiTrigger and playing then
      -- MIDI notes on the trigger track pick the move. With no note in range, keep
      -- the last move, or go to the idle pose if "Idle between notes" is on.
      local pitch = activeTriggerPitch(reaper.GetPlayPosition())
      local idx = pitch and engine.noteToMove(char.rows, pitch, BASE_NOTE)
      if not idx and state.midiIdle then idx = char.heldIndex end
      if idx and idx ~= state.selected then state.pending = idx end
    elseif state.followSections and playing then
      local name = currentSection(reaper.GetPlayPosition())
      if name then
        local idx = engine.resolveSection(char, name, state.sectionMap)
        if idx and idx ~= state.selected then state.pending = idx end
      end
    end

    local rowIdx, frameIdx = engine.compute(char, state.selected, state.speed, playing, qn)

    -- apply a pending move switch (defer to loop wrap when Sync changes)
    if state.pending and state.pending ~= state.selected then
      local wrapped = playing and (frameIdx == 0 and state.lastFrame ~= 0)
      if (not state.syncChanges) or (not playing) or wrapped then
        state.selected = state.pending
        state.pending  = nil
      end
    end
    state.lastFrame = frameIdx or 0

    renderer.draw(ctx, char, rowIdx, frameIdx, state.dispH)
    reaper.ImGui_End(ctx)
  end

  return open
end

local function frame()
  local open
  if state.char then
    open = drawDancer()
  else
    open = drawLoaderPanel()
  end

  if open and not wantClose then
    reaper.defer(frame)
  end
end

-- restore settings, auto-load last character, persist on exit
restoreSettings()
local last = reaper.GetExtState(EXT_NAMESPACE, 'lastPath')
if last and last ~= '' then loadCharacter(last, true) end

reaper.atexit(saveSettings)
reaper.defer(frame)

-- Expose the pure modules for the test harness. REAPER ignores a script's
-- return value, so this is a no-op at runtime.
return { engine = engine, loader = loader,
         serializeMap = serializeMap, deserializeMap = deserializeMap }
