# Půdorys

iOS app (SwiftUI + RoomPlan + SceneKit). Project file is generated: edit `project.yml`, then `xcodegen generate`. `Pudorys.xcodeproj` and `build/` are not committed. UI strings are Czech; code and comments English.

Verify changes in the Simulator with the sample room, no LiDAR needed:

```sh
xcodebuild -project Pudorys.xcodeproj -scheme Pudorys -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build build
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/Pudorys.app
xcrun simctl launch booted name.zicha.pudorys -demo -demoLayout -tab plan   # or model / photos / ai; add -exportTest
xcrun simctl io booted screenshot shot.png
```

## Planning a room from an export

When the user hands over an exported folder or ZIP and asks for a furniture layout:

1. Read `plan.json`, look at `pudorys.png` and the photos in `photos/` (their camera position and direction are in `plan.json`; captions often say where radiators or sockets are).
2. Write `layout.json` in the format of `docs/layout-format.md`. Mind the rotation convention (front faces +y at 0°, clockwise). Ergonomics: door zones free, 60 cm or more for passages and beside beds, about 90 cm in front of wardrobes, nothing tall in front of windows, desks with side light.
3. Run `python3 tools/check_layout.py <folder> <layout.json>` and look at the generated `.preview.svg` (render it with `qlmanage -t -s 900 -o <dir> <svg>` to view it). Fix every `!!` line before handing the layout back.
4. Tell the user to AirDrop the JSON to the iPhone and import it in AI plán → ⋯ → Importovat rozvržení. Offer two or three alternative layouts as separate files when the brief allows different approaches.
