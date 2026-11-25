# 128K tuning bounds

Use the previously measured 770.5 GB/s bandwidth and 185.7 TFLOPS dense FP16
GEMM, not card advertising. Weight traffic is about 3.473 GB/decode token.
Q4 K+V is 1152 bytes/token/layer: eight full-attention blocks at 131072 plus
40 sliding blocks at 1024 imply roughly 1.255 GB KV reads/decode token.
An optimistic bandwidth ceiling is 770.5 / (3.473 + 1.255) = 163 tok/s.
The measured 29.87 tok/s at near-full context is only 18% of this loose bound.
Quantization, kernels, conversions and repeated cache traffic lower it.

Source inspection: q4 single-token attention currently falls through to MMA,
which converts quantized K/V to f16. A full K+V f16 copy at 128K / 8 KV heads /
128 head dimension is 512 MiB. This plausibly explains the approximately
520 MiB growth between startup and full-context serving; it must be tested,
not assumed. The existing vector kernel can consume q4 directly and is a
candidate after configuration levers, with numerical tests required.

Prefill: linear FLOPs remain ~9.83 GFLOP/token. At full context, attention
adds roughly 4*8*3072*131072 = 12.88 GFLOP/token (plus SWA). Half measured
GEMM throughput / ~22.7 GFLOP is a loose ~4.1K tok/s ceiling. The measured
1.35K near-full prefill is ~33%. Quantized sparse GEMMs and attention are not
dense cuBLAS; this is prioritization, not a speed guarantee.
