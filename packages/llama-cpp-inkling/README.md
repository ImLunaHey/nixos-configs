# Tower's Inkling CUDA engine

Pins the Inkling branch of `Mcniiby/ik_llama.cpp-mcniiby` at
`46b11f422d42ce4eb7cf8d92386cf36f60a1af86`, built for Tower's RTX 5070 Ti
(sm_120) with the locked Nixpkgs CUDA 12.8 toolchain. Model weights remain
in `machines/tower/inference.nix`; this package does not fetch or requantize them.

The upstream describes this fork as an **unmaintained research showcase**.
We pin and qualify this revision rather than following its branch. Keep the
original `packages/llama-cpp-cuda` package available as a fallback.

`kernels.nix` builds the unchanged upstream GPU/model libraries and their
numerical tests. `default.nix` builds the HTTP/template layer against those
exact libraries. This avoids recompiling CUDA when correcting server-only
compatibility issues. Its small local patch:

- Implements recursive `tojson(sort_keys=true)` required by the model's tool
  template, without changing the template or mutating its inputs. Includes a
  nested-object/array ordering regression test.
- Sets `SO_REUSEADDR` in addition to the HTTP library's existing `SO_REUSEPORT`,
  so the service can take over port 8080 after the previous engine stops.

The service supplies `/run/opengl-driver/lib` through `LD_LIBRARY_PATH` for
NixOS's installed NVIDIA driver. Runtime libraries otherwise use store RPATHs.
No driver, power-limit, vocabulary, loop-count or reasoning-default change.

Five CPU/GPU numerical suites and all 1,439 Jinja assertions were run on the
built artifacts. Model-level qualification and reproducible measurements are
under `benchmarks/tower-inkling/`. The checked kernel types cover this GGUF's
F32, Q8_0, IQ4_NL and IQ3_S tensors, plus types needed by its numerical tests.
This is a Tower-specific package, not a general-purpose replacement for every
model or GPU.

The KV kernel allowlist also includes Q4_0 for Tower's qualified GPU-only 128K
profile (batch 1024, physical batch 224, INKLING_Q4_VEC=1).
Run `test-fa-relbias CUDA` to exercise the additional q4 attention cases.
The CPU q4 cases currently fail in this build, so do not use this profile
with CPU attention/offload. Qualification is in
`benchmarks/tower-inkling/context-128k/PLAN.md`.

`INKLING_Q4_VEC=1` selects direct q4 vector attention for single-token,
128-wide full attention and small relative-bias batches. It avoids converting
the whole KV cache to f16 for each decode step. The default remains off so the
original path is available for controlled comparisons. The patch reuses
existing CUDA kernels; expanded tests cover full attention at 4K/32K/128K and
relative-bias decode/prefill. See the tuning ledger before enabling it.
