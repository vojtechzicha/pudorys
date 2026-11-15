# Contributing

Thanks for your interest. Bug reports, ideas and pull requests are welcome.

## Reporting a problem

Open an issue with your device model, iOS version, what you did and what happened. For a wrong floor plan, an export of the room (share button → ZIP) helps most. Leave out photos you don't want to make public; `plan.json` alone is often enough.

## Making a change

1. Build as described in the [README](README.md#build-and-run). Most of the app can be checked in the Simulator with the sample room (`-demo` launch argument), with no LiDAR device.
2. Keep the code style of the files you touch: SwiftUI, no third-party dependencies, comments in English.
3. User-facing text is in Czech. Add new strings in Czech; if you don't speak Czech, write English in the pull request and say so, and the strings will be translated during review.
4. If you change the plan or layout format, update [docs/layout-format.md](docs/layout-format.md), `tools/check_layout.py` and the example in `examples/demo-bedroom`.
5. Before opening the pull request, make sure the app builds (`xcodebuild … build`, as in the CI workflow) and that `python3 tools/check_layout.py examples/demo-bedroom` passes.

By contributing you agree that your contribution is licensed under the [MIT License](LICENSE).
