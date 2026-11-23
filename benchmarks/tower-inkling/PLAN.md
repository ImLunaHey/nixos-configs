# Tower / Inkling experiments — 2026-11-23

Task: improve TTFT/prefill and decode without changing the model, quantization,
32,768-token context, quality, or stability. One sequence; no concurrency increase.
GPU memory cap: 14,750 MiB total residency, leaving at least 1,553 MiB free.
Power limit remains 300 W; no clock, power-profile or reasoning-default changes.
No prior tuning ledger was found in the configuration; baseline is the deployed unit.

Method: the inference-optimisation skill's control/candidate/control method;
6 deterministic code/prose decode prompts, 192-token maximum, temperature 0,
explicit reasoning effort 0 in the fixed native prompt template. Warmup excluded.
Three cold 4,096-token prefill samples, with exact server tokenization and cache_n=0.
SSE measures local-client TTFT; server timings count real tokens. Outputs and hashes
are retained. A once-per-second VRAM sampler cancels the request at the memory cap.
All experiments are serialized; the live server is drained before graceful restart.
The headless dashboard remains running throughout; no other compute GPU job exists.

## Baseline A

Median decode ~77.16 tok/s; cold 4K prefill ~1020.4 tok/s; TTFT ~4.015 s.
Peak observed GPU residency 14,158 MiB. CUDA graphs are already reused.

## Physical batch 512 — rejected

Only ubatch changed from 128 to 512. Startup could not allocate a 3,356.22 MiB
compute buffer (CUDA out of memory); no performance run accepted. Baseline restored.
This is an allocation failure, not a measured speed regression. Keep 32K context.

## Physical batch 192

Accepted after three candidate panels and two baseline panels: cold 4K TTFT
4.015s → 3.462s, prompt processing 1021 → 1184 tok/s, decode ~77 tok/s.
Peak observed memory 14,556 MiB. Both 16K and near-32K retrieval checks pass.
Short greedy outputs match; 4K summary wording differs (see README limitations).

## GPU-side sampling — rejected

At physical batch 192: ~77.73 tok/s versus adjacent ~76.97 controls, under 1%.
Cold 4K TTFT slightly worsens (~3.475s). Insufficient benefit to retain the flag.

## Final qualification

Built and switched the complete Tower Nix configuration, with only the Inkling
unit changed and no runtime override left. Final deployed panel: 3.464s cold
4K TTFT, 1183 prefill tok/s, 77.06 decode tok/s; 14,556 MiB observed peak.
Chat, reasoning, structured tool round-trip and near-32K retrieval pass.
The PR records the change; it is not automatically merged.
