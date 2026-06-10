//! Reproducible micro-benchmarks for the telemetry hot paths.
//!
//! These are `#[ignore]`d so they never run in the normal `cargo test` gate;
//! invoke them explicitly for before/after measurement:
//!
//! ```bash
//! cargo test --release -p edex-core --test telemetry_perf -- --ignored --nocapture
//! ```
//!
//! They print wall-clock timings to stdout. Numbers are inherently
//! machine/load-dependent, so always compare a before/after pair captured on
//! the same machine in the same session.

use edex_core::sysinfo::SysinfoService;
use std::time::Instant;

fn median_ms(mut samples: Vec<f64>) -> f64 {
    samples.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let n = samples.len();
    if n == 0 {
        return 0.0;
    }
    if n % 2 == 1 {
        samples[n / 2]
    } else {
        (samples[n / 2 - 1] + samples[n / 2]) / 2.0
    }
}

/// Finding #1: cost of constructing the sysinfo service at app launch.
#[test]
#[ignore]
fn bench_service_construction() {
    let iters = 8;
    let mut samples = Vec::with_capacity(iters);
    for _ in 0..iters {
        let start = Instant::now();
        let service = SysinfoService::new();
        let elapsed = start.elapsed().as_secs_f64() * 1000.0;
        std::hint::black_box(&service);
        samples.push(elapsed);
    }
    println!(
        "[bench] SysinfoService::new()  median={:.2}ms  samples={:?}",
        median_ms(samples.clone()),
        samples
            .iter()
            .map(|v| format!("{v:.1}"))
            .collect::<Vec<_>>()
    );
}

/// Finding #2/#3: cost of the CPU panel's per-second snapshot path.
///
/// BASELINE: the CPU panel routes through `panel_snapshot(false, 5, false)`,
/// which rebuilds the full process table on every call.
/// AFTER: switch this body to the new CPU-only service method.
#[test]
#[ignore]
fn bench_cpu_snapshot() {
    let service = SysinfoService::new();
    // Warm up: first call primes per-core deltas AND the one-time process seed,
    // so the measured calls reflect the steady-state (no process scan).
    let _ = service.cpu_snapshot();
    let iters = 12;
    let mut samples = Vec::with_capacity(iters);
    for _ in 0..iters {
        let start = Instant::now();
        let snap = service.cpu_snapshot().expect("cpu path");
        let elapsed = start.elapsed().as_secs_f64() * 1000.0;
        std::hint::black_box(&snap);
        samples.push(elapsed);
    }
    println!(
        "[bench] cpu_snapshot  median={:.2}ms  samples={:?}",
        median_ms(samples.clone()),
        samples
            .iter()
            .map(|v| format!("{v:.1}"))
            .collect::<Vec<_>>()
    );
}

/// Finding #2: raw cost of one CPU-temperature (Components/SMC) read — the
/// single most expensive telemetry call. This is the cache-MISS cost the TTL
/// now amortises to once per 15 s instead of once per CPU poll.
#[test]
#[ignore]
fn bench_cpu_temperature_read() {
    let service = SysinfoService::new();
    let _ = service.cpu_temperature();
    let iters = 5;
    let mut samples = Vec::with_capacity(iters);
    for _ in 0..iters {
        let start = Instant::now();
        let r = service.cpu_temperature().expect("temp");
        let elapsed = start.elapsed().as_secs_f64() * 1000.0;
        std::hint::black_box(&r);
        samples.push(elapsed);
    }
    println!(
        "[bench] cpu_temperature (cache-miss) median={:.2}ms samples={:?}",
        median_ms(samples.clone()),
        samples
            .iter()
            .map(|v| format!("{v:.1}"))
            .collect::<Vec<_>>()
    );
}

/// Finding #3: cost of the compact TOPLIST snapshot (no full process list).
/// BASELINE: `panel_snapshot(true, 5, false)`. AFTER: switch to the new
/// shared-process-cache TOPLIST method.
#[test]
#[ignore]
fn bench_toplist_snapshot() {
    use std::time::Duration;
    let service = SysinfoService::new();
    // ZERO dedup TTL so every call actually refreshes — measures the per-refresh
    // cost (which is unchanged; the TOPLIST win is frequency, not per-call cost).
    let _ = service.toplist_snapshot(true, 5, false, Duration::ZERO);
    let iters = 12;
    let mut samples = Vec::with_capacity(iters);
    for _ in 0..iters {
        let start = Instant::now();
        let snap = service
            .toplist_snapshot(true, 5, false, Duration::ZERO)
            .expect("toplist path");
        let elapsed = start.elapsed().as_secs_f64() * 1000.0;
        std::hint::black_box(&snap);
        samples.push(elapsed);
    }
    println!(
        "[bench] toplist_snapshot  median={:.2}ms  samples={:?}",
        median_ms(samples.clone()),
        samples
            .iter()
            .map(|v| format!("{v:.1}"))
            .collect::<Vec<_>>()
    );
}
