# ReaDancer

A little dancing character for REAPER, inspired by FL Studio's Fruity Dance.

It puts a character in its own floating window that dances in time with your
project. Compatible with Fruity Dance spritesheets.

## What you need

- REAPER 7.0 or newer
- The ReaImGui extension (install it from ReaPack)

## Installing

ReaDancer is installable via ReaPack. In REAPER open Extensions, then ReaPack,
then Import repositories, and paste:

```
https://github.com/julianZ99/ReaDancer/raw/master/index.xml
```

Then open Browse packages, find ReaDancer, and install it.

To load it by hand instead, grab `Various/ReaDancer.lua` and point REAPER's
New/load ReaScript at it.

## Using it

Run the action and pick a character image. The character shows on its own with no
window borders, floating over REAPER. Drag it to move it, scroll to resize it.

Everything else is in the right-click menu:

- **Move**: pick which dance to play.
- **Speed**: how fast it dances, relative to the tempo.
- **Follow sections**: let the arrangement drive it. Name your regions or markers,
  and each one plays a move you assign.
- **MIDI triggers**: drive it from MIDI notes on a track, like Fruity Dance's
  piano roll. Note 60 (middle C) plays the first move, each semitone up the next.

## Character packs

A character is a sprite sheet image plus a text file with the same name:

```
MyDancer.png     the drawing
MyDancer.txt     the move names
```

Since this is the same layout FL Studio uses, existing Fruity Dance packs work
with no changes. There's also an extended format for loops longer than 8 frames
and per-move timing. The full pack format is in [FORMAT.md](FORMAT.md).

## Internals

How ReaDancer works under the hood is in [DESIGN.md](DESIGN.md).

## License

MIT, see [LICENSE](LICENSE).

## A note on names

ReaDancer is a fan made project. It isn't affiliated with or endorsed by Cockos or
Image-Line. "REAPER" belongs to Cockos Incorporated; "FL Studio" and "Fruity
Dance" belong to Image-Line. Nothing from those products ships here.