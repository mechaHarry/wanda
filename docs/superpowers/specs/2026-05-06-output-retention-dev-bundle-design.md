# Output Retention and Dev App Bundle Design

## Context

Wanda is currently a SwiftPM macOS app that launches with `swift run Wanda`. The executable opens a native SwiftUI/AppKit window and renders terminal state through Metal, but there is no `Wanda.app` bundle staged for normal macOS launching.

Manual testing also shows a primary terminal usability bug: after typing a command, output appears briefly and then the terminal is cleared. The report applies to every command, including normal prompts and redraws, so this is a terminal-core correctness issue rather than a packaging issue.

## Goals

- Preserve normal command output and prompt text on the primary terminal screen.
- Keep alternate-screen behavior isolated for full-screen terminal programs.
- Add regression tests before changing parser/model behavior.
- Add a simple local `dist/Wanda.app` development bundle flow.
- Keep the bundle flow separate from signing, notarization, and release distribution.

## Non-Goals

- Do not replace the terminal parser with a full third-party terminal engine in this milestone.
- Do not implement infinite scrollback, scrollback UI, or indexed search.
- Do not add Developer ID signing, hardened runtime, notarization, DMG creation, or Sparkle-style update packaging.
- Do not create or require an Xcode project for this milestone.

## Approach

Use a narrow terminal-core fix plus a SwiftPM app-bundle script.

The terminal fix should start with byte-stream regressions that reproduce ordinary shell output, prompt redraws, carriage-return/newline behavior, and erase-screen variants. The parser should stop collapsing all `CSI J` erase commands into one destructive full-screen reset. The model should apply erase variants according to their intent:

- `ESC[J` and `ESC[0J`: erase from cursor to end of screen.
- `ESC[1J`: erase from start of screen to cursor.
- `ESC[2J`: erase the whole visible screen.

If a shell sends partial erase commands during prompt redraw, existing command output outside the erased range should remain. Alternate screen remains the only path intended for full-screen app isolation.

The packaging fix should add a project-local script that builds the SwiftPM product, stages a minimal `dist/Wanda.app`, and launches that bundle with `/usr/bin/open -n`. This makes local usage match normal macOS expectations without pretending the app is distribution-signed.

## Components

### Terminal Parser

Extend terminal events so erase-screen commands carry a mode instead of a single `clearScreen` event. Keep the parser bounded: CSI parameter digit limits and buffer limits still apply. Unknown or unsupported CSI commands should remain no-ops or malformed events as they do today.

### Terminal Model

Apply erase-screen modes against the visible grid only. Primary and alternate grids remain separate. Erase operations must mark only affected rows dirty when practical, and all affected rows dirty when a full-screen clear occurs.

The model should preserve scrollback bounds. Full visible-screen erases should not append content to scrollback; only actual scrolling should append bounded scrollback rows.

### Dev Bundle Script

Add `script/build_and_run.sh` with a small, deterministic flow:

1. Stop an existing `Wanda` process if one is running.
2. Run `swift build`.
3. Create `dist/Wanda.app/Contents/MacOS`.
4. Copy the built `Wanda` executable into the bundle.
5. Write a minimal `Contents/Info.plist` with `CFBundleExecutable`, `CFBundleIdentifier`, `CFBundleName`, `CFBundlePackageType`, `LSMinimumSystemVersion`, and `NSPrincipalClass`.
6. Launch with `/usr/bin/open -n dist/Wanda.app`.

The script should support a verification mode that checks the bundle shape and confirms the app process starts.

### Documentation

Update `README.md` so local usage prefers the bundle script:

- `swift test` for tests.
- `swift build` for raw compile checks.
- `./script/build_and_run.sh` for normal local app launch.
- `swift run Wanda` remains a low-level diagnostic path, not the default user-facing run command.

## Testing

Add strict tests for the behavior being changed:

- Parser emits distinct erase-screen modes for `ESC[J`, `ESC[0J`, `ESC[1J`, and `ESC[2J`.
- Primary screen command output remains visible after shell-like prompt redraw sequences.
- Full-screen erase clears the visible screen without mutating scrollback.
- Partial erase does not clear unrelated rows or cells.
- Existing alternate-screen and scrollback tests continue to pass.
- Bundle script verification confirms `dist/Wanda.app/Contents/Info.plist` and `Contents/MacOS/Wanda` exist after build.

Run the full SwiftPM test suite after the focused tests.

## Security and Memory

The parser must keep existing CSI bounds so malformed terminal output cannot grow memory unbounded. The model should keep scrollback capped and should not copy large buffers unnecessarily for partial erases.

The bundle script should use fixed project-local paths and avoid accepting arbitrary executable or destination paths. It should replace only generated files under `dist/Wanda.app`.

## Acceptance Criteria

- Running a normal command no longer flashes output and clears the terminal.
- Prompt redraws do not wipe command output outside the explicit erase range.
- `./script/build_and_run.sh` creates and launches `dist/Wanda.app`.
- `swift test` passes.
- `swift build` passes.
- The app can still be launched manually and quits cleanly.
