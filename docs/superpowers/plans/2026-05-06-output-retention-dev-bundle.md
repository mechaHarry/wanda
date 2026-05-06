# Output Retention and Dev App Bundle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix primary-screen output retention and add a local `dist/Wanda.app` development bundle workflow.

**Architecture:** Keep the terminal fix in the existing parser/model boundary by replacing the single destructive clear-screen event with bounded erase-screen modes. Keep packaging outside app source in one project-local script that stages and launches a minimal SwiftPM-built `.app` bundle.

**Tech Stack:** Swift 6, SwiftPM, XCTest, SwiftUI/AppKit, Metal, Bash, macOS app bundle metadata.

---

## File Structure

- Modify `Sources/Wanda/TerminalCore/TerminalEvent.swift`: add `TerminalEraseMode` and replace `clearScreen` with `eraseScreen(TerminalEraseMode)`.
- Modify `Sources/Wanda/TerminalCore/TerminalParser.swift`: decode `CSI J` parameters into erase modes.
- Modify `Sources/Wanda/TerminalCore/TerminalGrid.swift`: add a row-range clearing helper for partial erase operations.
- Modify `Sources/Wanda/TerminalCore/TerminalModel.swift`: apply erase modes without resetting the cursor or mutating scrollback.
- Modify `Tests/WandaTests/TerminalCoreTests.swift`: add parser/model regressions and update old clear-screen expectations.
- Create `script/build_and_run.sh`: stage `dist/Wanda.app` and launch it.
- Create `.codex/environments/environment.toml`: wire the Codex Run action to the script.
- Modify `.gitignore`: ignore generated `.build/` and `dist/`.
- Modify `README.md`: document the app-bundle run path.

---

### Task 1: Parser Erase-Screen Modes

**Files:**
- Modify: `Sources/Wanda/TerminalCore/TerminalEvent.swift`
- Modify: `Sources/Wanda/TerminalCore/TerminalParser.swift`
- Modify/Test: `Tests/WandaTests/TerminalCoreTests.swift`

- [ ] **Step 1: Write the failing parser test**

Add this test to the parser extension in `Tests/WandaTests/TerminalCoreTests.swift`:

```swift
func testParserEmitsEraseScreenModes() {
    var parser = SwiftTerminalParser()

    let events = parser.parse(Array("\u{001B}[J\u{001B}[0J\u{001B}[1J\u{001B}[2J".utf8))

    XCTAssertEqual(events, [
        .eraseScreen(.cursorToEnd),
        .eraseScreen(.cursorToEnd),
        .eraseScreen(.startToCursor),
        .eraseScreen(.all),
    ])
}
```

- [ ] **Step 2: Run the parser test and verify it fails**

Run:

```bash
swift test --filter TerminalCoreTests/testParserEmitsEraseScreenModes
```

Expected: compile failure because `TerminalEvent.eraseScreen` and `TerminalEraseMode` do not exist yet.

- [ ] **Step 3: Add the erase mode event type**

Change `Sources/Wanda/TerminalCore/TerminalEvent.swift` to this shape:

```swift
import Foundation

public enum TerminalEvent: Equatable, Sendable {
    case print(Character)
    case moveCursor(row: Int, column: Int)
    case cursorUp(Int)
    case cursorDown(Int)
    case cursorForward(Int)
    case cursorBackward(Int)
    case carriageReturn
    case lineFeed
    case backspace
    case eraseScreen(TerminalEraseMode)
    case clearLine
    case setGraphicRendition([Int])
    case useAlternateScreen(Bool)
    case malformedSequence
}

public enum TerminalEraseMode: Equatable, Sendable {
    case cursorToEnd
    case startToCursor
    case all
}
```

- [ ] **Step 4: Decode `CSI J` into erase modes**

In `Sources/Wanda/TerminalCore/TerminalParser.swift`, replace the current `J` case with this implementation:

```swift
case UInt8(ascii: "J"):
    switch parameters.first ?? 0 {
    case 0:
        events.append(.eraseScreen(.cursorToEnd))
    case 1:
        events.append(.eraseScreen(.startToCursor))
    case 2:
        events.append(.eraseScreen(.all))
    default:
        events.append(.malformedSequence)
    }
```

- [ ] **Step 5: Update existing parser clear-screen expectations**

In `testParserEmitsClearAndSGREvents`, change the expected `J` event from `.clearScreen` to `.eraseScreen(.all)`:

```swift
XCTAssertEqual(events, [.eraseScreen(.all), .clearLine, .setGraphicRendition([0]), .setGraphicRendition([31, 1])])
```

- [ ] **Step 6: Run parser tests and verify they pass**

Run:

```bash
swift test --filter TerminalCoreTests/testParserEmitsEraseScreenModes
swift test --filter TerminalCoreTests/testParserEmitsClearAndSGREvents
```

Expected: both tests pass.

- [ ] **Step 7: Commit Task 1**

Run:

```bash
git add Sources/Wanda/TerminalCore/TerminalEvent.swift Sources/Wanda/TerminalCore/TerminalParser.swift Tests/WandaTests/TerminalCoreTests.swift
git commit -m "fix: decode erase screen modes"
```

---

### Task 2: Model Erase-Screen Semantics

**Files:**
- Modify: `Sources/Wanda/TerminalCore/TerminalGrid.swift`
- Modify: `Sources/Wanda/TerminalCore/TerminalModel.swift`
- Modify/Test: `Tests/WandaTests/TerminalCoreTests.swift`

- [ ] **Step 1: Write failing model tests**

Add these tests to the model extension in `Tests/WandaTests/TerminalCoreTests.swift`:

```swift
func testModelEraseFromCursorToEndPreservesEarlierOutput() {
    var model = TerminalModel(columns: 4, rows: 3, scrollbackLimit: 5)
    for character in "abcdefgh" {
        model.apply(.print(character))
    }

    model.apply(.moveCursor(row: 1, column: 1))
    model.apply(.eraseScreen(.cursorToEnd))

    XCTAssertEqual(String(model.visibleGrid.rowCells(0).map(\.character)), "abcd")
    XCTAssertEqual(String(model.visibleGrid.rowCells(1).map(\.character)), "e   ")
    XCTAssertEqual(String(model.visibleGrid.rowCells(2).map(\.character)), "    ")
}

func testModelEraseStartToCursorPreservesLaterOutput() {
    var model = TerminalModel(columns: 4, rows: 3, scrollbackLimit: 5)
    for character in "abcdefghijkl" {
        model.apply(.print(character))
    }

    model.apply(.moveCursor(row: 1, column: 2))
    model.apply(.eraseScreen(.startToCursor))

    XCTAssertEqual(String(model.visibleGrid.rowCells(0).map(\.character)), "    ")
    XCTAssertEqual(String(model.visibleGrid.rowCells(1).map(\.character)), "   h")
    XCTAssertEqual(String(model.visibleGrid.rowCells(2).map(\.character)), "ijkl")
}

func testModelEraseAllClearsVisibleScreenWithoutMovingCursorOrScrollback() {
    var model = TerminalModel(columns: 2, rows: 2, scrollbackLimit: 5)
    for character in "abcdef" {
        model.apply(.print(character))
    }
    let scrollbackCount = model.scrollback.count

    model.apply(.moveCursor(row: 1, column: 1))
    model.apply(.eraseScreen(.all))

    XCTAssertEqual(model.cursor, TerminalPoint(column: 1, row: 1))
    XCTAssertEqual(model.visibleGrid.rowCells(0), [.blank, .blank])
    XCTAssertEqual(model.visibleGrid.rowCells(1), [.blank, .blank])
    XCTAssertEqual(model.scrollback.count, scrollbackCount)
}

func testModelShellLikePromptRedrawDoesNotClearPreviousCommandOutput() {
    var model = TerminalModel(columns: 12, rows: 4, scrollbackLimit: 5)
    for character in "echo hi" {
        model.apply(.print(character))
    }
    model.apply(.carriageReturn)
    model.apply(.lineFeed)
    for character in "hi" {
        model.apply(.print(character))
    }
    model.apply(.carriageReturn)
    model.apply(.lineFeed)

    model.apply(.eraseScreen(.cursorToEnd))
    for character in "$ " {
        model.apply(.print(character))
    }

    XCTAssertEqual(String(model.visibleGrid.rowCells(0).map(\.character)).prefix(7), "echo hi")
    XCTAssertEqual(String(model.visibleGrid.rowCells(1).map(\.character)).prefix(2), "hi")
    XCTAssertEqual(String(model.visibleGrid.rowCells(2).map(\.character)).prefix(2), "$ ")
}
```

- [ ] **Step 2: Run one failing model test**

Run:

```bash
swift test --filter TerminalCoreTests/testModelEraseFromCursorToEndPreservesEarlierOutput
```

Expected: compile failure or behavior failure because `TerminalModel` does not handle `.eraseScreen`.

- [ ] **Step 3: Add a grid partial-clear helper**

Add this method to `Sources/Wanda/TerminalCore/TerminalGrid.swift`:

```swift
public mutating func clearCells(in row: Int, columns columnRange: ClosedRange<Int>) {
    precondition(row >= 0 && row < rows, "Row out of bounds")
    precondition(columnRange.lowerBound >= 0, "Column range lower bound out of bounds")
    precondition(columnRange.upperBound < columns, "Column range upper bound out of bounds")

    for column in columnRange {
        setCell(.blank, at: TerminalPoint(column: column, row: row))
    }
}
```

- [ ] **Step 4: Implement erase-screen application in the model**

In `Sources/Wanda/TerminalCore/TerminalModel.swift`, replace the old `.clearScreen` case with:

```swift
case .eraseScreen(let mode):
    eraseScreen(mode)
```

Add these private helpers near the other model mutation helpers:

```swift
private mutating func eraseScreen(_ mode: TerminalEraseMode) {
    switch mode {
    case .cursorToEnd:
        clearVisibleRow(cursor.row, from: cursor.column, through: visibleGrid.columns - 1)
        if cursor.row + 1 < visibleGrid.rows {
            for row in (cursor.row + 1)..<visibleGrid.rows {
                clearVisibleRow(row, from: 0, through: visibleGrid.columns - 1)
            }
        }
    case .startToCursor:
        if cursor.row > 0 {
            for row in 0..<cursor.row {
                clearVisibleRow(row, from: 0, through: visibleGrid.columns - 1)
            }
        }
        clearVisibleRow(cursor.row, from: 0, through: cursor.column)
    case .all:
        withVisibleGrid { grid in
            grid.clearAll()
        }
        markAllRowsDirty()
    }
}

private mutating func clearVisibleRow(_ row: Int, from startColumn: Int, through endColumn: Int) {
    guard startColumn <= endColumn else {
        return
    }

    withVisibleGrid { grid in
        grid.clearCells(in: row, columns: startColumn...endColumn)
    }
    markDirty(row: row)
}
```

- [ ] **Step 5: Update old model clear-screen tests**

Replace `testModelClearScreenResetsCursorAndPendingWrap` with a test that matches real erase-screen behavior:

```swift
func testModelEraseAllClearsScreenAndPendingWrapWithoutMovingCursor() {
    var model = TerminalModel(columns: 2, rows: 2, scrollbackLimit: 5)
    model.apply(.print("A"))
    model.apply(.print("B"))

    model.apply(.eraseScreen(.all))
    model.apply(.print("C"))

    XCTAssertEqual(model.cursor, TerminalPoint(column: 1, row: 0))
    XCTAssertEqual(model.visibleGrid.cell(at: TerminalPoint(column: 0, row: 0)).character, "C")
    XCTAssertEqual(model.visibleGrid.cell(at: TerminalPoint(column: 1, row: 0)).character, " ")
    XCTAssertEqual(model.visibleGrid.cell(at: TerminalPoint(column: 0, row: 1)).character, " ")
}
```

Update any remaining `.clearScreen` references in tests to `.eraseScreen(.all)`.

- [ ] **Step 6: Run focused model tests**

Run:

```bash
swift test --filter TerminalCoreTests/testModelEraseFromCursorToEndPreservesEarlierOutput
swift test --filter TerminalCoreTests/testModelEraseStartToCursorPreservesLaterOutput
swift test --filter TerminalCoreTests/testModelEraseAllClearsVisibleScreenWithoutMovingCursorOrScrollback
swift test --filter TerminalCoreTests/testModelShellLikePromptRedrawDoesNotClearPreviousCommandOutput
swift test --filter TerminalCoreTests/testModelEraseAllClearsScreenAndPendingWrapWithoutMovingCursor
```

Expected: all focused model tests pass.

- [ ] **Step 7: Run all terminal core tests**

Run:

```bash
swift test --filter TerminalCoreTests
```

Expected: all `TerminalCoreTests` pass.

- [ ] **Step 8: Commit Task 2**

Run:

```bash
git add Sources/Wanda/TerminalCore/TerminalGrid.swift Sources/Wanda/TerminalCore/TerminalModel.swift Tests/WandaTests/TerminalCoreTests.swift
git commit -m "fix: preserve output during screen erase"
```

---

### Task 3: SwiftPM Dev App Bundle

**Files:**
- Create: `script/build_and_run.sh`
- Create: `.codex/environments/environment.toml`
- Modify: `.gitignore`
- Modify: `README.md`

- [ ] **Step 1: Create the build/run script**

Create `script/build_and_run.sh` with this content:

```bash
#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Wanda"
BUNDLE_ID="com.mechaharry.Wanda"
MIN_SYSTEM_VERSION="15.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

usage() {
  echo "usage: $0 [run|--package-only|--verify|--debug|--logs|--telemetry]" >&2
}

stop_existing_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

stage_bundle() {
  swift build
  local build_binary
  build_binary="$(swift build --show-bin-path)/$APP_NAME"

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS"
  cp "$build_binary" "$APP_BINARY"
  chmod +x "$APP_BINARY"

  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

verify_bundle() {
  test -x "$APP_BINARY"
  test -f "$INFO_PLIST"
  /usr/bin/plutil -lint "$INFO_PLIST" >/dev/null
}

case "$MODE" in
  run)
    stop_existing_app
    stage_bundle
    open_app
    ;;
  --package-only|package)
    stage_bundle
    verify_bundle
    ;;
  --verify|verify)
    stop_existing_app
    stage_bundle
    verify_bundle
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --debug|debug)
    stop_existing_app
    stage_bundle
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    stop_existing_app
    stage_bundle
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    stop_existing_app
    stage_bundle
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  *)
    usage
    exit 2
    ;;
esac
```

- [ ] **Step 2: Make the script executable**

Run:

```bash
chmod +x script/build_and_run.sh
```

- [ ] **Step 3: Add generated build paths to `.gitignore`**

Change `.gitignore` to include:

```gitignore
.superpowers/
.build/
dist/
```

- [ ] **Step 4: Add Codex Run action config**

Create `.codex/environments/environment.toml`:

```toml
# THIS IS AUTOGENERATED. DO NOT EDIT MANUALLY
version = 1
name = "Wanda"

[setup]
script = ""

[[actions]]
name = "Run"
icon = "run"
command = "./script/build_and_run.sh"
```

- [ ] **Step 5: Update README run instructions**

Change `README.md` so `Manual Run` becomes:

````markdown
## Manual Run

```bash
./script/build_and_run.sh
```

This stages and launches `dist/Wanda.app`. `swift run Wanda` remains useful for low-level SwiftPM diagnostics, but the app-bundle script is the normal local run path.
````

- [ ] **Step 6: Verify bundle packaging without launching**

Run:

```bash
./script/build_and_run.sh --package-only
test -x dist/Wanda.app/Contents/MacOS/Wanda
test -f dist/Wanda.app/Contents/Info.plist
/usr/bin/plutil -lint dist/Wanda.app/Contents/Info.plist
```

Expected: the script exits 0, the two `test` commands exit 0, and `plutil` reports `OK`.

- [ ] **Step 7: Commit Task 3**

Run:

```bash
git add .gitignore .codex/environments/environment.toml README.md script/build_and_run.sh
git commit -m "build: add dev app bundle launcher"
```

---

### Task 4: Final Verification

**Files:**
- No planned source edits.

- [ ] **Step 1: Run full test suite**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 2: Run raw build**

Run:

```bash
swift build
```

Expected: build exits 0.

- [ ] **Step 3: Run bundle verification**

Run:

```bash
./script/build_and_run.sh --verify
```

Expected: command exits 0 and a `Wanda` process exists.

- [ ] **Step 4: Quit the launched app**

Run:

```bash
osascript -e 'tell application "System Events"' -e 'tell process "Wanda"' -e 'set frontmost to true' -e 'keystroke "q" using command down' -e 'end tell' -e 'end tell'
```

Expected: command exits 0.

- [ ] **Step 5: Confirm no app process remains**

Run:

```bash
osascript -e 'tell application "System Events" to get the unix id of every process whose name is "Wanda"'
```

Expected: empty output.

- [ ] **Step 6: Inspect worktree**

Run:

```bash
git status --short --branch
```

Expected: only ignored generated build artifacts are absent from status; no tracked files are modified.
