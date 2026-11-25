#!/usr/bin/env python3
"""Re-quantise screenshots into the ASCII ramp cells and compare them.

  cells.py [--gfx|--glyph] A.png    -> 3x3 grid of mean ramp level (0-9), CLIP %, FLAT flag
  cells.py [--gfx] A.png B.png      -> also: % cells changed, % changed by >1 ramp step, bbox of change
  cells.py --sheet OUT.png A.png B.png ...   (<= 8)  -> one tiled PNG, labelled (RGB kept)
  cells.py --chroma [--outside=..|--box=..] A.png [B.png]  -> CHROMA line per PNG: cells whose
      mean colour has HSV saturation > 0.15, their mean saturation and circular mean hue (deg), bbox

--gfx applies the shader's gamma (1.5) so a graphics shot's levels are the glyph
indices the ASCII pass would stamp. --glyph DECODES an ASCII shot: each 8x16
cell is matched against the ten atlas glyphs (ascii/atlas.png) by normalised
correlation, so a wall of faint '.' reads as level 1, not as the near-black mean. CLIP = % of pixels >= 250 (a blown frame).
FLAT = >= 95% of all cells share one ramp level (an unconverged or empty frame).

Cells are 8x16 px like the shader; a partial last row/column is dropped. Levels
are the same 10-step ramp the shader uses, from mean luminance, so the numbers
describe what a viewer would read, not raw pixels.
"""
import sys
from PIL import Image, ImageDraw

CW, CH, LEVELS, GAMMA = 8, 16, 10, 1.5


def levels(path, gfx=False):
    im = Image.open(path).convert("L")
    w, h = im.size
    cols, rows = w // CW, h // CH
    small = im.resize((cols, rows), Image.BOX)   # box filter == per-cell mean
    px = small.load()
    def lv(v):
        f = v / 255.0
        if gfx:
            f = f ** GAMMA
        return min(LEVELS - 1, int(f * (LEVELS - 0.01)))
    return [[lv(px[x, y]) for x in range(cols)] for y in range(rows)]


_ATLAS = None


def atlas_templates():
    global _ATLAS
    if _ATLAS is None:
        import numpy as np
        im = Image.open(__file__.rsplit("/", 1)[0] + "/../ascii/atlas.png").convert("L")
        a = np.asarray(im, dtype=np.float32) / 255.0
        t = [a[:, i * CW:(i + 1) * CW] for i in range(LEVELS)]
        _ATLAS = [(g - g.mean()) / (g.std() + 1e-6) for g in t]
    return _ATLAS


def glyph_levels(path):
    """Decode an ASCII-rendered PNG: the ramp index of the glyph in each cell."""
    import numpy as np
    im = Image.open(path).convert("L")
    w, h = im.size
    cols, rows = w // CW, h // CH
    a = np.asarray(im, dtype=np.float32)[: rows * CH, : cols * CW] / 255.0
    cells = a.reshape(rows, CH, cols, CW).transpose(0, 2, 1, 3)        # rows, cols, CH, CW
    mean = cells.mean(axis=(2, 3), keepdims=True)
    std = cells.std(axis=(2, 3), keepdims=True)
    norm = (cells - mean) / (std + 1e-6)
    temps = np.stack(atlas_templates()[1:])                          # 9 glyphs, skip ' '
    # normalised correlation of every cell with every glyph
    corr = np.einsum("rcij,gij->rcg", norm, temps) / (CH * CW)
    best = corr.argmax(axis=2) + 1
    blank = (cells.max(axis=(2, 3)) < 0.08)                            # nothing drawn
    lv = np.where(blank, 0, best)
    return lv.tolist()


def clip_pct(path):
    im = Image.open(path).convert("L")
    h = im.histogram()
    return 100.0 * sum(h[250:]) / (im.width * im.height)


def is_flat(lv):
    # an unconverged or empty frame: >= 95% of all cells share one level
    hist = [0] * LEVELS
    for row in lv:
        for v in row:
            hist[v] += 1
    n = len(lv) * len(lv[0])
    return max(hist) / n >= 0.95


def grid3(lv):
    rows, cols = len(lv), len(lv[0])
    out = []
    for gy in range(3):
        line = []
        for gx in range(3):
            ys = range(gy * rows // 3, (gy + 1) * rows // 3)
            xs = range(gx * cols // 3, (gx + 1) * cols // 3)
            s = sum(lv[y][x] for y in ys for x in xs)
            line.append(s / (len(ys) * len(xs)))
        out.append(line)
    return out


def compare(a, b, circle=None):
    """Cell diff. circle=(cx, cy, r) in px splits the count into cells whose
    centre lies inside the circle grown by 16 px (the aura + a margin) and
    cells outside it; returns (changed, big, n, bbox, inside, outside, n_in)."""
    rows, cols = len(a), len(a[0])
    changed = big = inside = outside = n_in = 0
    x0 = y0 = 10**9
    x1 = y1 = -1
    for y in range(rows):
        for x in range(cols):
            d = abs(a[y][x] - b[y][x])
            is_in = False
            if circle is not None:
                cx, cy, r = circle
                px, py = x * CW + CW / 2, y * CH + CH / 2
                is_in = (px - cx) ** 2 + (py - cy) ** 2 <= (r + 16) ** 2
                if is_in:
                    n_in += 1
            if d:
                changed += 1
                x0, y0, x1, y1 = min(x0, x), min(y0, y), max(x1, x), max(y1, y)
                if d > 1:
                    big += 1
                if is_in:
                    inside += 1
                else:
                    outside += 1
    n = rows * cols
    bbox = (x0, y0, x1, y1) if changed else None
    return changed, big, n, bbox, inside, outside, n_in


def chroma(path, circle=None, box=None, thr=0.15):
    """Per-cell colour: the cell's mean RGB -> HSV. Counts cells with saturation
    > thr (a grey frame gives 0 whatever its levels), their mean saturation, the
    circular mean hue in degrees and the bbox; --outside/--box split the count."""
    import math
    im = Image.open(path).convert("RGB")
    w, h = im.size
    cols, rows = w // CW, h // CH
    small = im.resize((cols, rows), Image.BOX).convert("HSV")   # H, S, V in 0..255
    px = small.load()
    n = cols * rows
    cnt = inside = outside = 0
    sat_sum = sx = sy = 0.0
    hues = []
    x0 = y0 = 10**9
    x1 = y1 = -1
    for y in range(rows):
        for x in range(cols):
            hh, ss, vv = px[x, y]
            sat = ss / 255.0
            if sat <= thr or vv < 16:      # a near-black cell's (1,2,1) mean is not a colour (T98)
                continue
            cnt += 1
            sat_sum += sat
            hues.append(hh / 255.0 * 360.0)
            ang = hh / 255.0 * 2.0 * math.pi
            sx += math.cos(ang)
            sy += math.sin(ang)
            x0, y0, x1, y1 = min(x0, x), min(y0, y), max(x1, x), max(y1, y)
            cx, cy = x * CW + CW / 2, y * CH + CH / 2
            is_in = False
            if circle is not None:
                is_in = (cx - circle[0]) ** 2 + (cy - circle[1]) ** 2 <= (circle[2] + 16) ** 2
            elif box is not None:
                is_in = box[0] - CW <= cx <= box[2] + CW and box[1] - CH <= cy <= box[3] + CH
            if is_in:
                inside += 1
            else:
                outside += 1
    hue = (math.degrees(math.atan2(sy, sx)) + 360.0) % 360.0 if cnt else 0.0
    bbox = (x0, y0, x1, y1) if cnt else None
    # the hue spread (M6.0m): 5th and 95th percentile of the counted cells' hues, unwrapped about the mean
    p5 = p95 = hue
    if cnt:
        hs = sorted(((h - hue + 180.0) % 360.0) - 180.0 for h in hues)
        p5 = (hue + hs[int(0.05 * (len(hs) - 1))]) % 360.0
        p95 = (hue + hs[int(0.95 * (len(hs) - 1))]) % 360.0
    line = f"CHROMA {path} cells>{thr:.2f}={cnt} ({100.0*cnt/n:.2f}%) mean_sat={sat_sum/max(cnt,1):.2f} mean_hue_deg={hue:.0f} p5={p5:.0f} p95={p95:.0f} bbox={bbox}"
    if circle is not None or box is not None:
        line += f" inside={inside} outside={outside}"
    print(line)
    return cnt, hue, bbox


def sheet(out, paths):
    ims = [Image.open(p).convert("RGB") for p in paths]   # RGB kept: colour survives a sheet (M5.0g)
    tw = max(i.width for i in ims) // 2
    th = max(i.height for i in ims) // 2
    ncol = 2 if len(ims) > 1 else 1
    nrow = (len(ims) + ncol - 1) // ncol
    canvas = Image.new("RGB", (tw * ncol, (th + 18) * nrow), 0)
    d = ImageDraw.Draw(canvas)
    for i, (im, p) in enumerate(zip(ims, paths)):
        cx, cy = (i % ncol) * tw, (i // ncol) * (th + 18)
        canvas.paste(im.resize((tw, th), Image.BOX), (cx, cy + 18))
        d.text((cx + 4, cy + 3), p.split("/")[-1], fill=(255, 255, 255))
    canvas.save(out)
    print(f"SHEET {out} {len(ims)} images {canvas.width}x{canvas.height}")


def main(argv):
    if len(argv) >= 3 and argv[0] == "--sheet":
        paths = argv[2:]
        if len(paths) > 8:
            sys.exit("sheet: at most 8 images")
        sheet(argv[1], paths)
        return
    gfx = glyph = chrom = False
    circle = None
    box = None
    while argv and argv[0].startswith("--"):
        if argv[0] == "--gfx":
            gfx = True
        elif argv[0] == "--glyph":
            glyph = True
        elif argv[0] == "--chroma":
            chrom = True
        elif argv[0].startswith("--outside="):
            circle = tuple(float(v) for v in argv[0].split("=", 1)[1].split(","))
            if len(circle) != 3:
                sys.exit("--outside=cx,cy,r (px)")
        elif argv[0].startswith("--box="):
            box = tuple(float(v) for v in argv[0].split("=", 1)[1].split(","))
            if len(box) != 4:
                sys.exit("--box=x0,y0,x1,y1 (px, from the SHOT line's patch=)")
        else:
            sys.exit(f"unknown option {argv[0]}")
        argv = argv[1:]
    if not argv:
        sys.exit(__doc__)
    if chrom:
        for p in argv[:2]:
            chroma(p, circle, box)
        return
    a = glyph_levels(argv[0]) if glyph else levels(argv[0], gfx)
    g = grid3(a)
    print(f"CELLS {argv[0]} {len(a[0])}x{len(a)} CLIP {clip_pct(argv[0]):.1f}%" + (" FLAT" if is_flat(a) else ""))
    for line in g:
        print("  " + "  ".join(f"{v:4.2f}" for v in line))
    if len(argv) > 1:
        b = glyph_levels(argv[1]) if glyph else levels(argv[1], gfx)
        if (len(b), len(b[0])) != (len(a), len(a[0])):
            sys.exit("size mismatch")
        changed, big, n, bbox, inside, outside, n_in = compare(a, b, circle)
        print(f"DIFF changed={changed}/{n} ({100*changed/n:.2f}%) by>1step={big} ({100*big/n:.2f}%) bbox={bbox}")
        if circle is not None:
            n_out = n - n_in
            print(f"CIRCLE inside={inside}/{n_in} ({100*inside/max(n_in,1):.2f}%) outside={outside}/{n_out} ({100*outside/max(n_out,1):.2f}%)")
        if box is not None:
            x0, y0, x1, y1 = box
            cx0, cy0 = int(x0 // CW) - 1, int(y0 // CH) - 1
            cx1, cy1 = int(x1 // CW) + 1, int(y1 // CH) + 1
            b_in = b_out = below = 0
            out_big = below_big = 0            # by > 1 ramp step: real, not threshold noise
            core = 10
            out_min = 10
            for y in range(len(a)):
                for x in range(len(a[0])):
                    d = a[y][x] != b[y][x]
                    if cx0 <= x <= cx1 and cy0 <= y <= cy1:
                        core = min(core, b[y][x])
                        if d:
                            b_in += 1
                    elif d:
                        b_out += 1
                        out_min = min(out_min, b[y][x])
                        big_d = abs(a[y][x] - b[y][x]) > 1
                        out_big += big_d
                        if y > cy1:
                            below += 1
                            below_big += big_d
            print(f"BOX cells=({cx0},{cy0})-({cx1},{cy1}) inside={b_in} outside={b_out} ({100*b_out/max(changed,1):.1f}% of changed; by>1step {out_big}) below={below} (by>1step {below_big}) core_min={core} outside_min={out_min}")


if __name__ == "__main__":
    main(sys.argv[1:])
