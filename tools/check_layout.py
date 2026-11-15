#!/usr/bin/env python3
"""Check a furniture layout against an exported room and draw a preview.

Usage: python3 tools/check_layout.py <export folder> [layout.json] [-o preview.svg]

Reads plan.json from the export folder (made by the Půdorys app) and a layout
(default: layout.json in the same folder), applies the same rules as the app
(inside the room, no overlaps, door zones free; rugs and chairs at tables may
overlap) and writes an SVG preview next to the layout. Standard library only.
"""
import json
import math
import sys
from pathlib import Path


def corners(i):
    r = math.radians(i["rotation"])
    hw, hd = i["width"] / 2, i["depth"] / 2
    out = []
    for x, y in [(-hw, -hd), (hw, -hd), (hw, hd), (-hw, hd)]:
        out.append((x * math.cos(r) - y * math.sin(r) + i["x"], x * math.sin(r) + y * math.cos(r) + i["y"]))
    return out


def contains(poly, p):
    inside, j = False, len(poly) - 1
    for i in range(len(poly)):
        (ax, ay), (bx, by) = poly[i], poly[j]
        if (ay > p[1]) != (by > p[1]) and p[0] < (bx - ax) * (p[1] - ay) / (by - ay) + ax:
            inside = not inside
        j = i
    return inside


def overlaps(p, q, tol=0.01):
    for poly in (p, q):
        for k in range(len(poly)):
            ex, ey = poly[(k + 1) % len(poly)][0] - poly[k][0], poly[(k + 1) % len(poly)][1] - poly[k][1]
            n = math.hypot(ex, ey) or 1
            ax, ay = -ey / n, ex / n
            pp = [x * ax + y * ay for x, y in p]
            qq = [x * ax + y * ay for x, y in q]
            if max(pp) <= min(qq) + tol or max(qq) <= min(pp) + tol:
                return False
    return True


def flat(i):
    return i["category"] == "rug" or i["height"] < 0.05


def may_overlap(a, b):
    if flat(a) or flat(b):
        return True
    cats = {a["category"], b["category"]}
    if "chair" in cats and cats & {"table", "desk"}:
        return True
    return "lamp" in cats and bool(cats & {"table", "desk", "storage"})


def issues(plan, layout):
    out = {}
    outline = [tuple(p) for p in plan["outline"]]
    zones = [[tuple(p) for p in z] for z in plan.get("door_clearance_zones", [])]
    for i in layout:
        c = corners(i)
        found = []
        inset = []
        for x, y in c:
            dx, dy = i["x"] - x, i["y"] - y
            d = math.hypot(dx, dy) or 1
            inset.append((x + dx / d * 0.03, y + dy / d * 0.03))
        if len(outline) > 2 and not all(contains(outline, p) for p in inset):
            found.append("outside the room")
        for o in layout:
            if o["id"] != i["id"] and not may_overlap(i, o) and overlaps(c, corners(o)):
                found.append(f"overlaps {o['name']}")
        if not flat(i) and any(overlaps(c, z) for z in zones):
            found.append("blocks a door")
        if found:
            out[i["id"]] = found
    return out


COLORS = {"bed": "#5856d6", "sofa": "#ff9500", "chair": "#ff9500", "table": "#a2845e", "desk": "#a2845e",
          "storage": "#30b0c7", "television": "#af52de", "rug": "#ff2d55", "plant": "#34c759"}


def svg(plan, layout, bad):
    s, pad = 100, 80
    pts = plan["outline"] + [p for w in plan["walls"] for p in (w["from"], w["to"])]
    minx, miny = min(p[0] for p in pts), min(p[1] for p in pts)
    maxx, maxy = max(p[0] for p in pts), max(p[1] for p in pts)
    X = lambda v: (v - minx) * s + pad
    Y = lambda v: (v - miny) * s + pad
    w, h = (maxx - minx) * s + 2 * pad, (maxy - miny) * s + 2 * pad
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{w:.0f}" height="{h:.0f}" font-family="Helvetica" font-size="12">',
         '<rect width="100%" height="100%" fill="white"/>']
    o.append('<polygon fill="#efe6d6" points="' + " ".join(f"{X(x):.1f},{Y(y):.1f}" for x, y in plan["outline"]) + '"/>')
    for z in plan.get("door_clearance_zones", []):
        o.append('<polygon fill="#ff000018" stroke="#f003" points="' + " ".join(f"{X(x):.1f},{Y(y):.1f}" for x, y in z) + '"/>')
    for i in sorted(layout, key=lambda i: not flat(i)):
        col = COLORS.get(i["category"], "#888")
        c = corners(i)
        o.append(f'<polygon fill="{col}44" stroke="{"red" if i["id"] in bad else col}" stroke-width="2" points="'
                 + " ".join(f"{X(x):.1f},{Y(y):.1f}" for x, y in c) + '"/>')
        o.append(f'<line x1="{X(c[2][0]):.1f}" y1="{Y(c[2][1]):.1f}" x2="{X(c[3][0]):.1f}" y2="{Y(c[3][1]):.1f}" stroke="{col}" stroke-width="5"/>')
        o.append(f'<text x="{X(i["x"]):.1f}" y="{Y(i["y"]):.1f}" text-anchor="middle">{i["name"]}</text>')
    for wl in plan["walls"]:
        (ax, ay), (bx, by) = wl["from"], wl["to"]
        o.append(f'<line x1="{X(ax):.1f}" y1="{Y(ay):.1f}" x2="{X(bx):.1f}" y2="{Y(by):.1f}" stroke="#222" stroke-width="12" stroke-linecap="square"/>')
    for op in plan["openings"]:
        (ax, ay), (bx, by) = op["from"], op["to"]
        col = {"window": "#6aa8ff", "door": "#a0522d"}.get(op["kind"], "white")
        o.append(f'<line x1="{X(ax):.1f}" y1="{Y(ay):.1f}" x2="{X(bx):.1f}" y2="{Y(by):.1f}" stroke="{col}" stroke-width="13"/>')
    o.append("</svg>")
    return "\n".join(o)


def main():
    args = [a for a in sys.argv[1:] if a != "-o"]
    out = sys.argv[sys.argv.index("-o") + 1] if "-o" in sys.argv else None
    if out:
        args.remove(out)
    if not args:
        sys.exit(__doc__)
    folder = Path(args[0])
    plan = json.loads((folder / "plan.json").read_text())
    layout_path = Path(args[1]) if len(args) > 1 else folder / "layout.json"
    data = json.loads(layout_path.read_text())
    layout = data["layout"] if isinstance(data, dict) else data
    bad = issues(plan, layout)
    for i in layout:
        print(f'{"!!" if i["id"] in bad else "ok"} {i["name"]}: {"; ".join(bad.get(i["id"], [])) or "fine"}')
    preview = Path(out) if out else layout_path.with_suffix(".preview.svg")
    preview.write_text(svg(plan, layout, bad))
    print(f"preview: {preview}")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
