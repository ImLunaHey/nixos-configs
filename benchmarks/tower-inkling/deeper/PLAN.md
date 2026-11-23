# Second pass — 2026-11-23

Luna challenged stopping after the batch-size change. Continue the hill-climb
against the deployed 192 baseline: same abliterated weights and 32K context.
Do not reduce loop count, prune vocabulary, or silently switch quantizations.

## Leads

1. Inkling-specific kernels in Mcniiby/ik_llama.cpp-mcniiby, pinned commit
   46b11f422d42ce4eb7cf8d92386cf36f60a1af86. The author's identical-weight
   comparison reports ~2x decode on a 5070 Ti. Reproduce with OUR original
   IQ3_S weights, not the author's differently quantized/trimmed model.
2. DSpark, the model's native three-layer speculative drafter.
3. Mainline CUDA graph scheduling, ngram speculation, and KV kernel precision.

## DSpark compatibility failure

The b12633 executable lists draft-dspark, but the published mainline-format
Unsloth Inkling drafter at revision 800c946d7b9c830c86290df49afbbe91db8455f5
fails tensor-shape validation: joint_proj.weight expects [2816,768], gets
[5120,768]. This is not a performance result. b12651 still has the same loader
formula. The generic flag is not sufficient evidence of Inkling-drafter
compatibility. No tensor dimensions were forced or weights modified. Restored
healthy deployed configuration immediately after the failed load.

## Measurement corrections for engine comparisons

The harness now sends exact input token IDs and requires prompt_n to equal
the submitted length (the older ik server lacks cache_n). It also reports
normalized decode throughput: (predicted_n - 1) / predicted_ms, since the
first token belongs to prefill. The ik fork reports predicted_n / predicted_ms;
raw engine timings remain in the records. The same updated harness must be
used for both sides of comparisons. No GPU benchmarks during CPU compilation.

The fork was fetched by commit and NAR hash
`1xbp9wp2s7zcak8pc844869cgpjdi50dzzcxpk6kwiq79hj5pimf`.
An initial CUDA 13.4 build failed because that toolkit removed
cudaGraphGetEdges_v2. Retry uses the repository's CUDA 12.8 package set,
matching the existing runtime family; no driver change and no source patch.

Frozen token fixtures are used for engine comparisons because the fork also
includes a newer tokenizer fix. Input SHA-256 is recorded per sample so any
accidental difference in submitted tokens is visible. Functional API checks
still exercise each engine's real chat template and tokenizer.

The original model contains only F32 (334 tensors), Q8_0 (322), IQ4_NL (24),
and IQ3_S (24). The candidate build includes all these types. No re-quantization
or vocabulary trim is involved. The source fork describes itself as an
unmaintained showcase; maintenance and compatibility are part of acceptance,
not just its advertised throughput.

The first CUDA 12.8 compile completed, but Nix correctly rejected temporary
build-directory RPATHs in the hand-written install phase. Fixed by setting
explicit store library paths, then rebuilding cleanly. The final candidate
build includes its fused-operation tests and only the quantization types
needed for this model and those tests. These are build/packaging corrections,
not benchmark results.

## First engine result and compatibility gates

On identical frozen-token fixtures, the unpatched fork achieved 127.56 tok/s
normalized decode versus 77.17 in the adjacent mainline control. Cold 4K TTFT
was 2.396s versus 3.452s. Peak observed memory fell to 13,606 MiB.
All five kernel suites passed (CPU/GPU comparisons; zero failures).
This is a promising measurement, not acceptance: the tool-call smoke test
failed because the embedded template requests `tojson(sort_keys=true)`, which
the fork's Jinja implementation did not support. A narrow recursive sorting
patch and regression test are being qualified. The original model template
is not weakened or replaced. The HTTP library also needed SO_REUSEADDR when
switching from the current server; the compatibility patch sets it in addition
to the existing SO_REUSEPORT. Candidate comparisons use loopback port 8081.

## Larger batches and final plateau

- Fixed engine, b512/ub192: ~127.6 tok/s and 2.397s cold 4K TTFT.
- b512/ub512: ~127.4 tok/s and 1.542s; 14,166 MiB observed. Accepted.
- b1024/ub512: ~127.4 tok/s and 1.438s; 14,166 MiB. Accepted.
- b1024/ub768: ~127.3 tok/s and 1.452s; 14,618 MiB. Rejected:
  more memory and no latency benefit. Did not push ub1024 past the memory cap.
- Whole CUDA graph: ~127.44 tok/s, 1.438s; neighbouring controls ~127.38
  and ~127.27. Inside noise, rejected.
- 16 graph chunks: ~127.01 tok/s, 1.440s; controls ~127.27/~127.29.
  Inside noise, rejected; retain the fork's default eight chunks.
- Suffix speculation: ~126.36 tok/s, 1.441s; controls ~127.29/~127.25.
  No gain on this fixed panel, rejected. This does not establish its value
  on large repetitive code-edit tasks, which were not measured here.

Three consecutive scheduling/speculation levers did not improve the best
configuration. Current plateau: b1024/ub512, default kernel settings, no
speculation. The source- and package-pinned final Nix build reuses exactly the
qualified server binary. Only Inkling's unit and engine closure changed.

Remaining ranked opportunities:
1. Port/qualify native DSpark support for this exact drafter and ablated target;
   nontrivial model/engine work, and acceptance may not pay for verification.
2. Profile remaining IQ3_S/Q8_0 expert and output-head kernels and port targeted
   improvements; custom CUDA work with numerical tests, beyond config tuning.
3. Different quantization or vocabulary pruning: excluded from this pass because
   they change the quality/model constraints. The author's faster demo uses a
   different quantization and trimmed vocabulary; its numbers are not ours.

Prefix caching is already enabled in normal serving. These cold measurements
intentionally disable it; existing cache hits are not presented as a new gain.

## Final deployed qualification

- Deployed the full Nix system with b1024/ub512 and the exact qualified server
  binary. No temporary unit override remains.
- Final panel: 127.38 tok/s normalized decode, 1.436s cold 4K TTFT,
  2,856 tok/s prefill. All ten fixture input hashes/counts match the mainline
  control. Output differences are retained; no bit-identical claim.
- Chat/reasoning/tool round-trip gates passed before and after a graceful
  systemd restart. Service active, zero automatic restarts; no kernel Xid logs.
- 16K retrieval passed; three near-32K retrieval runs passed all three exact
  needles with no truncation. Cold near-32K TTFT 12.111–12.539s. Peak sampled
  memory 14,232 MiB, below 14,750 MiB cap. GPU power limit remains 300 W.
- Five numerical suites and 1,439 Jinja assertions passed. Full Nix system
  built; Go harnesses pass vet. These gates do not replace a broad model-quality
  evaluation or a long-duration production soak.
