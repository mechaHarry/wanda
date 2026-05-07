# Wanda Roadmap

Wanda is a native macOS terminal emulator focused on a low-latency PTY-to-Metal rendering path. The roadmap favors a simple, measurable baseline first, then expands compatibility, window management, search, persistence, and visual polish without losing latency discipline.

## Original Product Goals

The initial feature set for Wanda is:

- Metal-rendered terminal text at high refresh rates, including crisp fonts, antialiasing, and eventually broader typography support.
- Extremely low latency from keystroke to visible character on screen.
- Basic tmux-like pane splitting without depending on tmux:
  - `Cmd-D` splits left/right.
  - `Cmd-Shift-D` splits up/down.
- Multiple independent window instances via `Cmd-N`.
- Shell prompt navigation shortcuts:
  - `Option-Left` and `Option-Right` jump word by word.
  - `Cmd-Left` and `Cmd-Right` jump to line start and line end.
- Infinite-like scrollback without memory leaks or runaway memory usage.
- Fast output search with `Cmd-F` and automatic scroll snapping to matches.
- Precise mouse selection, including easy double-click token selection for URLs and strings without accidental wrapped-line grabs.
- Clean, fast session restore after crash or restart, including window position and best-effort desktop Space behavior.

## Current Baseline

The active baseline is a SwiftPM-first macOS app that stages and launches `dist/Wanda.app` for local testing. The core architecture is:

- SwiftUI app shell with AppKit interop where native macOS behavior requires it.
- Local PTY adapter for shell lifecycle, input writes, resize propagation, and output reads.
- Swift terminal parser and model isolated from UI and Metal.
- Metal renderer consuming terminal snapshots.
- Bounded in-memory scrollback.
- Basic selection and copy.
- Window geometry persistence.
- Versioned app bundle packaging and release scripts.
- Metal stress benchmark with checked-in baseline support.

## Milestones

### 1. Terminal Correctness And Daily Use

The first priority is making normal shell work feel stable and predictable.

- Preserve output across command execution, prompt redraws, and resize.
- Handle terminal resize without losing visible history or current prompt state.
- Close a terminal window cleanly when its shell exits.
- Keep erase, underline, alternate screen, scrollback, and UTF-8 prompt glyph behavior correct under common zsh workflows.
- Expand terminal compatibility deliberately, with tests for each supported ANSI, CSI, OSC, and control sequence.

### 2. Rendering Performance Baseline

The renderer should stay simple and measurable before advanced typography is attempted.

- Maintain a Metal text path with stable cell metrics and low frame times.
- Use benchmark runs to track:
  - frame presentation timing,
  - FPS,
  - characters per second,
  - total print time,
  - workload hash and baseline comparison.
- Add renderer improvements only when they are covered by benchmark deltas and regression tests.
- Keep glyph atlas growth bounded and observable.

### 3. Input Latency

Wanda should treat every input change as latency-sensitive.

- Preserve direct key-to-PTY writes with minimal main-thread work.
- Keep `Option-Left`, `Option-Right`, `Cmd-Left`, and `Cmd-Right` mapped to shell-native readline behavior.
- Track keystroke, PTY write, model mutation, and rendered-frame timing.
- Add latency regressions to benchmark output once the baseline is stable enough to compare over time.

### 4. Windows And Panes

Window and pane management should feel native while staying isolated from terminal model code.

- Support `Cmd-N` for a new terminal window in the active desktop Space.
- Add pane splitting:
  - `Cmd-D` for side-by-side panes,
  - `Cmd-Shift-D` for stacked panes.
- Keep each pane's PTY, scrollback, renderer state, and selection independent.
- Add pane focus movement and close behavior only after split creation is reliable.
- Avoid introducing tmux as a runtime dependency.

### 5. Scrollback And Search

"Infinite" history should mean a user can keep working without memory growth becoming a problem.

- Move from bounded in-memory-only scrollback toward a disk-backed or segmented history store.
- Keep visible grid and hot scrollback memory bounded.
- Release old buffers predictably.
- Add `Cmd-F` search over terminal output.
- Build an index that supports fast match lookup and snapping to matched content. Exact arbitrary substring search still needs defined indexing costs; the roadmap target is fast indexed lookup with measured bounds, not unbounded raw scans.

### 6. Selection And Clipboard

Selection should be cell-accurate and optimized for common terminal copying.

- Clear selection on normal click.
- Keep drag selection aligned to rendered cells after resize.
- Improve double-click token rules for URLs, paths, identifiers, and shell strings.
- Avoid copying unrelated wrapped text when the user selects a URL or short token.
- Add later support for richer URL detection and context actions if it does not complicate selection basics.

### 7. Session Restore

Restore should be fast, clean, and safe after app restart or crash.

- Persist window frame, size, and active Space behavior as far as macOS public APIs allow.
- Restore window and pane layout.
- Restore working directories and shell launch context.
- Restore scrollback and visible terminal contents after persistence is implemented.
- Treat live process restore as a later, higher-risk milestone rather than part of the initial persistence layer.

### 8. Typography Expansion

Simple text rendering comes first. Advanced typography should be explored only after the baseline renderer has hard performance numbers.

- Continue broad Unicode glyph support for terminal-safe text.
- Add fallback font handling for missing glyphs.
- Explore ligatures, complex shaping, emoji, and wide-character behavior behind benchmarks and compatibility tests.
- Reject typography features that exceed frame-time budgets or make cell metrics unstable.

### 9. Theme And Visual Design

The default terminal should be accessible before it is decorative.

- Keep the default scheme on pure black with every text color meeting WCAG contrast targets.
- Keep backing layers matched to the terminal background to avoid white flashes.
- Explore a future liquid-glass terminal surface with blur, refraction, and tinting.
- Treat glass effects as optional presentation work that must not reduce readability, accessibility, or measured latency.

### 10. Distribution And Release

Distribution should be repeatable from repo state.

- Keep `VERSION` as the semver source of truth.
- Generate app bundle plist versions from the shared version source.
- Produce signed release tags using `v` plus `VERSION`.
- Build a versioned zip containing `Wanda.app`.
- Upload release assets through the release script.

## Engineering Gates

Every roadmap item should meet these gates before being considered done:

- Strict automated tests for the feature or regression.
- `swift test` and `swift build` pass.
- Memory growth is bounded or explicitly measured.
- Security-sensitive code paths avoid shell injection, unsafe file access, and unbounded parsing.
- Native macOS APIs are preferred for UI, windowing, menus, shortcuts, and packaging.
- Performance-sensitive changes include benchmark or instrumentation evidence.
