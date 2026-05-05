# Wanda

Wanda is a macOS 15+ terminal emulator MVP focused on a low-latency PTY-to-Metal rendering path.

## Build

```bash
swift build
```

## Test

```bash
swift test
```

## Manual Run

```bash
swift run Wanda
```

## MVP Scope

The first milestone is a single native macOS terminal window with a local shell, Swift terminal model, bounded in-memory scrollback, basic selection, Metal text rendering, window geometry restore, and latency instrumentation.

## Verification Checklist

- `swift test` passes.
- `swift build` passes.
- `swift run Wanda` launches one native macOS window.
- Printable keys reach the shell.
- Option-Left sends `ESC b`.
- Option-Right sends `ESC f`.
- Command-Left sends `Ctrl-A`.
- Command-Right sends `Ctrl-E`.
- Window size and position restore after relaunch.
- Sustained shell output does not grow scrollback beyond the configured cap.
