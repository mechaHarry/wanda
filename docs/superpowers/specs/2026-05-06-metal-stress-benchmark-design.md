# Metal Stress Benchmark Design

Date: 2026-05-06
Status: Approved design, pending implementation plan

## Goal

Add a native Wanda benchmark command that opens a real Wanda window, drives a deterministic terminal stress workload through the existing Metal-backed rendering path, prints final performance metrics, and compares those metrics against a checked-in repo baseline.

The benchmark is intended to measure Wanda's visible rendering experience, especially Metal frame presentation timing, frame rate, characters per second, and total print time. It intentionally avoids PTY and shell scheduling overhead for the first baseline so the baseline reflects the terminal model, SwiftUI window, Metal renderer, and display presentation path rather than child-process buffering.

## User Flow

Wanda adds a native macOS menu command:

`Benchmark > Run Metal Stress Benchmark`

Selecting the command opens a new benchmark Wanda window and starts the benchmark immediately. The window uses the same terminal rendering surface as a normal Wanda terminal window, but it does not start a shell and it does not treat user keystrokes as benchmark input.

During the run, the benchmark window prints a deterministic ANSI stress stream. When the final batch has been submitted and the final frame has been presented, Wanda appends a summary block in the terminal window with:

- workload ID
- workload hash
- total characters printed
- total bytes processed
- total print time
- average frame-present latency
- p95 frame-present latency
- average FPS during the benchmark
- characters per second
- comparison against the checked-in baseline

## Workload

The first workload is versioned as `metal-stress-v1`.

The workload is generated from code rather than stored as a giant text fixture. The generator is deterministic and exposes a stable content hash so future runs can verify that the workload matches the baseline.

The workload stresses:

- ANSI foreground and background colors across the 16-color palette
- bold, underline, italic, and inverse attributes already supported by Wanda
- long wrapped lines and short fragmented lines
- dense ASCII patterns and punctuation
- fallback-safe box-like text patterns using supported glyphs
- URLs, paths, repeated identifiers, and long token runs
- enough output to force many screen updates and scrollback movement

The first version stays within Wanda's current ASCII-oriented glyph atlas. Unicode, ligatures, and broader font-shaping stress cases remain future benchmark workloads after the simple Metal text path has a stable baseline.

## Measurement Model

The benchmark uses an internal output generator but still opens a real benchmark window and renders through the existing Metal view.

The runner records:

- `start`: immediately before the first generated batch is applied
- one submitted timestamp per output batch
- one frame-present timestamp for the first Metal frame presented after each submitted batch
- `finish`: the frame-present timestamp for the final benchmark batch

The runner feeds output in bounded batches on the main actor and yields between batches so SwiftUI and Metal can present frames during the run.

Metrics:

- `totalPrintTime`: final benchmark frame-present timestamp minus first submitted timestamp
- `charactersPerSecond`: total characters divided by total print time
- `averageFrameLatency`: average of per-batch `submitted -> framePresented` durations
- `p95FrameLatency`: p95 of per-batch `submitted -> framePresented` durations
- `averageFPS`: presented benchmark frame count divided by elapsed presented-frame time
- `bytesProcessed`: UTF-8 byte count submitted to `TerminalViewModel.processOutput`

Frame timing uses Wanda's existing `TerminalMetalRenderer` completed-command-buffer callback as the presentation signal. This is not a photodiode-level display measurement; it is Wanda's practical in-app proxy for "Metal work for this frame completed and was presented to the drawable."

## Baseline

The first checked-in baseline is stored as JSON:

`Benchmarks/baselines/metal-stress-v1.json`

The app bundle build step copies this repo-owned baseline into `dist/Wanda.app/Contents/Resources/Benchmarks/baselines/metal-stress-v1.json`. The runtime loader reads the bundled copy first. During SwiftPM diagnostics, it may also fall back to the repo-relative path when running from the checkout.

The baseline includes:

- schema version
- workload ID
- workload hash
- timestamp
- git commit used to create the baseline
- macOS version
- Metal device name
- window size
- terminal rows and columns
- total characters
- total bytes
- total print time
- average frame latency
- p95 frame latency
- average FPS
- characters per second

The benchmark command reads this file and prints percentage deltas for the current run versus the baseline. Faster throughput and FPS are positive; lower latency and total time are positive.

Because this is a full-window rendering benchmark, the baseline is machine-sensitive. The metadata is part of the baseline so differences in display, OS, GPU, or window geometry are visible when comparing runs.

## Architecture

New files:

- `Sources/Wanda/Benchmark/TerminalBenchmarkWorkload.swift`
  - Generates `metal-stress-v1`.
  - Computes stable workload metadata and hash.

- `Sources/Wanda/Benchmark/TerminalBenchmarkRunner.swift`
  - Owns batch scheduling, timing, frame accounting, metric computation, and summary rendering.
  - Uses injectable clocks/timing hooks for deterministic tests.

- `Sources/Wanda/Benchmark/TerminalBenchmarkBaseline.swift`
  - Defines Codable baseline models.
  - Loads the bundled baseline JSON, with a repo-relative fallback for SwiftPM diagnostics.
  - Computes signed percentage comparisons.

- `Sources/Wanda/App/BenchmarkTerminalWindowView.swift`
  - Hosts a benchmark-specific terminal window.
  - Reuses the existing Metal terminal view path.
  - Does not start a PTY.

Potential shared extraction:

- If needed, extract the common Metal terminal surface from `TerminalWindowView` into a small shared view so normal terminal and benchmark windows use the same rendering path without duplicating overlay/input/status code.

Updated files:

- `Sources/Wanda/App/WandaApp.swift`
  - Adds the benchmark window scene.
  - Adds the `Benchmark` command menu with `Run Metal Stress Benchmark`.

- `README.md`
  - Documents how to run the benchmark and how to interpret the baseline.

- `script/build_and_run.sh`
  - Copies checked-in benchmark baselines into the staged app bundle resources.

## Error Handling

If Metal is unavailable, the benchmark window shows the existing renderer-unavailable placeholder and prints a benchmark failure status rather than crashing.

If the baseline JSON is missing, malformed, or has a workload hash mismatch, the benchmark still runs and prints current metrics, but it reports that no comparable baseline is available.

The benchmark runner caps pending batch measurements so a stalled render path cannot grow memory without bound.

## Security And Resource Use

The benchmark does not execute shell commands and does not spawn a child process. It generates deterministic in-process output only.

The workload size, batch size, and pending frame measurements are bounded. The run is finite and should not create unbounded scrollback beyond Wanda's existing scrollback cap.

The baseline loader reads only the repo baseline file bundled with the app during development. It does not fetch remote data.

## Testing

Tests are written before implementation code.

Automated tests cover:

- `metal-stress-v1` workload stability
- workload hash stability
- workload contains ANSI color/style escape sequences
- workload includes long lines and wrapped-line stress
- metric computation for total duration, characters/sec, FPS, average latency, and p95 latency from injected timestamps
- baseline JSON decoding
- baseline comparison direction and percentage math
- benchmark orchestration completes without starting a PTY when driven by fake frame timestamps
- memory bounds for pending batch measurements

Manual verification covers:

- `swift test`
- `swift build`
- `./script/build_and_run.sh --verify`
- launch Wanda, choose `Benchmark > Run Metal Stress Benchmark`, confirm a benchmark window opens and prints a final summary
- confirm the final summary includes current metrics and baseline comparison

## Non-Goals

This first benchmark does not:

- benchmark PTY read/write throughput
- benchmark shell command execution
- benchmark Unicode shaping, ligatures, emoji, or non-ASCII glyph coverage
- update the baseline automatically from the menu
- claim cross-machine comparability without checking baseline metadata
