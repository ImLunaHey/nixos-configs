# Measured ceilings (approximate, not speed promises)

Hardware: RTX 5070 Ti, 16,303 MiB visible VRAM; Ryzen 7 9700X; 32 GB RAM.
Pinned llama.cpp b12633 / CUDA 12.8, driver 595.112.07. Power limit 300 W.

`hardware/main.c` uses the pinned server's CUDA runtime and cuBLAS. Six samples,
after warmup, measured approximately 770.5 GB/s aggregate device-copy traffic
(read + write), 170.7 TFLOPS FP16 GEMM at 4096 cubed, and 185.7 TFLOPS at
8192 cubed. Copy buffers are 128 MiB each; GEMM allocations peak at 384 MiB.
The model stayed loaded but idle. No power/clock settings changed.

The GGUF has 26,070,385,152 physical parameters, 13,328,532,480 tensor bytes,
128 experts with 8 selected per token, and 24 physical blocks. Blocks 6–17
execute three times, producing 48 effective blocks. `cmd/gguf/main.go` inventories
actual tensor offsets (including at most alignment padding), applies the
loop multiplier, and charges expert tensors at 8/128. Input embedding lookup
is excluded from full-matrix traffic. Attention, output head and shared
weights remain included. This estimates 3,473,286,144 weight bytes read per
decode step and approximately 4,914,989,568 active linear parameters.

At short context, a bandwidth-only upper bound is:

    770.5e9 / 3.4733e9 = approximately 222 tokens/sec

The baseline's ~77 tokens/sec is ~35% of that optimistic bound. This does
not account for quantization unpacking, small routed GEMVs, synchronization,
attention/residual operations, or imperfect memory reuse. It is not a claim
that serving flags can reach 222 tokens/sec.

There are 8 effective full-attention blocks and 40 effective sliding-window
blocks (1024-token window). With 8 KV heads, 128 dimensions and q8_0 storage,
an approximate full K+V traffic budget is 2176 bytes per token per block.
At 4K context this adds ~160 MB/read step; at 32K, ~660 MB. Actual cache
allocation and traffic can differ with reuse and the engine's implementation.

Using half the measured 8192-cubed FP16 throughput as a practical compute
budget gives roughly 9.4K prefill tokens/sec before attention overhead, or
around 8.9K at 4K with a rough attention term. This is a loose roofline:
small MoE batches and IQ3 kernels are not dense cuBLAS FP16 GEMMs. The baseline
~1.02K tokens/sec is ~11% of that bound. Increasing batch size could improve
kernel efficiency, but the measured 512-token scratch allocation does not
fit the card. Memory capacity, not the advertised model context limit,
constrains the batch experiment.
