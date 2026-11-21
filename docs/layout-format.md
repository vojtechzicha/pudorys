# Plan and layout format

## Coordinates

All values are metres, in plan coordinates: x to the right, y **downwards** (a top view, the way `pudorys.png` is drawn). The plan is rotated so the longest wall is horizontal, and the room's top-left corner is near (0, 0).

## plan.json (`pudorys-plan/1`, read-only)

| Field | Meaning |
|---|---|
| `outline` | Floor polygon `[[x, y], …]`, not closed |
| `walls[]` | `from`, `to`, `length`, `height` |
| `openings[]` | `kind` (`door` / `window` / `opening` / `wardrobe`), `from`, `to`, `width`, `height`, `sill` (bottom edge above floor). Set by hand in the app when known: `label` (where a door leads, e.g. "Koupelna"), for doors `hinge_at` `[x, y]` and `swings` (`into this room` / `out of this room`); `sliding` marks doors wider than 2 m. A `wardrobe` is a built-in wardrobe whose sliding doors lie in the wall line, with `depth_behind_wall` (60 cm and `depth_is_assumed` when not measured) |
| `door_clearance_zones` | One polygon per door and built-in wardrobe: the area in front of it that must stay free |
| `detected_furniture[]` | What RoomPlan found: `category`, `x`, `y`, `width`, `depth`, `height`, `rotation` |
| `photos[]` | `file`, `camera_at` `[x, y]`, `looking_towards_deg` (clockwise from +x), `caption` |
| `area_m2`, `perimeter_m`, `ceiling_height_m`, `room_type`, `notes` | |

## layout.json (what Claude writes, the app imports)

An array (or `{"layout": [...]}`) of pieces:

```json
[
  {"id": "bed", "name": "Postel 160×200", "category": "bed",
   "x": 1.05, "y": 1.75, "width": 1.6, "depth": 2.05, "height": 0.5,
   "rotation": 90, "note": "čelo u levé stěny"}
]
```

- `x`, `y`: centre of the piece.
- `width` runs along x and `depth` along y when `rotation` is 0. The **front** (where you sit, open doors and drawers, or watch from; for a bed the foot end) faces **+y** (down).
- `rotation`: degrees, clockwise on the plan. 90 → front faces −x (left), 180 → front faces −y (up), 270 → front faces +x (right).
- `category`: `bed`, `sofa`, `chair`, `table`, `desk`, `storage`, `television`, `rug`, `plant`, `lamp`, `refrigerator`, `stove`, `oven`, `dishwasher`, `sink`, `washerDryer`, `toilet`, `bathtub`, `other`. It sets the colour; `rug` (or height under 5 cm) may lie under other pieces, chairs may overlap tables and desks, and lamps may overlap tables, desks and storage.
- `id`: any unique string; keep ids when changing an existing layout.
- `note`: optional, shown when the piece is selected.

The app marks a piece red when it reaches outside the outline (3 cm tolerance), overlaps another piece, or covers a door clearance zone.
