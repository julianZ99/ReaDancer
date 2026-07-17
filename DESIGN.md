# ReaDancer design notes

How ReaDancer is built. The character
pack format, for anyone making sprite sheets, has its own doc: [FORMAT.md](FORMAT.md).

## 1. Goals

ReaDancer aims to recreate and extend FL Studio's Fruity Dance inside REAPER. Two
constraints drive the architecture:

1. **Runs wherever REAPER does.** The implementation is Lua (ReaScript) on top of
   [ReaImGui](https://github.com/cfillion/reaimgui), which REAPER exposes
   identically on Windows, macOS and Linux.
2. **Load Fruity Dance packs unchanged.** Old Fruity packs have to keep working
   (see [FORMAT.md](FORMAT.md)); the extended format only adds to that, it never
   breaks them.

## 2. Architecture

The implementation lives in one `ReaDancer.lua`, organised as local modules
(tables of functions). It may be split into files later if it grows; the module
boundaries below are the intended seams.

The flow is straightforward: the loader turns a `.png`/`.txt` pair into a
`character` table, the engine reads the transport and decides the current move
and frame, the renderer draws that frame, and the ui ties it together and
persists settings.

- **loader**: resolves a `.png`/`.txt` pair, parses the pack, decodes geometry,
  creates the ReaImGui image, and produces a `character` table. All format
  knowledge lives here.
- **engine**: owns the clock. Given transport state and tempo, computes the
  current move and frame index. Pure logic, no drawing, no REAPER-image calls
  beyond reading transport.
- **renderer**: draws one cell of the sheet into the window, scaled to fit, alpha
  preserved.
- **ui**: character picker, move selection, speed and options, window handling
  and persisted settings.

## 3. Character table

The loader turns a pack into this table, consumed by the engine and renderer:

```lua
character = {
  version   = 0,        -- 0 = classic, N = extended format version
  image     = <ReaImGui_Image>,
  imgW      = 0, imgH = 0,
  cols      = 8,        -- frames per loop
  rows      = 0,        -- number of moves
  cellW     = 0, cellH = 0,
  beats     = 1.0,      -- default loop length (beats); from #beats
  moves     = {         -- row order, 0-based rows
    -- { name = "Idle", row = 0, frames = 8, beats = 1.0 },
  },
  heldIndex = 0,        -- index into moves of the idle pose
  warnings  = {},       -- array of human-readable strings
}
```

## 4. Timing model

The engine converts transport position to a frame index. Position is read with
`GetPlayState()` / `GetPlayPosition()` and mapped to quarter notes with
`TimeMap2_timeToQN(0, pos)`, so tempo and tempo changes are handled by REAPER.

One full loop spans `beats` quarter notes (per-move override via the `beats`
attribute), scaled by a global user `speed` multiplier. For a move with `frames`
frames:

```
loopQN = beats / speed
frame  = floor((qn / loopQN) * frames) % frames
```

- **Transport stopped**: idle pose (`Held`), frame 0.
- **Sync changes**: when the selected move changes, defer the switch until
  `frame` wraps to 0, matching Fruity Dance's "Sync changes" option.

The default is one loop per beat, which reads as tempo-synced and matches how
Fruity Dance moves along with the project. `speed` and `#beats` let people tune
how frantic a longer sheet looks.

## 5. Move selection

Manual selection is the base: the move is chosen from the context menu, persisted
across sessions. The idle pose (`Held`) is the default.

### 5.1 Section-following

An optional mode (context menu, persisted) picks the move from the current
**arrangement section**, meaning REAPER regions and markers, so the dancer
changes what it does at the intro, verse, build, drop or break, driven by the
project rather than by hand. Speed and timing are untouched; only the selected
move changes.

- **Current section**: `currentSection(pos)` scans `EnumProjectMarkers3`. A
  **region** containing `pos` wins (the innermost, i.e. latest-starting one);
  otherwise the most recent **marker** at or before `pos`. Returns its name, or
  nil.
- **Section-to-move map**: the mapping is configurable, so a section does *not*
  have to be named like a move. `state.sectionMap` is keyed by the normalised
  (trimmed, lowercased) section name; the value is a move name, or `''` for
  "explicitly none". `engine.resolveSection(char, name, map)` returns:
  - a mapped move name uses that move (looked up by name, so it survives pack
    reloads; nil if the move is not in the current pack);
  - `''` returns nil (this section is ignored);
  - no entry means auto, falling back to `engine.matchMove` (exact, else the
    longest move name that is a leading word, so a move `Drop` covers a section
    `Drop 2`, but `Intro` does not match `Introspection`).
  So it works automatically when names line up, and each section can be assigned
  a specific move from the menu when they do not.
- **Applying it**: a match sets `state.pending`, so the Sync-changes logic
  applies the switch immediately or at the next loop boundary. A section
  resolving to nil leaves the current move as-is, so manual selection still holds
  through unmapped or unlabelled parts.

The map is persisted as `section\tmove` lines. `matchMove` and `resolveSection`
are pure and unit-tested; only `currentSection` and `projectSections` touch
REAPER.

### 5.2 MIDI triggering

Fruity Dance's own control is the piano roll: you trigger moves with MIDI notes.
ReaDancer does the same. A toggle picks a trigger track (stored by GUID, set from
the selected track); while playing, the note active at the play cursor selects
the move. MIDI note 60 (middle C) plays the first move and each semitone up is
the next, so drawing notes on the track sequences the dance. Note-name labels
like C4 or C5 depend on REAPER's octave-naming preference, so the note number is
what matters. `engine.noteToMove` maps a pitch to a move index (nil when out of
range); `activeTriggerPitch` finds the active note by scanning the track's MIDI
takes, and is the only REAPER-touching part. When no note is active the dancer
holds the last move, or returns to the idle pose if the "Idle between notes"
option is on.

When several automatic modes are on, precedence is MIDI triggering, then
section-following, then the manual selection.

## 6. Rendering

The current cell is drawn with `ImGui_Image`, passing the frame's UV
sub-rectangle, at a fixed display size that preserves the cell aspect ratio, over
a transparent background. GIF frame decoding is deferred; static sheets are
sliced first.

### 6.1 Presentation

There is a single presentation: **just the dancer**, matching Fruity Dance's
floating look. There is no control strip; the character is the whole window.

- The character is drawn at a fixed display height (adjustable with the mouse
  wheel), its width following the cell aspect ratio. The window uses
  `AlwaysAutoResize`, so it hugs the sprite.
- The dancer window uses `NoTitleBar | NoScrollbar | NoBackground | NoCollapse`
  with zero window padding, plus `SetNextWindowBgAlpha(0)` and transparent
  `WindowBg`/`Border` colors, for real transparency. It is moved by dragging its
  body and scaled with the mouse wheel.
- **All controls live in the right-click context menu**: move, speed, sync,
  follow-sections and its per-section mapping, pin-on-top, load, close. Nothing
  else is on screen.
- **When no character is loaded** there is no dancer to click, so a small normal
  window (with a title bar, so it can be moved and closed) shows a
  `Load character...` button. Once a pack loads, it is replaced by the bare
  dancer.

Desktop-level transparency depends on the compositor, and only Wayland
compositors that blur undecorated or transparent windows (Hyprland, for example)
are affected: the transparent regions look frosted. That is the compositor, not
the app; disable blur for the window with a compositor rule. On Wayland/Hyprland
(rule syntax as of 0.55), matching by the window title `ReaDancer`:

```
windowrule = no_blur on, match:title ^(ReaDancer)$
windowrule = no_shadow on, match:title ^(ReaDancer)$
windowrule = border_size 0, match:title ^(ReaDancer)$
```

This is a Wayland-only workaround.

## 7. Persistence

Last-used character path, selected move, speed, sync-changes, always-on-top
(pin), display size, the section-to-move map, and the MIDI-trigger toggle and
track GUID are stored via REAPER `SetExtState`/`GetExtState` under a `ReaDancer`
namespace (persist = true) and restored on launch. Settings are written on exit
via `reaper.atexit`.

## 8. Tests

The pure logic (the loader/parser and the engine's move-matching, section
resolution and MIDI note mapping) is unit-tested with plain Lua under `tests/`.
The harness stubs enough of the REAPER API to load the script and calls the
modules it returns. Run them from the repo root:

```
lua5.4 tests/run.lua
```

GitHub Actions runs the same on every push and pull request.

## 9. Distribution

Ships through ReaPack as the `.lua` script plus a generated `index.xml`. ReaImGui
is a ReaPack dependency users install separately.

## 10. Roadmap

- **v0.1** (done): load a pack (classic and extended), render it, tempo-synced
  idle/loop, pick a move by hand.
- **v0.2** (done): Speed presets and Sync-changes, always-on-top (pin), persist
  speed, selected move and options across sessions.
- **v0.3** (done): the "just the dancer" presentation, hiding all chrome so only
  the character shows, movable by dragging it, controls via right-click menu.
- **v0.4** (done): section-following, where the arrangement (regions and markers)
  picks the move, and MIDI-note triggering, where notes on a track pick it.
- **v1.0**: published ReaPack index, a self-made example character, several
  dancers on screen at once (the way Fruity Dance allows), docs.
