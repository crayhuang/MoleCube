# MoleCubeMac

First SwiftUI implementation for the MoleCube macOS app.

This version is intentionally conservative:

- Uses SwiftUI for the UI shell and core screens.
- Uses the local Mole repository as the CLI backend.
- Reads machine-readable output where it already exists.
- Keeps destructive cleanup and uninstall actions as disabled UI placeholders.
- Supports Simplified Chinese, Traditional Chinese, and English through an in-app language picker.

## Run

Recommended for UI development:

1. Open `MoleCubeMac.xcodeproj` in Xcode.
2. Select the `MoleCubeMac` scheme.
3. Select `My Mac` as the destination. This is a macOS app, so it does not launch in an iOS Simulator.
4. Press Run.

From this folder:

```bash
swift run MoleCubeMac
```

From the repository root:

```bash
swift run --package-path apps/MoleCubeMac MoleCubeMac
```

## Backend Mapping

- Status: `bin/status-go --json`, falling back to `go run ./cmd/status --json`.
- Analyze: `bin/analyze-go --json`, falling back to `go run ./cmd/analyze --json`.
- App inventory: `./mole uninstall --list`.
- History: `./mole history --json`.

The backend sets `NO_COLOR=1` for app integration. Read-only inventory and dry-run previews also set `MOLE_TEST_NO_AUTH=1` and `MO_NO_OPLOG=1`; real uninstall runs keep authentication enabled.

The shared Xcode scheme also sets `MOLECUBE_REPOSITORY_ROOT` to the current repository path so the app can find the local Mole CLI when launched from Xcode DerivedData.

## Next Steps

- Add JSON contracts for clean, purge, installer, and optimize.
- Replace placeholder cleanup/uninstall actions with preview-first flows.
- Move localization into `Localizable.strings`.
- Add an Xcode project or app bundle packaging target for signing and distribution.
