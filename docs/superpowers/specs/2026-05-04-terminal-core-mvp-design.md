# Terminal Core MVP Design

Date: 2026-05-04
Status: Approved design for implementation planning

## Context

Wanda starts as a new macOS terminal emulator project. The current workspace is empty, so this design defines the first milestone rather than changing an existing application.

The long-term product direction includes Metal-rendered terminal text, native macOS UI, tmux-like splits, multiple windows, low-latency input, large scrollback, fast search, robust selection, and session restore. The first milestone intentionally narrows that scope to prove the terminal core and rendering path before adding higher-level window management and persistence.

## Goals

Build a single-window terminal core MVP for macOS 15+ that launches a local shell, renders terminal output through Metal, forwards keyboard input with extremely low latency, supports a daily-driver terminal subset, and restores the window size and position.

The MVP must follow the project directives:

- API-call code, if introduced later, must use graceful backoff. This MVP does not include external API calls.
- UI code must use OS-native SDKs.
- Code must be reviewed for memory leaks and security issues.
- Every feature needs strict tests.
- UI and data must remain isolated.
- Simpler implementation choices win when they preserve the latency and correctness goals.

## Non-Goals

The MVP does not include:

- tmux-like splits, tabs, multiple terminal windows, or Cmd-N support,
- disk-backed scrollback, infinite-like history, indexed search, or Cmd-F search,
- live shell session restore, restored terminal contents, restored scrollback, or desktop Space restore,
- ligatures, complex shaping, emoji polish, advanced fallback fonts, or full Unicode terminal fidelity,
- local prompt editing or shell-aware command-line manipulation,
- network calls or AI features.

These remain post-MVP milestones after the renderer, PTY path, and latency gates are established.

## Recommended Approach

Use a SwiftUI app shell with an AppKit-backed Metal view and a replaceable parser boundary.

The first implementation should behave like a Swift-native terminal core, but the parser interface should stay narrow enough that a mature parser can be tested and swapped in later if it beats the Swift-native parser on compatibility, memory use, and latency.

This approach keeps the key high-risk areas isolated:

- SwiftUI and AppKit handle native windowing, command routing, focus, and low-level key events.
- The PTY adapter owns local shell lifecycle and byte streams.
- The parser boundary converts bytes into terminal events.
- The terminal model owns grid state, cursor state, attributes, alternate screen, scrollback, and selection.
- The Metal renderer consumes model snapshots or dirty ranges, never raw PTY bytes.

## Architecture

### UI Shell

The UI shell is a macOS 15+ native SwiftUI application. SwiftUI owns the application and window lifecycle. An AppKit bridge provides low-level key event handling and hosts the Metal rendering view.

Responsibilities:

- create one terminal window,
- restore window size and position,
- route application commands,
- manage focus,
- bridge keyboard and resize events to the terminal session,
- expose native accessibility hooks where practical.

The MVP has a single terminal pane. Splits and multiple windows are excluded from this milestone.

### PTY Adapter

The PTY adapter owns the local pseudo-terminal session and default shell process.

Responsibilities:

- launch the user's default shell,
- write keyboard input and mapped terminal escape sequences,
- asynchronously read shell output,
- propagate terminal resize events,
- close file descriptors and terminate child processes gracefully,
- apply backpressure so sustained output does not grow memory without bounds.

The adapter must have explicit lifecycle states for launch, running, terminating, exited, and failed.

### Parser Boundary

The parser boundary accepts PTY bytes and emits terminal events. It should be small and replaceable.

Responsibilities:

- parse supported ANSI, CSI, OSC, and control sequences,
- reject or safely bound malformed and unreasonably large sequences,
- emit typed events rather than mutating the renderer,
- keep parser internals hidden from the terminal model.

The first parser can be Swift-native. A future parser adapter may be introduced only if tests and performance measurements justify it.

### Terminal Model

The terminal model is pure Swift state with no UI or Metal dependencies.

Responsibilities:

- maintain the primary screen grid,
- maintain alternate screen state for full-screen terminal apps,
- track cursor position and style,
- track text attributes and ANSI colors,
- apply erase, clear, scroll, insert, delete, and resize operations,
- keep bounded in-memory scrollback with a hard cap,
- track dirty ranges for rendering,
- own cell-aware selection state.

The model should be deterministic and covered by unit tests. Renderer behavior should be testable from model output, not from PTY byte streams.

### Metal Renderer

The renderer uses Metal for terminal cell drawing.

Responsibilities:

- create and maintain a fast monospace glyph atlas,
- render crisp antialiased text,
- render ANSI color attributes,
- upload changed cell data efficiently,
- use stable cell metrics for predictable layout,
- draw dirty regions where practical,
- expose frame and presentation timing for latency instrumentation.

The MVP renderer does not support ligatures or complex shaping. Those are later experiments after baseline text rendering performance is proven.

## Data Flow

Input path:

1. AppKit receives key events.
2. The key mapper converts printable keys and supported navigation shortcuts into PTY bytes or terminal escape sequences.
3. The PTY adapter writes bytes to the shell.
4. Latency instrumentation records key receipt and write timing.

Output path:

1. The PTY adapter reads shell output asynchronously.
2. The parser boundary converts bytes into typed terminal events.
3. The terminal model applies events and records dirty ranges.
4. The Metal renderer uploads changed cell data and presents a frame.
5. Latency instrumentation records observable model mutation and frame timing where available.

The renderer must not parse terminal bytes. The parser must not own rendering state. The PTY adapter must not mutate UI state directly.

## Terminal Behavior

The MVP targets CLI daily-driver basics without attempting to be a complete xterm clone.

Required behavior:

- default local shell startup,
- ANSI colors and character attributes,
- cursor movement,
- clear and erase operations,
- terminal resizing,
- bounded in-memory scrollback,
- simple text selection and copy,
- alternate screen support for tools such as `vim`, `less`, and `top`,
- enough keyboard handling for common shells and full-screen terminal apps.

Optional behavior within the MVP:

- truecolor if it falls naturally out of the attribute model,
- bracketed paste if it is covered by tests and does not complicate the input path,
- basic mouse reporting if it is covered by tests and does not threaten the latency goal.

Out of scope:

- broad xterm compatibility,
- advanced OSC integrations,
- local shell prompt editing,
- terminal multiplexing.

## Key Mapping

Prompt navigation is implemented by sending terminal escape sequences. The terminal does not inspect or edit the prompt locally.

Required mappings:

- Option-Left sends `ESC b` for word-left.
- Option-Right sends `ESC f` for word-right.
- Command-Left sends `Ctrl-A` (`0x01`) for line start.
- Command-Right sends `Ctrl-E` (`0x05`) for line end.

These defaults match common shell readline behavior and must be covered by key mapping tests. A future settings milestone can add configurable mappings if needed.

## Selection

Selection is cell-aware.

The MVP should support:

- click-and-drag selection across cells,
- double-click token selection,
- copy selected text.

Double-click token selection uses conservative rules:

- stop at whitespace,
- stop at common delimiters for shell tokens,
- keep URL-safe characters inside a selected URL-like token.

Selection should avoid surprising wrapped-line grabs when the user is trying to copy a URL or a short string. More advanced URL detection and wrapped-string selection are deferred.

## Scrollback

The MVP uses bounded in-memory scrollback only.

Requirements:

- enforce a hard line or byte cap,
- discard old scrollback predictably,
- avoid retaining stale cell buffers after discard,
- test memory behavior under sustained output.

Disk-backed history and indexed search are post-MVP features.

## Persistence

The MVP persists only window geometry.

Requirements:

- remember the terminal window size and position,
- restore that geometry on next launch when valid,
- fall back to a sane default when the saved geometry is unavailable or off-screen.

The MVP does not restore shell process state, terminal contents, scrollback, search state, split layout, tabs, multiple windows, or desktop Space.

## Performance

The project goal is extremely low latency from keystroke to character on screen. The MVP must include instrumentation before features expand beyond the core path.

Instrumentation should record:

- key event receipt time,
- PTY write time,
- matching model mutation time when observable,
- Metal frame commit or present timing where available.

The MVP should define a numeric p95 keystroke-to-present budget after the first instrumented prototype runs on the dev machine. That budget becomes a gate for new terminal behavior and renderer changes.

Acceptance criteria:

- normal shell typing does not appear visibly batched or delayed,
- sustained terminal output remains responsive,
- scrollback cap prevents unbounded memory growth,
- performance tests are repeatable enough to catch regressions.

## Error Handling

The MVP must handle:

- shell launch failure with a native error state,
- PTY read/write errors,
- shell exit,
- malformed escape sequences,
- oversized parser parameters,
- renderer initialization failure,
- invalid saved window geometry.

Error states should be visible through native UI placeholders or status surfaces without blocking cleanup. Failed PTY sessions must not leave orphan processes or open file descriptors.

## Security And Memory

Security and memory checks are part of the design, not a release afterthought.

Requirements:

- bound parser buffers and parameter lists,
- bound scrollback memory,
- close PTY file descriptors on shutdown,
- terminate or detach shell processes deliberately,
- avoid retaining obsolete Metal buffers,
- avoid unsafe string handling in parser and selection code,
- keep shell execution local and explicit,
- do not introduce external network access in the MVP.

## Testing

Every MVP feature requires strict tests.

Required unit tests:

- parser events for supported sequences,
- malformed and oversized sequence handling,
- grid mutations,
- cursor movement,
- resize behavior,
- alternate screen switching,
- scrollback cap enforcement,
- key mapping,
- selection token rules,
- window geometry persistence.

Required integration tests:

- PTY launch and shell echo,
- PTY resize propagation,
- full-screen alternate screen behavior with a simple fixture,
- shutdown cleanup.

Required renderer and performance tests:

- glyph atlas creation,
- cell buffer update correctness,
- ANSI color rendering metadata,
- nonblank frame output where practical,
- sustained output throughput,
- keystroke-to-present latency measurement.

Leak and security checks should cover PTY lifetime, file descriptors, parser bounds, scrollback memory, and Metal resource cleanup.

## Milestone Boundary

The MVP is complete when a user can launch Wanda, interact with one local shell, see Metal-rendered terminal text, use common command-line tools including basic alternate-screen tools, select and copy text, resize the window, relaunch with geometry restored, and observe measured latency that satisfies the agreed budget.

Post-MVP work should be split into separate specs:

- splits and multiple windows,
- large scrollback and indexed search,
- richer text shaping and font fallback,
- session restore beyond window geometry,
- advanced terminal compatibility.
