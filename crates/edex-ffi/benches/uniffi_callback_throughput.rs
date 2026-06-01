use criterion::{black_box, criterion_group, criterion_main, Criterion, Throughput};
use edex_core::pty::PtyOutputObserver;
use std::sync::atomic::{AtomicUsize, Ordering};

struct CountingSink {
    bytes: AtomicUsize,
}

impl PtyOutputObserver for CountingSink {
    fn on_output(&self, _id: u32, bytes: Vec<u8>) {
        self.bytes.fetch_add(bytes.len(), Ordering::Relaxed);
    }

    fn on_exit(&self, _id: u32, _status: Option<i32>) {}

    fn on_metadata(&self, _id: u32, _cwd: Option<String>, _process: Option<String>) {}
}

fn observer_dispatch_throughput(c: &mut Criterion) {
    let sink = CountingSink {
        bytes: AtomicUsize::new(0),
    };
    let payload = vec![0_u8; 4096];

    let mut group = c.benchmark_group("pty_observer_dispatch");
    group.throughput(Throughput::Bytes(payload.len() as u64));
    group.bench_function("rust_trait_4k_chunks", |b| {
        b.iter(|| sink.on_output(1, black_box(payload.clone())))
    });
    group.finish();
}

criterion_group!(benches, observer_dispatch_throughput);
criterion_main!(benches);
