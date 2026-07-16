# ReaDancer character pack format

A ReaDancer character is a sprite sheet image plus a small text file with the
same name. This explains how to make one. Fruity Dance packs already work as-is.

## The two files

A pack is two files sharing a base name:

```
Foo.png     the sprite sheet
Foo.txt     the move names
```

The image is a grid of cells. Each row is one dance (a "move"), played left to
right and looped. Each column is one frame. The `.txt` names the rows, one per
line, top to bottom, and the row named `Held` is the idle pose (what shows when
you drag the character around).

There are two kinds of pack. A plain one is read exactly like Fruity Dance. An
extended one adds a header line to unlock a few extras.

## Classic (Fruity Dance)

- PNG is best (it has transparency), but JPG, GIF and BMP work too.
- The grid is always 8 columns, so a dance is 8 frames.
- One `.txt` line per row, in order. The number of lines is the number of rows.
- `Held` (any capitalisation) is the idle pose, usually the last row.
- Names are taken as-is. A line starting with `#` is just a name here.

Example:

```
Idle
Wave
Spin
Held
```

## Extended (ReaDancer)

Add this as the first line and the extras below become available:

```
#readancer 1
```

Nothing else changes on its own: a pack that is just `#readancer 1` plus plain
names behaves exactly like a classic one. Old Fruity packs never start with this
line, so they always stay classic.

Now you can use directives, comments, and per-move settings.

### Directives

A line like `#key value` sets an option. They usually go at the top. Unknown ones
are ignored.

| Directive     | Value        | Default | What it does |
|---------------|--------------|---------|--------------|
| `#readancer`  | number       | (none)  | Turns on the extended format. Must be the first line. |
| `#cols`       | 1 or more    | `8`     | Frames per dance, meaning how many columns the grid has. |
| `#beats`      | more than 0  | `1`     | How long one loop lasts, in beats. Can be a fraction. |

### Comments

In an extended pack, a line starting with `# ` (hash then a space) is a comment
and is ignored.

### Per-move settings

A move line can carry settings after ` | ` (a space, a pipe, a space):

```
Wave | frames=6 beats=2
```

| Setting  | Value        | Default   | What it does |
|----------|--------------|-----------|--------------|
| `frames` | 1 to `cols`  | `cols`    | How many frames this move uses, starting from the left. The rest of the row is left empty, so moves can have different lengths. |
| `beats`  | more than 0  | `#beats`  | How long this move's loop lasts, overriding `#beats`. |

`frames` bigger than `cols` is capped, with a warning.

## Cell sizes

Cells are all the same size:

```
cell width  = image width  / columns
cell height = image height / rows
```

If the image does not divide evenly, ReaDancer rounds down and ignores the
leftover pixels on the right and bottom. Sizing the sheet to exact multiples
avoids that.

## What happens on odd input

ReaDancer tries to load anyway and just warns, unless it really cannot.

It gives up when the image will not open, or the `.txt` exists but has no names.

It warns and keeps going when:

- there is no `.txt`: it assumes one row named `Held`
- there is no `Held` row: the last row becomes the idle pose
- the image does not divide evenly into the grid
- a directive or setting is unknown, `frames` is too big, or `#readancer` is a
  newer version than this one

## A full example

`Groovy.txt`:

```
#readancer 1
#cols 12
#beats 2
# 12 frames over two beats; Held is a single frame
Idle
Wave | frames=6
Spin | beats=1
Held | frames=1
```

with a `Groovy.png` that is 12 cells wide and 4 rows tall.

## More

How ReaDancer plays these packs is in [DESIGN.md](DESIGN.md).
