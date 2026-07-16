-- Engine tests: move matching, section resolution/cycling, MIDI note mapping,
-- and the section-map serialisation. All pure functions (no REAPER calls).
local H = dofile('tests/harness.lua')
local mod = H.load()
local engine, ser, deser = mod.engine, mod.serializeMap, mod.deserializeMap
local t = H.tester()

local char = { rows = 4, moves = {
  { name = 'Intro' }, { name = 'Verse' }, { name = 'Build' }, { name = 'Drop' },
} }

-- matchMove: exact, case-insensitive, prefix word, no accidental substring
t:eq('match exact', engine.matchMove(char, 'Drop'), 4)
t:eq('match case-insensitive', engine.matchMove(char, 'verse'), 2)
t:eq('match trims', engine.matchMove(char, '  Build  '), 3)
t:eq('match leading-word "Drop 2"', engine.matchMove(char, 'Drop 2'), 4)
t:eq('no substring w/o boundary', engine.matchMove(char, 'Introspection'), nil)
t:eq('match none', engine.matchMove(char, 'Breakdown'), nil)
t:eq('match empty', engine.matchMove(char, ''), nil)

-- longest leading-word wins
local char2 = { rows = 2, moves = { { name = 'Intro' }, { name = 'Intro Fill' } } }
t:eq('exact beats prefix', engine.matchMove(char2, 'Intro'), 1)
t:eq('longest prefix wins', engine.matchMove(char2, 'Intro Fill Extra'), 2)

-- resolveSection: map overrides, '' = none, missing = auto
local map = {}
t:eq('resolve auto (unmapped)', engine.resolveSection(char, 'Drop', map), 4)
map['breakdown'] = 'Verse'
t:eq('resolve mapped by name', engine.resolveSection(char, 'Breakdown', map), 2)
t:eq('resolve mapped key case-insensitive', engine.resolveSection(char, 'BREAKDOWN', map), 2)
map['drop'] = 'Intro'
t:eq('resolve override beats auto', engine.resolveSection(char, 'Drop', map), 1)
map['chorus'] = ''
t:eq('resolve explicit none', engine.resolveSection(char, 'Chorus', map), nil)
map['weird'] = 'Nope'
t:eq('resolve mapped-but-missing move', engine.resolveSection(char, 'weird', map), nil)

-- cycleSection forward/back and round-trips
local cyc = { moves = { { name = 'Wave' }, { name = 'Spin' }, { name = 'Held' } } }
t:eq('cycle auto->m1', engine.cycleSection(cyc, nil), 'Wave')
t:eq('cycle m3->none', engine.cycleSection(cyc, 'Held'), '')
t:eq('cycle none->auto', engine.cycleSection(cyc, ''), nil)
t:eq('cycleBack auto->none', engine.cycleSectionBack(cyc, nil), '')
t:eq('cycleBack none->m3', engine.cycleSectionBack(cyc, ''), 'Held')
for _, e in ipairs({ { name = 'auto' }, { name = 'none', v = '' },
                     { name = 'Wave', v = 'Wave' }, { name = 'Spin', v = 'Spin' },
                     { name = 'Held', v = 'Held' } }) do
  local s = e.v  -- nil for auto
  t:eq('rt fwd/back ' .. e.name, engine.cycleSectionBack(cyc, engine.cycleSection(cyc, s)), s)
end

-- noteToMove: base note plays move 1, ascending, nil out of range
t:eq('note base -> move 1', engine.noteToMove(4, 60, 60), 1)
t:eq('note base+3 -> move 4', engine.noteToMove(4, 63, 60), 4)
t:eq('note base+4 -> nil', engine.noteToMove(4, 64, 60), nil)
t:eq('note below base -> nil', engine.noteToMove(4, 59, 60), nil)
t:eq('note other base', engine.noteToMove(4, 50, 48), 3)

-- section map serialisation round-trip (including '' = none)
local rt = deser(ser({ intro = 'Intro', drop = 'Verse', chorus = '' }))
t:eq('ser rt intro', rt.intro, 'Intro')
t:eq('ser rt drop', rt.drop, 'Verse')
t:eq('ser rt none', rt.chorus, '')
t:eq('deser empty string', next(deser('')), nil)

return t.pass, t.fail
