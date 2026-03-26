# PPLX Kernels

[pplx-kernels](https://github.com/perplexityai/pplx-kernels) provides
high-performance MoE dispatch/combine kernels with support for NVLink,
IBGDA, IBRC, and EFA transport layers. The following examples run the
pplx-kernels all-to-all benchmark on a Slurm cluster. You can use
rdmatop on the compute nodes to observe RDMA network flow during the
benchmarks.

## Build

The Dockerfile in this repo includes pplx-kernels. Build the container
image and convert it to an enroot squashfs for `pplx.sbatch`:

```bash
cd rdmatop && make docker
```

## Examples

```bash
# Multi-node benchmark (2 nodes, 16 GPUs)
salloc -N 2 bash examples/pplx/pplx.sbatch \
  python3 -m tests.bench_all_to_all
```
