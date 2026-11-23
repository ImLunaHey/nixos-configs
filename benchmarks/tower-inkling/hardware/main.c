// Host-only CUDA microbenchmarks. Load the pinned server's CUDA libraries;
// no kernel compiler, driver changes, or power-profile changes are needed.
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#define CHECK(x)                                                               \
  do {                                                                         \
    int e = (x);                                                               \
    if (e) {                                                                   \
      fprintf(stderr, "CUDA/BLAS error %d at line %d\n", e, __LINE__);         \
      exit(1);                                                                 \
    }                                                                          \
  } while (0)
#define LOAD(lib, name)                                                        \
  *(void **)(&name) = dlsym(lib, #name);                                       \
  if (!name) {                                                                 \
    fprintf(stderr, "missing %s\n", #name);                                    \
    exit(1);                                                                   \
  }
int main(void) {
  void *rt = dlopen("libcudart.so.12", RTLD_NOW | RTLD_GLOBAL),
       *bl = dlopen("libcublas.so.12", RTLD_NOW | RTLD_GLOBAL);
  if (!rt || !bl) {
    fprintf(stderr, "%s\n", dlerror());
    return 1;
  }
  int (*cudaMalloc)(void **, size_t), (*cudaFree)(void *),
      (*cudaMemcpy)(void *, const void *, size_t, int),
      (*cudaDeviceSynchronize)(void), (*cudaEventCreate)(void **),
      (*cudaEventRecord)(void *, void *), (*cudaEventSynchronize)(void *),
      (*cudaEventElapsedTime)(float *, void *, void *),
      (*cudaEventDestroy)(void *);
  int (*cublasCreate_v2)(void **), (*cublasDestroy_v2)(void *),
      (*cublasHgemm)(void *, int, int, int, int, int, const uint16_t *,
                     const uint16_t *, int, const uint16_t *, int,
                     const uint16_t *, uint16_t *, int);
  LOAD(rt, cudaMalloc);
  LOAD(rt, cudaFree);
  LOAD(rt, cudaMemcpy);
  LOAD(rt, cudaDeviceSynchronize);
  LOAD(rt, cudaEventCreate);
  LOAD(rt, cudaEventRecord);
  LOAD(rt, cudaEventSynchronize);
  LOAD(rt, cudaEventElapsedTime);
  LOAD(rt, cudaEventDestroy);
  LOAD(bl, cublasCreate_v2);
  LOAD(bl, cublasDestroy_v2);
  LOAD(bl, cublasHgemm);
  void *start, *end, *a, *b, *c, *handle;
  CHECK(cudaEventCreate(&start));
  CHECK(cudaEventCreate(&end));
  size_t bytes = 128UL << 20;
  CHECK(cudaMalloc(&a, bytes));
  CHECK(cudaMalloc(&b, bytes));
  for (int i = 0; i < 8; i++)
    CHECK(cudaMemcpy(b, a, bytes, 3));
  for (int sample = 0; sample < 6; sample++) {
    CHECK(cudaEventRecord(start, 0));
    for (int i = 0; i < 100; i++)
      CHECK(cudaMemcpy(b, a, bytes, 3));
    CHECK(cudaEventRecord(end, 0));
    CHECK(cudaEventSynchronize(end));
    float ms;
    CHECK(cudaEventElapsedTime(&ms, start, end));
    printf("{\"kind\":\"device_copy\",\"sample\":%d,\"read_plus_write_GB_s\":%."
           "3f}\n",
           sample, 2.0 * bytes * 100 / (ms * 1e6));
  }
  CHECK(cudaFree(a));
  CHECK(cudaFree(b));
  CHECK(cublasCreate_v2(&handle));
  for (int n = 4096; n <= 8192; n *= 2) {
    size_t sz = (size_t)n * n * 2;
    uint16_t *host = malloc(sz);
    for (size_t i = 0; i < sz / 2; i++)
      host[i] = 0x3c00;
    CHECK(cudaMalloc(&a, sz));
    CHECK(cudaMalloc(&b, sz));
    CHECK(cudaMalloc(&c, sz));
    CHECK(cudaMemcpy(a, host, sz, 1));
    CHECK(cudaMemcpy(b, host, sz, 1));
    free(host);
    uint16_t one = 0x3c00, zero = 0;
    for (int i = 0; i < 8; i++)
      CHECK(cublasHgemm(handle, 0, 0, n, n, n, &one, a, n, b, n, &zero, c, n));
    for (int sample = 0; sample < 6; sample++) {
      CHECK(cudaEventRecord(start, 0));
      for (int i = 0; i < 10; i++)
        CHECK(
            cublasHgemm(handle, 0, 0, n, n, n, &one, a, n, b, n, &zero, c, n));
      CHECK(cudaEventRecord(end, 0));
      CHECK(cudaEventSynchronize(end));
      float ms;
      CHECK(cudaEventElapsedTime(&ms, start, end));
      printf(
          "{\"kind\":\"fp16_gemm\",\"n\":%d,\"sample\":%d,\"TFLOPS\":%.3f}\n",
          n, sample, 2.0 * n * n * n * 10 / (ms * 1e9));
    }
    CHECK(cudaFree(a));
    CHECK(cudaFree(b));
    CHECK(cudaFree(c));
  }
  CHECK(cublasDestroy_v2(handle));
  CHECK(cudaEventDestroy(start));
  CHECK(cudaEventDestroy(end));
  return 0;
}
