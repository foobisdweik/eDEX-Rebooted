# Telemetry performance benchmarks — 2026-06-09

Branch: `codex/native-telemetry-perf` (off `post-web-runtime`).
Machine: Apple Silicon (aarch64-apple-darwin), Darwin 25.6.0. Same machine,
build type (`--release`), and session used for the before/after pair.

Harness: `crates/edex-core/tests/telemetry_perf.rs`, run as

```bash
cargo test --release -p edex-core --test telemetry_perf -- --ignored --nocapture --test-threads=1
```

Each figure is the median of the printed samples (warm; first call discarded so
per-core CPU deltas and the temp cache are primed). Numbers are
machine/load-dependent — compare the pair, not absolutes.

## Headline: the dominant cost was a thermal/SMC read that returns nothing here

`Components::refresh()` (CPU temperature) costs **~107 ms per call** on this
Apple Silicon Mac and yields **no sensor data** (`main=0, cores=0`). The old
`panel_snapshot` ran it on **every** CPU poll (1 Hz) and **every** TOPLIST poll
(0.5 Hz). That single call — not the process-table scan (~3.5 ms) — was the
~85 ms-per-poll dominator.

## Rust core hot paths (per-call, release, median ms)

| Metric | Before | After | Δ abs | Δ % |
|---|---:|---:|---:|---:|
| `SysinfoService::new()` (startup construction) | 101.83 | 0.01 | −101.82 | −99.99% |
| CPU-panel poll (`cpu_snapshot`, steady state) | 84.94 | ~0.00 | −84.94 | ~−100% |
| TOPLIST poll (per actual refresh) | 89.20 | 3.44 | −85.76 | −96.1% |
| CPU-temperature read (cache **miss** cost) | 106.82 (every poll) | 106.82 (once / 15 s) | — | — |

Raw samples (ms):

- before `new()`: 112.4, 142.1, 102.8, 98.9, 108.6, 100.0, 100.8, 100.9
- before cpu path (`panel_snapshot(false,5,false)`): 63.3, 66.9, 89.0, 133.0, 89.6, 79.2, 84.8, 95.4, 85.1, 79.5, 88.6, 82.3
- before toplist (`panel_snapshot(true,5,false)`): 70.5, 139.3, 101.4, 89.0, 93.9, 85.0, 89.4, 88.6, 82.3, 94.8, 84.4, 97.1
- after `new()`: ~0.0 ×8
- after cpu (`cpu_snapshot`): 0.0 ×12 (all within the 15 s temp-cache window)
- after toplist (`toplist_snapshot`, ZERO ttl = forced refresh): 3.8, 3.3, 3.7, 3.3, 3.4, 3.7, 3.3, 3.4, 3.5, 3.4, 3.2, 3.5
- temp cache-miss: 109.5, 91.4, 99.5, 110.7, 106.8

## Steady-state CPU time spent on telemetry, at idle (computed from the above)

Per wall-clock minute, modal closed:

| Source | Before | After |
|---|---:|---:|
| CPU panel (60 polls/min) | 60 × ~85 ms = **5,100 ms** | temp miss 4 × 107 ms + cpu refresh ≈ **~430 ms** |
| TOPLIST panel | 30 × ~89 ms = **2,670 ms** | 12 × ~3.4 ms = **~41 ms** |
| **Total telemetry CPU time / min** | **≈ 7,770 ms** (~13% of one core) | **≈ 470 ms** (~0.8% of one core) |
| **Reduction** | | **≈ −94%** |

(After: 56/60 CPU polls hit the temp cache at ~0 ms; 4 miss at ~107 ms. The
temp read is shared, so whichever consumer trips the 15 s TTL pays it once.)

## Process-table refresh frequency (by construction, from the call graph)

Each full refresh is `refresh_processes_specifics(All, true, everything())`
(~3.5 ms). Single producer = `SysinfoService::toplist_snapshot`; the CPU panel
never triggers one (beyond a single launch seed).

| Source | Before | Before /min | After | After /min |
|---|---|---:|---|---:|
| CPU panel | 1 s, full refresh | 60 | no process refresh | 0 |
| TOPLIST panel | 2 s, full refresh | 30 | 5 s, shared producer | 12 |
| Process modal (open) | 1 s, full refresh | 60 | 1 s, only while visible | 60 |
| Launch | `refresh_all()` in `new()` | 1 (eager) | 1 lazy seed on first CPU poll | 1 |
| **Total (modal closed)** | | **90** | | **12** |

## Render cadence (CPU graph)

| | Before | After |
|---|---|---|
| Driver | `TimelineView(.animation)` | `TimelineView(.periodic(by: 1/30))` |
| Redraws/s on ProMotion (120 Hz) | up to 120 | 30 |
| Redraws/s on 60 Hz | 60 | 30 |

Underlying telemetry updates once per second; the extra redraws only
interpolate the horizontal scroll, so 30 Hz preserves smooth motion
(20 px/s → 0.67 px/frame) while cutting GPU redraws ≥4× on ProMotion.

## App-level CPU / energy / memory

Not sampled via `top`/`powermetrics` in this session: the app activates
fullscreen and grabs the foreground (`NSApp.activate(ignoringOtherApps:)`),
so launching it to sample would seize the user's display. The figures above are
deterministic, reproducible core-level measurements plus call-graph-derived
frequencies, which isolate exactly the work removed. A maintainer can confirm
end-to-end with `powermetrics`/Activity Monitor on a manual run.
