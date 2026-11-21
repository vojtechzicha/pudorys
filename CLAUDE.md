# Půdorys

iOS app (SwiftUI + RoomPlan + SceneKit). Project file is generated: edit `project.yml`, then `xcodegen generate`. `Pudorys.xcodeproj` and `build/` are not committed. UI strings are Czech; code and comments English.

Verify changes in the Simulator with the sample room, no LiDAR needed:

```sh
xcodebuild -project Pudorys.xcodeproj -scheme Pudorys -destination 'platform=iOS Simulator,id=<simulator UDID>' -derivedDataPath build build   # UDID from `xcrun simctl list devices`; a name alone is ambiguous once several iOS runtimes are installed
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/Pudorys.app
xcrun simctl launch booted name.zicha.pudorys -demo -demoLayout -tab plan   # or model / photos / ai; add -exportTest
xcrun simctl io booted screenshot shot.png
```

The scan code (`ScanView`, `PlanBuilder`) only runs on real RoomPlan data. Test `PlanBuilder` changes in the Simulator with `-importRoom <roomplan-captured-room.json>` (from any export of a real scan), then `-open "<name>"`; `-rebuild` re-runs it on the scans already stored. On a device: `xcodebuild … -destination 'id=<device UDID>' -allowProvisioningUpdates`, `xcrun devicectl device install app`, and pull scans back with `xcrun devicectl device copy from --domain-type appDataContainer --domain-identifier name.zicha.pudorys --source Documents/Scans`.

## Planning a room from an export

When the user hands over an exported folder or ZIP and asks for a furniture layout:

1. Read `plan.json`, look at `pudorys.png` and the photos in `photos/` (their camera position and direction are in `plan.json`; captions often say where radiators or sockets are). Openings may carry a `label` (where a door leads), `hinge_at` and `swings`, and the kind `wardrobe` (a built-in wardrobe behind the wall line); keep the entrance and the wardrobe front usable.
2. Write `layout.json` in the format of `docs/layout-format.md`. Mind the rotation convention (front faces +y at 0°, clockwise). Ergonomics: door zones free, 60 cm or more for passages and beside beds, about 90 cm in front of wardrobes, nothing tall in front of windows, desks with side light.
3. Run `python3 tools/check_layout.py <folder> <layout.json>` and look at the generated `.preview.svg` (render it with `qlmanage -t -s 900 -o <dir> <svg>` to view it). Fix every `!!` line before handing the layout back.
4. Tell the user to AirDrop the JSON to the iPhone and import it in AI plán → ⋯ → Importovat rozvržení. Offer two or three alternative layouts as separate files when the brief allows different approaches.
