# PPLX Kernels

[pplx-kernels](https://github.com/ppl-ai/pplx-kernels) provides
high-performance MoE dispatch/combine kernels with support for NVLink,
IBGDA, IBRC, and EFA transport layers. Although Perplexity AI has deprecated
this older kernel in favor of [pplx-garden](https://github.com/perplexityai/pplx-garden),
we still use it here to demonstrate monitoring RDMA traffic and NVSHMEM
throughput with rdmatop. This example runs the pplx-kernels all-to-all
benchmark on a Slurm cluster with a dedicated Docker image layered on top
of the base `efa` image (adding vLLM, DeepGEMM, and pplx-kernels).
Use rdmatop on the compute nodes to observe RDMA network flow during
the benchmarks.

## Build

First build the base image, then build the pplx image on top of it.
The pplx image adds vLLM (< v0.16), DeepGEMM, and pplx-kernels:

```bash
cd rdmatop
make docker        # build the base efa image
make pplx-docker   # build the pplx image (uses efa:latest as base)
```

## Examples

```bash
# Multi-node benchmark (2 nodes, 16 GPUs)
salloc -N 2 bash examples/pplx/pplx.sbatch \
  python3 -m tests.bench_all_to_all
```
