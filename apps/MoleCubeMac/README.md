# MoleCube for macOS

MoleCube is a native macOS interface for safe system maintenance. It provides
visual workflows for cleanup previews, app removal, disk analysis, optimization,
and system status.

MoleCube includes and uses [Mole](https://github.com/tw93/Mole), the open-source
macOS maintenance CLI created by tw93 and contributors.

## License and commercial use

MoleCube is commercial open source software distributed under the GNU General
Public License, version 3.0 (GPL-3.0). You may charge for copies, support,
services, or distribution, but recipients retain the GPL rights to run, study,
modify, and redistribute the GPL-covered software.

Every MoleCube release must:

- Include the GPL-3.0 license and the upstream Mole attribution.
- Provide access to the complete corresponding source for that exact binary.
- Include the MoleCube UI source, bundled Mole source, modifications, and build
  scripts needed to produce the release.
- Avoid terms or technical restrictions that prevent GPL-permitted modification
  or redistribution.

See the repository [LICENSE](../../LICENSE), [NOTICE](../../NOTICE), and
[open-source distribution guide](../../docs/OPEN_SOURCE_DISTRIBUTION.md).

## System requirements

- macOS 14 or later.
- Universal build support for Apple Silicon and Intel Macs.

## Run from Xcode

1. Open `MoleCubeMac.xcodeproj` in Xcode.
2. Select the `MoleCubeMac` scheme.
3. Select **My Mac** as the destination.
4. Press Run.

From this folder:

```bash
swift run MoleCubeMac
```

From the repository root:

```bash
swift run --package-path apps/MoleCubeMac MoleCubeMac
```

## Backend mapping

MoleCube uses the local Mole CLI as its backend:

- Status: `bin/status-go --json`, falling back to `go run ./cmd/status --json`.
- Analyze: `bin/analyze-go --json`, falling back to `go run ./cmd/analyze --json`.
- App inventory: `./mole uninstall --list`.
- History: `./mole history --json`.

The backend sets `NO_COLOR=1` for app integration. Read-only inventory and
dry-run previews also set `MOLE_TEST_NO_AUTH=1` and `MO_NO_OPLOG=1`; real
uninstall runs keep authentication enabled.

The shared Xcode scheme sets `MOLECUBE_REPOSITORY_ROOT` to the repository path,
so the app can find the local Mole CLI when launched from Xcode DerivedData.

## Build a distributable DMG

Use `Scripts/create_dmg.sh` only from a clean, tagged source revision. The script
creates a Universal DMG and includes `LICENSE.txt`, `NOTICE.txt`, and
`SOURCE-CODE.txt` next to `MoleCube.app`.

Before creating a release, configure a Developer ID Application signing identity:

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" \
DEVELOPMENT_TEAM="TEAMID" \
apps/MoleCubeMac/Scripts/create_dmg.sh
```

The resulting DMG must be published together with a clear link to the matching
source tag on <https://github.com/crayhuang/MoleCube>.

## Development status

MoleCube is intentionally conservative. It uses SwiftUI for the native UI and
keeps destructive cleanup and uninstall flows preview-first, confirmation-based,
and protected by Mole's safety rules.
