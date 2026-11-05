# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A macOS SwiftUI app that removes the `com.apple.quarantine` extended attribute from dropped apps/files so un-notarized apps can open without Gatekeeper blocking them. No external dependencies, no test targets.

## Build

The Xcode project lives in `I am sure/` (note the spaces — always quote paths).

```bash
xcodebuild -project "I am sure/I am sure.xcodeproj" -scheme "I am sure I want to open this App" -configuration Debug build
```

Schemes: `I am sure I want to open this App` (main app, embeds the extension) and `Let me open this App` (action extension only).

## Targets

- **Main app** (`I am sure/App/`, bundle `com.ruinelson.iamsure`, macOS 26.0+): **not sandboxed** (`ENABLE_APP_SANDBOX = NO`) — required so `removexattr` works on arbitrary user files. Hardened runtime on.
- **Action extension** (`I am sure/Extension/`, `com.apple.ui-services`, Finder Quick Action, sandboxed, read-only user-selected files, macOS 26.0+): the App Sandbox denies writing `com.apple.quarantine` (`deny file-write-xattr` in `application.sb`) and extensions must be sandboxed, so it can't remove quarantine itself. `ActionViewController` extracts file URLs from the input items, `ActionView` (SwiftUI) asks for confirmation, then it hands the URLs to the containing app with `NSWorkspace.open(_:withApplicationAt:)`. Its default actor isolation is nonisolated (unlike the main app).

Both folders are `PBXFileSystemSynchronizedRootGroup`s: adding/removing files on disk updates target membership automatically — no need to edit `project.pbxproj` for new source files. Asset catalog, AccentColor and `AppIcon` (an Icon Composer `AppIcon.icon` in `App/`) are wired through build settings (`ASSETCATALOG_COMPILER_APPICON_NAME`, `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`).

## Concurrency settings

Main app uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency (Swift 5 language mode). Consequently, types used off the main actor must be marked `nonisolated` (see `Quarantine.swift`), and background work uses `@concurrent` async functions rather than detached tasks.

## Architecture (main app)

- `Quarantine.swift` — pure file-system layer (`nonisolated enum Quarantine`). Uses Darwin `getxattr`/`removexattr` with `XATTR_NOFOLLOW`, recursing through folders and bundle contents via `FileManager.enumerator` (symlinked dirs not followed). Produces `RemoveQuarantineResult` / `ItemResult` with per-file failures; `ItemResult.status` is derived (failed if any failure, else removed vs. notQuarantined). `copyAndRemove` copies to a writable folder (never overwriting; adds numeric suffix) then clears the copy — the fallback for read-only locations like mounted DMGs.
- `RemovalModel.swift` — single `@Observable` model injected via `.environment`. Owns `path: [Route]` for the one `NavigationStack` and an `isWorking` flag that gates concurrent runs. `process(_:)` replaces the whole path with `[.result]`, auto-appending `.copy` when any item failed. `copyAndProcess` merges copied results back into the current result.
- `MyApp.swift` — `AppDelegate` owns the `RemovalModel` and forwards Launch Services file opens (`application(_:open:)`: the extension's hand-off, Dock drops, `open -a`) to `model.open(_:)`, which queues them in `pendingURLs` until the risks are acknowledged and no run is in progress. Single `Window` (fixed 640×480, closing quits). Root screen is `AcknowledgeRisks` until the `@AppStorage("ackRisks")` flag is set, then `DropItem`. `Route` cases map to `PresentResult` and `CopyDestination`.
- `MainToolbar.swift` — `.mainToolbar(title:subtitle:)` modifier that every screen must apply; it hides the system back button and supplies a consistent custom back button driven by `model.path` so the toolbar doesn't pop in during navigation.
- UI uses Liquid Glass APIs (`.glassEffect`, `GlassEffectContainer`, `.glass`/`.glassProminent` button styles). Each view has a `#Preview` that needs `.environment(RemovalModel())`.
