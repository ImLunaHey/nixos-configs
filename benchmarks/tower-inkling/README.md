# Tower: Inkling inference optimization, 2026-11-23

The accepted configuration uses the pinned Inkling-specific engine in
`packages/llama-cpp-inkling`, logical batch 1024 and physical batch 512. It
retains the original abliterated IQ3_S GGUF, all vocabulary entries, three
loop passes, 32,768-token context, q8_0 KV precision, one slot and reasoning
defaults. The first pass only tuned mainline's batch size; Luna challenged
that early stopping point, and the second pass tested the larger engine/kernel
opportunity. `FIRST-PASS.md` preserves that earlier report.

## Measurements

| Configuration | Decode tok/s | Cold 4K TTFT | Prefill tok/s | Observed panel VRAM |
| --- | ---: | ---: | ---: | ---: |
| Original mainline, physical batch 128 | 77.14 | 4.015s | 1021 | 14,158 MiB |
| First pass mainline, physical batch 192 | 77.17 | 3.452s | 1188 | 14,556 MiB |
| Deployed Inkling engine, batch 1024 / physical 512 | 127.38 | 1.436s | 2856 | 14,166 MiB |

The deployed result is **65.1% faster decode** and **64.2% lower cold 4K
TTFT** than the original baseline. Against the same-token-ID first-pass
control, decode is 65.1% faster and cold 4K TTFT is 58.4% lower.

Final 16K retrieval passed in 5.812s to first token. Three near-32K checks
all passed, with TTFT 12.111–12.539s (median 12.120s). Peak observed GPU use
across these checks was 14,232 MiB, leaving 2,071 MiB. A graceful service
restart and a second complete chat/reasoning/tool check also passed.


The baseline and candidate receive exactly the same frozen token-ID fixtures.
Medians exclude warmup. Decode uses six code/prose prompts per panel and
192-token output limits; cold prefill uses three 4,096-token prompts per panel.
Timing panels explicitly disable reasoning and prompt caching. Client TTFT is
measured on Tower, excluding LAN latency. Default high-reasoning answer time is
not represented by these figures. The same updated Go harness checks all input
tokens were processed and normalizes both engines to `(predicted_n - 1) /
predicted_ms`, since the first token is produced during prefill. Raw timings
and input/output hashes remain in each JSONL record.

The 16K retrieval check is a single run; the final near-32K check is repeated
three times. These are functional gates, not broad statistical estimates. Near-32K means 32,512 input tokens plus a 128-token
output allowance. Every retrieval test places three codes at 10%, 50% and 90%
of the document and requires all three exact codes back.

## What changed and why

The [pinned engine](https://github.com/Mcniiby/ik_llama.cpp-mcniiby/tree/46b11f422d42ce4eb7cf8d92386cf36f60a1af86)'s
Inkling-specific graph and CUDA kernels produced the large decode
gain on the existing weights. Its lower scratch-memory use also allowed a
larger physical batch. Moving from physical batch 192 to 512 cut cold prefill
latency again; logical batch 1024 provided a further improvement. Physical
batch 768 used more memory and was slightly slower, so it was rejected.

This differs from the author's advertised demo: we did **not** use its IQ3_QT
quantization, prune output vocabulary, reduce loop count or replace the
abliterated model. The author's reported speed is not used as a Tower result.
`THEORY.md` retains the measured hardware bounds: the ~222 tok/s bandwidth-only
decode ceiling and ~8.9K prefill tok/s estimate are optimistic, not serving
promises.

Two small server compatibility fixes were necessary: recursive JSON key
sorting for tool templates, and socket address reuse for a clean transition
from the old server. The patch, regression test, engine commit and source hash
are pinned in the package. GPU libraries stay unchanged from the tested fork.

## Qualification and limits

- Five fused-operation/attention suites passed on CPU and CUDA, with zero
  failures. All 1,439 Jinja assertions passed, including the new nested sorting
  and input-order regression test.
- Chat, reasoning, structured tool arguments and a complete tool-result round
  trip passed. Baseline/candidate 16K and near-32K retrieval checks passed.
- The complete Tower Nix configuration builds from the pinned source. The
  deployed build is rechecked using the same fixtures and functional gates.
- The memory watchdog caps observed total GPU use at 14,750 MiB, leaving at
  least 1,553 MiB free. Sampling is once per second, so it cannot guarantee
  there are no shorter peaks. No other compute GPU job runs during benchmarks.
- This engine changes floating-point execution and includes a tokenizer fix.
  Output text is **not universally bit-identical**. Numerical kernel tests,
  retained weights and these functional checks do not establish broad coding
  or reasoning accuracy equivalence. Outputs/hashes are preserved for review.
- The upstream calls itself an **unmaintained research showcase**. The package
  pins one qualified revision plus two local compatibility fixes. That is a
  maintenance tradeoff; the old mainline package remains available for rollback.
- No multi-user throughput claim: the service retains one full-context slot.

Rejected experiments, build/compatibility findings and raw results are in
`deeper/PLAN.md`. DSpark was tested but the published drafter did not match the
installed loader's tensor shapes; those checks were not bypassed. The first
pass also rejected a mainline batch-512 allocation failure and a <1% GPU
sampling gain. Startup failures are not performance measurements.

## Reproduce

Build the Go tools from the repository root (standard library only):

```sh
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o /tmp/inkling-bench ./benchmarks/tower-inkling/cmd/bench/main.go
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o /tmp/inkling-acceptance ./benchmarks/tower-inkling/cmd/acceptance/main.go
```

Copy them and the frozen fixtures under `deeper/` to Tower. With ordinary
traffic drained, run one process at a time against the local server:

```sh
./inkling-bench -fixtures panel-fixtures.json -tag control > control.jsonl
./inkling-bench -fixtures needle16k-fixtures.json -tag control-16k > control-16k.jsonl
./inkling-bench -fixtures needle32k-fixtures.json -tag control-32k > control-32k.jsonl
./inkling-acceptance > acceptance.jsonl
```

Use `-url http://127.0.0.1:8081` for a candidate on the comparison port. The
harness takes an advisory lock, checks the server is idle, checks only
llama-server is using GPU compute, verifies the power cap is unchanged, and
cancels its request above the memory cap. These checks do not reserve the API
against unrelated clients. Drain requests before changing configurations;
never force-kill a server during a prefill batch.

Use the package and service settings in this commit for the accepted engine.
For the mainline control use `packages/llama-cpp-cuda` with logical batch 512,
physical batch 192 and no `--swa-compress` (mainline already sizes SWA caches).
Use physical batch 128 to reproduce the original first-pass baseline. Keep
all other model/context/KV/power settings fixed. Run controls on both sides of
a candidate and repeat wins. `deeper/configs/` records the tested settings.

Method adapted from the
[inference-optimisation skill](https://github.com/sybil-solutions/inference-optimisation-skill):
measured ceilings, controlled comparisons, one lever at a time, memory limits,
functional/long-context gates and a ledger including rejected experiments.
