# 128K speed follow-up

Targets: improve 128K cold prefill and decode, preserve one 131072-token slot,
exact existing model weights/vocabulary/three loops, q4 KV, 14750 MiB cap and
300W. No extra quantization changes or speculative drafter substitutions.
Production 32K/q8 restored at queue exit. Only one GPU job at a time.

Prior rejected larger batches: ub256 and ub512 exceeded cap with full context.
New levers: intermediate ub192/224 (not previously tried), checkpoint overhead,
then profile q4 attention conversion versus direct quantized vector kernels.
Do not re-run rejected graph/suffix speculation sweeps without new evidence.

Configuration sweep (four interleaved ub128 controls):
- Controls: short decode 111.48–111.89 tok/s, cold4K 2.388–2.398s;
  near-full TTFT ~96.7–96.9s, ~29.9 tok/s, peak14554 MiB.
- ub192: short111.82 tok/s, cold4K2.103s, full88.134s/30.03 tok/s,
  peak14654 MiB. Beats both controls, no decode regression.
- Disable context checkpoints: short111.53 tok/s, cold4K2.311s,
  full94.780s/29.91 tok/s, same14554 MiB. Does not free GPU memory;
  reject removal of useful reuse behaviour for this small cold-only gain.
- ub224: short111.59 tok/s, cold4K1.983s, full87.346s/30.00 tok/s,
  peak14704 MiB. Full prefill barely beats192, but short prefill is >5% better.
  Keep as candidate best under the unchanged14750 cap; repeat qualification.

Code inspection found q4 single-token full attention and relative-bias
attention use the MMA path. Candidate patch gates dispatch to the existing
q4 vector kernel behind INKLING_Q4_VEC, preserving the baseline path for
controlled comparisons. No new quantization, model, context or power change.
Expanded CUDA numerical tests include full attention at4K/32K/128K and
relative-bias decode/prefill. Kernel compile waits for the GPU queue lock.

Direct-q4 candidate numerical qualification: all22 CUDA attention cases pass
with INKLING_Q4_VEC=0 and =1, including added full-attention q4 cases at4K,
32K and128K. All1439 Jinja assertions pass.
Initial full-context A/B atub224: off30.001 versus on60.103 tok/s;
TTFT87.358 versus87.417s. Both recover all three needles with identical answer
hashes and peak14704 MiB. Repetition and half-context/functional gates pending.

## Accepted result

| Metric | Initial 128K profile | Tuned candidate | Ceiling / method |
| --- | ---: | ---: | --- |
| Short-context decode | 111.35 tok/s | 115.09 tok/s | ~222 tok/s optimistic bandwidth; six prompts per panel, two candidate panels |
| Cold 4K TTFT | 2.397s | 1.984s | Three cold prompts per panel |
| Near-full 128K TTFT | 96.796s | 87.380s | Two candidate runs, 130816 exact input tokens |
| Near-full decode | 29.87 tok/s | 60.12 tok/s | ~163 tok/s optimistic weight+KV bound; two 28-token retrieval answers, normalized first-token accounting |
| Observed peak VRAM | 14554 MiB | 14704 MiB | 14750 MiB watchdog; 16303 MiB hardware |

The kernel-only controls at the same ub224 reproduce 30.001/30.011 tok/s,
versus 60.103/60.146 with direct-q4 enabled. Prefill remains unchanged within
noise. The batch change supplies the prefill gain; direct-q4 dispatch supplies
the decode gain. Numerical cases pass against the dense reference at4K/32K/
128K. Near-full retrieval answers are byte-identical across both paths.

**Not a bit-exact/lossless claim:** greedy short-prompt outputs differ on five
of six prompts. The vector kernel uses different numerical execution; this
can alter token choices. Model weights, q4 KV, vocabulary and loops are fixed.
Numerical checks and chat/reasoning/tool gates passed, but they do not establish
broad accuracy equivalence. No degeneration was observed in the saved panel.
The full-context decode figure comes from short retrieval answers, not a broad
long-generation benchmark. Single-slot only; no multi-user claim.

The 65536-token (half-context) needle also passed, TTFT38.070s, decode77.37
 tok/s. The near-full candidate was repeated twice. Production32K/q8 was
restored automatically after the queue and is not changed by this PR.

Remaining work is deeper kernel profiling/tuning: improve q4 attention's
repeated KV reads across grouped query heads, and reduce prefill's whole-cache
conversion/scratch overhead so larger physical batches fit. Native DSpark
still needs a compatible loader; the previous published drafter shape failure
is not bypassed. No claim that this is the maximum possible speed.
