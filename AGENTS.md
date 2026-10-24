# DroidSync — Agent Development Rules & Architecture Guidelines

## 1. Investigation First (Strict Rule)
- Never modify or execute code edits immediately upon receiving a bug report or feature request.
- Always perform a deep audit of the codebase, review existing AppKit/SwiftUI patterns, and present the root cause and proposed implementation plan to the user first.
- Only proceed with code execution after the user approves the proposed plan.

## 2. Native macOS Behavior & HIG Compliance
- **Window Header Double-Click**: Double-clicking empty areas of the window title/header bar must trigger `performZoom:` to toggle fitting on screen.
- **Window Lifecycle**: Closing the window with the red close button quits the app cleanly (`applicationShouldTerminateAfterLastWindowClosed = true`), and clicking the Dock icon reopens/brings the window key and visible (`applicationShouldHandleReopen`).
- **Draggable Splitters & Handles**: Any resizable divider must push `NSCursor.resizeUpDown` or `NSCursor.resizeLeftRight` on hover and pop on exit.
- **State Persistence**: User layout preferences (split heights, view modes, zoom levels) must be persisted via `@AppStorage`.
- **Adaptive Theming**: Maintain full dark and light mode support using macOS semantic system colors (`NSColor.windowBackgroundColor`, `NSColor.controlBackgroundColor`, `Color.accentColor`).

## 3. Swift 6 Concurrency & Code Quality
- All code must compile with 0 warnings and 0 errors under Swift 6 strict concurrency (`Sendable` compliance).
- UI state mutations must be isolated to `@MainActor`.
- Shell and ADB subprocesses must handle stdout and stderr concurrently to prevent 64KB pipe buffer deadlocks.

## 4. Licensing & Copyright Integrity
- All files, about panels, and licenses must preserve:
  `Copyright © 2026 Kyaw Moe Oo. All rights reserved.`
- Maintain the Apache License 2.0 and NOTICE attribution requirements intact.
