# 128K context qualification

The local-ai-registry rejects new GPU recipes with less than 131072 total KV
capacity on GPUs over 8 GB. The user requested testing one 128K slot after
being informed of this constraint. Production remains 32K/q8 until qualified.

1. Existing engine, 131072 context, q8_0 K/V, batch1024/ub512: loaded, but
   startup GPU memory was 15662/16303 MiB. Aborted before requests because
   this exceeds the existing 14750 MiB memory cap; restored 32K automatically.
2. Same engine with q4_0 K/V: startup failed because the dev build includes
   only F16/Q8_0 KV kernels. Recorded startup error; restored 32K automatically.
3. Rebuild the same pinned engine with Q4_0 added to its KV kernel allowlist.
   Test near-full retrieval, chat/reasoning/tool checks and short-panel speed.
   Keep the memory cap. Reduced KV precision needs its own qualification;
   retained model weights alone do not prove equivalent quality.

- Q4-capable build: all 18 CUDA relative-bias attention cases passed, including
  three added q4 cases (single-token decode and two prefill shapes). The CPU
  q4 cases returned NaNs (33 total passed, 3 failed across both backends), so
  this candidate is GPU-only; do not claim CPU/offload compatibility.
- q4/b1024/ub512 loaded at 14644 MiB. Its near-128K request was cancelled by
  the watchdog path before a completion; restored 32K. No passing evidence.
- Retry q4/b1024/ub256: startup 14234 MiB. Testing full-context retrieval.
- Improved the Go harness to persist the memory peak and cancellation reason
  when a request fails before headers, rather than leaving an empty JSONL.

## Qualified GPU-only candidate

- Batch256 was cancelled late in near-full prefill; retained the original
  memory cap and reduced physical batch again to 128.
- 131072 context / one slot / q4_0 K+V / b1024 / ub128 passed retrieval of
  all three codes at 10%, 50%, 90% of a 130816-token prompt, without truncation.
  TTFT 96.796s, decode 29.87 tok/s at full context, sampled peak 14554 MiB.
- Chat, reasoning and tool round-trip checks passed. Jinja: 1439 assertions.
  CUDA attention: 18 cases passed, including the three q4 cases.
- Short-context panel median: 111.35 tok/s decode, 2.397s cold 4K TTFT.
  These differ from both the full-context rate and the registry workload.
- Restored production 32768/q8 automatically after testing. This change adds
  compiled q4 support; it does not change Tower's serving defaults.
- A 128K recipe must require GPU-only attention. The CPU q4 path failed its
  numerical checks in this build. The existing q8 CPU/CUDA cases still pass.
  No broad q4-versus-q8 accuracy equivalence is claimed.

## Upstream registry acceptance

The unmodified lab.py try gates at registry commit
`e10a785174415c27700416cf7312304077dc7627` passed all six gates on this exact
128K/q4/b1024/ub128 profile: load, chat, reasoning, tools, context, speed.
Measured 103.4 tok/s decode and 986 prompt tok/s using the registry workload
and accounting. Its context gate processed 91890 prompt tokens; the separate
130816-token test above covers the nearly full context. The raw lab record
is `registry-run.json` and is bound by the generated recipe proof hash.

Submitted as https://github.com/sybil-solutions/local-ai-registry/pull/522.
The launcher pins Nix source commit 3d4450eb893ead81311a3bce2d809277a1932b66;
its expression resolves to the tested server store path. Upstream `make`
and `make check` pass (443 recipes and matching JS/Python SDKs). No policy
exemptions or hand-written recipes were introduced.

After the run, the temporary override was removed and the existing 32K/q8
production service restarted healthy. No automatic switch to 128K is made.
