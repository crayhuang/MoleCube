# MoleCube UI Prototype

This folder contains a static visual prototype for a future MoleCube macOS app.
It is intentionally non-functional and does not run cleanup commands.

Open `index.html` in a browser to review the proposed layout.

## Screens

- Dashboard: system health, reclaimable space, load overview, next actions.
- Clean Preview: category-based dry-run review before any destructive action.
- Disk Analyze: treemap and large-file list backed by `mo analyze --json`.
- Uninstall: CleanMyMac-style app inventory, leftover review, related-file groups, and safety-first uninstall action bar backed by `mo uninstall --list`.
- History: operation log backed by `mo history --json`.
- Settings: safety defaults, Trash routing, whitelist visibility.
- Start Scan: modal scan flow with simulated progress, task queue states, and a safe preview handoff.
- Language Switcher: Simplified Chinese, Traditional Chinese, and English with static and key dynamic copy translated.

## Backend Mapping

- `mo status --json`: Dashboard metrics.
- `mo analyze --json`: Disk Analyze.
- `mo uninstall --list`: Uninstall app inventory.
- `mo history --json`: History.
- Future JSON contracts needed: `mo clean --dry-run --json`, `mo purge --dry-run --json`, `mo installer --json`, `mo optimize --json`.

## Design Notes

- The prototype favors a native macOS utility feel: dense, scan-friendly, and safety-first.
- Destructive actions are visually separated from read-only scans.
- Cleanup defaults to preview and Trash routing.
- Protected app and path rules should remain owned by the existing Mole backend.
- Motion is intentionally lightweight: progress animation, scan pulse, task-state transitions, and subtle chart movement.
- The prototype uses an inline translation table for review. A production app should move this into SwiftUI localization resources.
