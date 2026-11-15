# Example export: sample bedroom

What the app exports for its built-in sample room (an L-shaped 16.4 m² bedroom), with a layout Claude proposed in the app. The full export also holds the USDZ models, RoomPlan's raw data, photos and a ready-made prompt; they are left out here.

- `plan.json`: the measured room (format in [docs/layout-format.md](../../docs/layout-format.md))
- `layout.json`: the furniture layout, which can be imported back into the app
- `pudorys.pdf`, `pudorys.png`, `pudorys.svg`: the floor plan with dimensions in cm

Check it with `python3 tools/check_layout.py examples/demo-bedroom`.
