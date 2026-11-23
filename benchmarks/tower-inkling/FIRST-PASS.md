# Tower: Inkling inference tuning, 2026-11-23

The accepted change is `--ubatch-size 128` → `192` in
`machines/tower/inference.nix`. It improves cold prompt processing on this
16 GB RTX 5070 Ti while retaining the same abliterated IQ3_S model,
32,768-token context, q8_0 KV cache, single slot and reasoning defaults.
The model and llama.cpp b12633/CUDA 12.8 binaries remain pinned.

## Results

Medians exclude warmup. The baseline combines runs A/B (12 decode and 6
prefill samples); the candidate combines runs A/B/C (18 decode and 9 prefill
samples). Each run uses the same six deterministic prompts. TTFT is measured
by a client on Tower, so network latency is excluded. Prompt caching is disabled
and the server must report zero cached tokens. Timing panels explicitly use
reasoning effort 0; these figures do not predict the wait for a full reasoning
answer under the unchanged service defaults.

| Metric | Baseline (128) | Accepted (192) | Final deployed |
| --- | ---: | ---: | ---: |
| Cold 4K TTFT | 4.015 s | 3.462 s | 3.464 s |
| Cold 4K prompt processing | 1021 tok/s | 1184 tok/s | 1183 tok/s |
| Short-context generation | 77.14 tok/s | 76.98 tok/s | 77.06 tok/s |
| Peak observed VRAM | 14158 MiB | 14556 MiB | 14556 MiB |
| Cold 16K retrieval TTFT | 18.612 s | 16.353 s | — |
| Cold near-32K retrieval TTFT | 43.635 s | 39.223 s | 39.176207999999995 s |

The 16K/32K rows are single cold retrieval requests per configuration, not
statistical estimates. The 32K request contains 32,512 input tokens plus a
128-token output allowance, leaving room in the configured context.

## Experiments and acceptance

- Baseline A → batch 512 → baseline recovery → batch 192 A → baseline B →
  baseline long-context tests → batch 192 B → GPU sampling → batch 192 C →
  candidate long-context tests → Nix deployment → final qualification.
- Physical batch **512** failed at startup: a 3,356 MiB compute allocation
  exceeded available VRAM. Rejected; the baseline was restored. The original
  restart policy retried during the health wait; subsequent experiments
  disabled automatic retries. `ubatch512-rejected.log` retains the failure.
- Physical batch **192** repeatedly reduced cold 4K TTFT by about 14%.
  Peak observed total GPU memory increased by 398 MiB, below the experiment
  cap of 14,750 MiB. The cap leaves at least 1,553 MiB free; sampling once per
  second is an observation, not a guarantee against sub-second spikes.
- GPU sampling at batch 192 produced ~77.73 tokens/sec versus ~76.97 in its
  adjacent controls (under 1%), while 4K TTFT worsened slightly. Rejected as
  too small a practical benefit to retain another change.
- All six short greedy decode outputs matched baseline exactly. The 4K
  summaries changed wording when batch size changed, while retaining the
  same factual content on inspection. **This is not a bit-identical or
  universally lossless change.** Different prefill batching changes the
  floating-point execution path; these small checks cannot establish general
  model accuracy.
- All three planted codes were recovered at 10%, 50% and 90% of both 16K
  and near-32K contexts, for baseline and candidate. No context truncation.
- OpenAI-compatible chat, reasoning (17 × 12 = 204), forced structured tool
  arguments and a tool-result round trip passed. These are smoke tests, not
  a broad reasoning or coding benchmark. Synthetic tool results are used;
  no external service is called.
- The complete Tower NixOS configuration built successfully. Comparing its
  closure and `/etc` against the live generation showed only the Inkling
  unit changed. It was switched on Tower; the temporary benchmark override
  was removed. Final qualification repeats the panel, functional checks and
  near-32K retrieval on that deployed generation. No GPU Xid errors observed.

The engine already uses CUDA graphs and full GPU offload. Further large decode
speedups probably require kernel/engine work or a different quality/memory
tradeoff, rather than this prompt-batch adjustment. The measured hardware
rooflines in `THEORY.md` are deliberately optimistic bounds, not achievable
serving promises. No claim of a significant decode speedup is made here.

## Reproduce

Go tools use only the standard library. Run benchmarks on Tower with no other
inference traffic, one GPU job at a time. The panel takes an advisory lock,
checks the server is idle, verifies only llama-server is using GPU compute,
checks the power cap is unchanged, and cancels its request above the VRAM cap.
These checks do not reserve the API against unrelated clients. Drain ordinary
traffic first. Do not kill a request mid-prefill to switch configurations.

Build on a Mac or Linux host from the repository root:

```sh
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o /tmp/inkling-bench ./benchmarks/tower-inkling/cmd/bench/main.go
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o /tmp/inkling-acceptance ./benchmarks/tower-inkling/cmd/acceptance/main.go
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o /tmp/inkling-gguf ./benchmarks/tower-inkling/cmd/gguf/main.go
```

Copy binaries to Tower, then run locally there against `127.0.0.1:8080`:

```sh
./inkling-bench -tag my-run > my-run.jsonl
./inkling-bench -mode needle -size 16384 -tag my-run-16k > my-run-16k.jsonl
./inkling-bench -mode needle -size 32512 -tag my-run-32k > my-run-32k.jsonl
./inkling-acceptance > my-run-acceptance.jsonl
./inkling-gguf /path/to/Inkling-2-Mini-Uncensored-AD-IQ3_S.gguf > model-metadata.json
```

Set only `--ubatch-size` to 128 for the control or 192 for the candidate in
`machines/tower/inference.nix`, then build/switch the Tower configuration using
the repository deployment procedure. The JSON files in `configs/` record the
complete experimental settings; `best-config.json` records the accepted one.
The model hash is pinned in both the Nix configuration and these records.

The optional `hardware/main.c` probe builds on Tower with
`gcc -O2 hardware/main.c -ldl -o hardware`. Set `LD_LIBRARY_PATH` to the pinned
llama.cpp package's `lib` directory and `/run/opengl-driver/lib` to run it.
Run only while inference is idle; its peak allocation is 384 MiB. It is a
host-only CUDA/cuBLAS probe and needs no nvcc. The GGUF inventory's active-weight
estimate is specific to this Inkling model's loop and expert structure.

Raw JSONL records retain outputs, hashes, prompt/decode timings, TTFT and
observed memory. `acceptance.jsonl` and `deployed-acceptance.jsonl` retain the
functional API responses. No model weights or credentials are included.

Method adapted from the
[inference-optimisation skill](https://github.com/sybil-solutions/inference-optimisation-skill):
controlled baselines, measured hardware ceilings, one change at a time,
long-context/functional checks, and a ledger including rejected experiments.
