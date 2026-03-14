# NVSHMEM

[NVSHMEM](https://github.com/NVIDIA/nvshmem) is a one-sided
communication library for GPUs based on the OpenSHMEM standard.
Unlike NCCL which focuses on collective communication, NVSHMEM
provides efficient point-to-point (producer/consumer) transfers.
A well-known use case is
[DeepEP](https://github.com/deepseek-ai/DeepEP), a high
performance MoE dispatch/combine implementation that replaces
AlltoAll communication. The following examples use the NVSHMEM
[perftest](https://github.com/NVIDIA/nvshmem/tree/main/perftest)
suite on a Slurm cluster. You can use rdmatop on the compute
nodes to observe RDMA network flow during the benchmarks.

## Build

The Dockerfile in this repo includes NVSHMEM and its perftest
binaries. Build the container image and convert it to an
enroot squashfs for `nvshmem.sbatch`:

```bash
cd rdmatop && make docker
```

## Examples

```
# Put Bandwidth (inter-node, 1 GPU per node)
salloc -N 2 NTASKS_PER_NODE=1 \
  bash examples/nvshmem/nvshmem.sbatch \
  /opt/nvshmem/bin/perftest/device/pt-to-pt/shmem_put_bw \
  -b 8 -e 128M -f 2 -n 10000 -w 100

# AlltoAll — Device (all 8 GPUs per node)
salloc -N 2 bash examples/nvshmem/nvshmem.sbatch \
  /opt/nvshmem/bin/perftest/device/coll/alltoall_latency \
  -b 16 -e 16M -f 2 -n 10000 -s all

# AlltoAll — Host / Stream (all 8 GPUs per node)
salloc -N 2 bash examples/nvshmem/nvshmem.sbatch \
  /opt/nvshmem/bin/perftest/host/coll/alltoall_on_stream \
  -b 2M -e 128M -f 2 -n 10000 -s all
```

## Common Perftest Flags

| Flag      | Description                              |
|-----------|------------------------------------------|
| `-b`      | Min message size (K/M/G suffix)          |
| `-e`      | Max message size                         |
| `-f`      | Step factor between sizes                |
| `-n`      | Number of iterations                     |
| `-w`      | Warmup iterations                        |
| `-c`      | Number of CTAs (thread blocks)           |
| `-t`      | Threads per CTA                          |
| `-s`      | Scope (`thread`, `warp`, `block`, `all`) |
| `-d`      | Datatype (`int`, `float`, `double`, ...) |
| `--bidir` | Bidirectional test                       |
