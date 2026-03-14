# NIXL

[NIXL](https://github.com/ai-dynamo/nixl) is a library for
accelerating point-to-point communication for inference, such
as KV cache transfer for LLM prefill/decode disaggregation
serving. The following examples use
[nixlbench](https://github.com/ai-dynamo/nixl/tree/main/benchmark/nixlbench)
to evaluate P2P transfer performance on Slurm. You can use
`rdmatop` to observe RDMA network flow during the benchmark.

## Build

The Dockerfile in this repo includes nixlbench, UCX, and
etcd. Build the container image and convert it to a Docker
tarball for `nixl.sbatch`:

```bash
cd rdmatop && make docker
```

## Examples

```
# Multi-GPU VRAM-to-VRAM (all 8 GPUs per node)
salloc -N 2 bash examples/nixl/nixl.sbatch \
  --backend LIBFABRIC \
  --initiator_seg_type VRAM \
  --target_seg_type VRAM \
  --mode MG \
  --num_initiator_dev 8 \
  --num_target_dev 8 \
  --num_iter 10000 \
  --max_block_size 1073741824 \
  --warmup_iter 128

# Single GPU (1 GPU per node, default)
salloc -N 2 bash examples/nixl/nixl.sbatch \
  --backend LIBFABRIC \
  --initiator_seg_type VRAM \
  --target_seg_type VRAM \
  --num_iter 10000 \
  --warmup_iter 128
```

## Common Flags

| Flag                   | Description                     |
|------------------------|---------------------------------|
| `--backend`            | `LIBFABRIC`, `UCX`              |
| `--initiator_seg_type` | `VRAM`, `DRAM`                  |
| `--target_seg_type`    | `VRAM`, `DRAM`                  |
| `--mode`               | `SG` (single GPU), `MG` (multi) |
| `--num_initiator_dev`  | GPUs on sending side            |
| `--num_target_dev`     | GPUs on receiving side          |
| `--num_iter`           | Number of iterations            |
| `--warmup_iter`        | Warmup iterations               |
| `--start_block_size`   | Starting block size             |
| `--max_block_size`     | Maximum block size (bytes)      |
| `--total_buffer_size`  | Total buffer per process        |
