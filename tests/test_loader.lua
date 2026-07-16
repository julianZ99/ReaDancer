-- Loader / character-pack format tests (DESIGN section 3).
local H = dofile('tests/harness.lua')
local t = H.tester()

local function loadPack(opts) return H.load(opts).loader.load('Pack.png') end
local function warned(c, pat)
  for _, w in ipairs(c.warnings) do if w:find(pat) then return true end end
  return false
end

-- classic: no header, verbatim names, 8 columns
local c = loadPack{ imgW = 96, imgH = 48, txt = { 'Idle', 'Wave', 'Held' } }
t:eq('classic version 0', c.version, 0)
t:eq('classic cols 8', c.cols, 8)
t:eq('classic rows 3', c.rows, 3)
t:eq('classic cellW 12', c.cellW, 12)   -- 96 / 8
t:eq('classic cellH 16', c.cellH, 16)   -- 48 / 3
t:eq('classic held is last', c.heldIndex, 3)
t:eq('classic frames default cols', c.moves[1].frames, 8)

-- extended: cols/beats + per-move attrs + comment vs directive
c = loadPack{ imgW = 120, imgH = 40, txt = {
  '#readancer 1', '#cols 12', '#beats 2', '# a comment',
  'Idle', 'Wave | frames=6', 'Spin | beats=1', 'Held | frames=1',
} }
t:eq('ext version 1', c.version, 1)
t:eq('ext cols 12', c.cols, 12)
t:eq('ext beats 2', c.beats, 2)
t:eq('ext rows 4 (comment/directives skipped)', c.rows, 4)
t:eq('ext cellW 10', c.cellW, 10)
t:eq('ext move name', c.moves[2].name, 'Wave')
t:eq('ext frames attr', c.moves[2].frames, 6)
t:eq('ext beats inherited', c.moves[2].beats, 2)
t:eq('ext per-move beats override', c.moves[3].beats, 1)
t:eq('ext held frames=1', c.moves[4].frames, 1)
t:eq('ext held found by name', c.heldIndex, 4)

-- unknown directive + frames clamp + missing Held
c = loadPack{ imgW = 16, imgH = 20, txt = { '#readancer 1', '#cols 4', '#wat hi', 'A | frames=99', 'B' } }
t:ok('unknown directive warns', warned(c, 'unknown directive: #wat'))
t:eq('frames clamped to cols', c.moves[1].frames, 4)
t:ok('clamp warns', warned(c, 'clamping'))
t:eq('no Held -> last row', c.heldIndex, 2)
t:ok('no Held warns', warned(c, 'no "Held"'))

-- non-divisible geometry warns and floors
c = loadPack{ imgW = 100, imgH = 15, txt = { 'Idle', 'Held' } }
t:ok('width non-divisible warns', warned(c, 'width 100 not divisible'))
t:ok('height non-divisible warns', warned(c, 'height 15 not divisible'))
t:eq('floored cellW', c.cellW, 12)   -- floor(100/8)

-- missing .txt -> single Held strip
c = loadPack{ imgW = 80, imgH = 10, txt = nil }
t:eq('missing txt single move', c.rows, 1)
t:eq('missing txt named Held', c.moves[1].name, 'Held')
t:ok('missing txt warns', warned(c, 'no .txt'))

return t.pass, t.fail
