# StrataVarious — Performance Reference

## Methodology

Benchmarks run via `node tests/bench.mjs` (ESM, Node ≥ 18).

Each benchmark runs a function N times in a tight loop, records per-iteration wall-clock times, then reports **P50 / P95 / max** (milliseconds). P95 is the operative threshold — it accounts for JIT warm-up and GC pauses without being distorted by outliers.

No external dependencies. No I/O. Pure in-process computation.

## Reference Numbers

Measured on **MacBook Air M2, macOS 15, Node v25.9.0** (2026-05-10, `chore/bench-realistic`).

| Benchmark | Iterations | P50 (ms) | P95 (ms) | Threshold |
|---|---|---|---|---|
| scrubSecrets — 100 KB, high-density secrets | 100 | 1.31 | 1.48 | **5 ms** |
| scrubSecrets — 256 KB, ~20 realistic secrets | 100 | 2.83 | 3.18 | **20 ms** |
| stripInvisibleUnicode — 100 KB | 100 | 0.11 | 0.28 | **2 ms** |
| extractFromTranscript — 500 entries | 50 | 0.77 | 1.12 | **20 ms** |
| extractFromTranscript — 1000 entries (~256 KiB) | 100 | 1.45 | 1.69 | **500 ms** |

## Thresholds and Rationale

| Function | P95 threshold | Rationale |
|---|---|---|
| `scrubSecrets` (100 KB dense) | 5 ms | Worst-case density; real sessions rarely exceed this |
| `scrubSecrets` (256 KB realistic) | 20 ms | ~20 secrets per 256 KiB — typical large session |
| `stripInvisibleUnicode` | 2 ms | Single regex pass, O(n) |
| `extractFromTranscript` (500 entries) | 20 ms | Baseline; guards against accidental complexity increase |
| `extractFromTranscript` (1000 entries) | 500 ms | Comfortable margin below the 5 s hook timeout |

The Stop hook runs synchronously after every Claude response. Any regression above these thresholds is user-perceptible.

## Running the Benchmark

```bash
node tests/bench.mjs
# or
npm run bench
```

## CI

A `perf-check` job is available in `.github/workflows/ci.yml` as a manual `workflow_dispatch` trigger. It is **not** part of the default push/PR pipeline (non-blocking by design — benchmarks are sensitive to runner CPU load). Run it before any merge that touches `scrubSecrets`, `extractFromTranscript`, or `stripInvisibleUnicode`.
