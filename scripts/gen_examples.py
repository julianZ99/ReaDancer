import subprocess, os, tempfile

# examples/ lives next to this script's parent (repo root), regardless of checkout location
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "examples")
os.makedirs(OUT, exist_ok=True)

ROW_COLORS = ["#4f8cff", "#ff6b6b", "#3ddc97", "#f7b32b", "#b085f5", "#ff9f1c"]

def make(name, cols, cell, rows, active=None):
    # rows: list of names ; active: dict rowidx->frames used (default cols)
    active = active or {}
    W, H = cols*cell, len(rows)*cell
    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}">']
    for r, rname in enumerate(rows):
        used = active.get(r, cols)
        col = ROW_COLORS[r % len(ROW_COLORS)]
        for c in range(cols):
            x, y = c*cell, r*cell
            on = c < used
            fill = col if on else "#2b2b2b"
            op = "1" if on else "0.25"
            svg.append(f'<rect x="{x+2}" y="{y+2}" width="{cell-4}" height="{cell-4}" '
                       f'rx="6" fill="{fill}" fill-opacity="{op}" stroke="#111" stroke-width="1.5"/>')
            tcol = "#111" if on else "#777"
            svg.append(f'<text x="{x+cell/2}" y="{y+cell/2-4}" font-family="sans-serif" '
                       f'font-size="{cell*0.22}" font-weight="bold" fill="{tcol}" '
                       f'text-anchor="middle">{r},{c}</text>')
            svg.append(f'<text x="{x+cell/2}" y="{y+cell*0.78}" font-family="sans-serif" '
                       f'font-size="{cell*0.14}" fill="{tcol}" text-anchor="middle">{rname}</text>')
    svg.append('</svg>')
    svgpath = os.path.join(tempfile.gettempdir(), f"{name}.svg")
    open(svgpath, "w").write("\n".join(svg))
    png = os.path.join(OUT, f"{name}.png")
    subprocess.run(["magick", "-background", "none", svgpath, png], check=True)
    return png, W, H

# 1) Classic pack: 8 cols, 3 rows. No header -> parsed as Fruity.
png, W, H = make("Classic8", 8, 96, ["Idle", "Wave", "Held"])
open(os.path.join(OUT, "Classic8.txt"), "w").write("Idle\nWave\nHeld\n")
print("Classic8.png", W, H)

# 2) Extended pack: 12 cols, 4 rows, variable frames.
rows = ["Idle", "Wave", "Spin", "Held"]
active = {1: 6, 3: 1}  # Wave uses 6 frames, Held uses 1
png, W, H = make("Groovy12", 12, 64, rows, active)
open(os.path.join(OUT, "Groovy12.txt"), "w").write(
    "#readancer 1\n"
    "#cols 12\n"
    "#beats 2\n"
    "# 12-frame loop over two beats; greyed cells are unused frames\n"
    "Idle\n"
    "Wave | frames=6\n"
    "Spin\n"
    "Held | frames=1\n"
)
print("Groovy12.png", W, H)
