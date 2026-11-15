# Půdorys

An iPhone app that scans a room with LiDAR and turns it into a floor plan with dimensions, a 3D model and a furniture layout you can plan with Claude. Czech UI.

Needs an iPhone with LiDAR (Pro / Pro Max, iPhone 12 Pro or newer) and iOS 17+. On other devices and in the Simulator, the sample room (menu ⋯ → Ukázková místnost) still lets you try everything except scanning.

## What it does

- **Scan.** Apple's RoomPlan guides you through the room and detects walls, doors, windows, openings and larger furniture. The camera button takes photos during the scan; each photo is pinned on the plan where it was taken, with the direction it looks.
- **Půdorys (floor plan).** Wall lengths in cm, doors with swing, windows, area, perimeter, ceiling height, volume. Tap a wall, door or window for its size (window sill height included). Ruler button: tap two points to measure; points snap to corners. Pinch to zoom, drag to pan.
- **Layout.** Add furniture from presets or take over what the scan found, then drag pieces, rotate them with two fingers or the buttons, and edit sizes. Pieces outside the room, overlapping others or blocking a door turn red.
- **3D.** The room with detected furniture and your layout. Orbit with one finger. "Nízké stěny" lowers the walls to see inside. The AR button opens Apple's scanned model in AR Quick Look.
- **AI plán.** A chat with Claude (`claude-opus-5-5`) that gets the measured plan, a picture of it, and up to 8 photos. Its proposed layout appears immediately in the plan and 3D, where you can keep adjusting it. The next message includes your manual changes. ⋯ → "Vrátit předchozí rozvržení" undoes a proposal. Needs an Anthropic API key (⋯ → API klíč), stored in the iPhone's Keychain.
- **Export.** Share button → ZIP with `pudorys.pdf` (A4), `pudorys.png`, `pudorys.svg`, `plan.json`, `layout.json`, `prompt-pro-clauda.txt`, `model-sken.usdz` (RoomPlan's model), `model-s-rozvrzenim.usdz` (model with the planned furniture), `roomplan-captured-room.json` (raw RoomPlan data) and the photos. Scans are also visible in the Files app under Na mém iPhonu → Půdorys → Scans.

## Planning without an API key (through Claude Code or claude.ai)

1. In the app: AI plán → ⋯ → "Kopírovat zadání pro Clauda" and paste it into claude.ai. Or export the ZIP, AirDrop it to the Mac and ask Claude Code in this repo to plan the room (see [CLAUDE.md](CLAUDE.md)).
2. Save the result as a `.json` file (an array of pieces, or `{"layout": [...]}`), get it onto the iPhone (AirDrop / iCloud Drive), then AI plán → ⋯ → "Importovat rozvržení".

The format is in [docs/layout-format.md](docs/layout-format.md). `tools/check_layout.py <export folder> [layout.json]` checks a layout with the same rules as the app and writes an SVG preview.

## Build and install

```sh
brew install xcodegen      # once
xcodegen generate          # creates Pudorys.xcodeproj from project.yml
open Pudorys.xcodeproj
```

Plug in the iPhone, select it as the run destination and press Run. Signing is automatic; to build under your own Apple account, change `DEVELOPMENT_TEAM` (and the bundle ID prefix if needed) in `project.yml`. The first time, the iPhone needs Developer Mode (Settings → Privacy & Security), and Xcode registers the device.

From the command line:

```sh
xcodebuild -project Pudorys.xcodeproj -scheme Pudorys -destination 'generic/platform=iOS' -allowProvisioningUpdates build
```

Simulator checks use the launch arguments `-demo` (open the sample room), `-demoLayout` (with a sample layout), `-tab plan|model|photos|ai`, `-exportTest` (write an export and log its path) and `-aiTest "<request>"` (send one planning request; logs `AITEST …`). Debug builds take the API key from the `ANTHROPIC_API_KEY` environment variable, so a Simulator test can pull it from a password manager such as 1Password without storing it:

```sh
SIMCTL_CHILD_ANTHROPIC_API_KEY="$(op read 'op://<vault>/<item>/credential')" \
  xcrun simctl launch --console-pty booted name.zicha.pudorys -demo -tab ai -aiTest "Navrhni rozmístění nábytku."
```

## Code map

| Path | What |
|---|---|
| `Pudorys/Scan/ScanView.swift` | RoomPlan capture view, photos with camera pose, saving |
| `Pudorys/Model/PlanBuilder.swift` | RoomPlan `CapturedRoom` → flat `PlanModel` (rotated so the longest wall is horizontal, origin at the room's corner) |
| `Pudorys/Model/PlanModel.swift`, `Layout.swift` | Plan geometry, layout items, collision rules, furniture presets |
| `Pudorys/Views/PlanDrawing.swift`, `PlanView.swift` | Drawing (shared with PNG/PDF export) and the interactive plan |
| `Pudorys/Views/Room3DView.swift` | SceneKit model built from the plan |
| `Pudorys/AI/ClaudeClient.swift`, `Views/PlannerView.swift` | Claude Messages API over HTTPS with structured JSON output; the chat |
| `Pudorys/Export/` | plan.json brief, SVG/PDF/PNG/USDZ/ZIP export |
| `tools/check_layout.py` | Layout check and SVG preview on the Mac |

## Limits

- One room per scan. RoomPlan can merge several rooms into a flat (`StructureBuilder`), not wired up yet.
- RoomPlan sizes are usually within a few cm. Check critical dimensions (a kitchen line, a built-in wardrobe) with a tape measure.
- RoomPlan detects only larger furniture categories (bed, sofa, table, chair, storage, appliances…). Radiators and sockets aren't detected; a photo with a caption tells Claude about them.
