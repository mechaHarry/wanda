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

## MVP Scope

The first milestone is a single native macOS terminal window with a local shell, Swift terminal model, bounded in-memory scrollback, basic selection, Metal text rendering, window geometry restore, and latency instrumentation.
