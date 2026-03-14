# rdmatop

A real-time TUI monitor for monitoring RDMA network interfaces — `htop`, but for RDMA traffic.

<p align="center">
  <img src="images/rdmatop.gif" alt="rdmatop" width="800">
</p>

Monitors per-device throughput (Gbps, packets/s, drops), RDMA read/write counters,
retransmits, health events, and shows which processes are using each RDMA device —
all via RDMA netlink, the same interface used by [rdma statistic](https://github.com/iproute2/iproute2/blob/main/rdma/stat.c).

## Build

```bash
make         # cargo build
make install # cargo install
make fmt     # cargo fmt
make clean   # cargo clean

# run rdmatop to monitor RDMA status
rdmatop
```

## Examples

Use `rdmatop` to monitor RDMA traffic while running GPU
communication benchmarks:

- [NCCL](examples/nccl/) — collective communication
- [NIXL](examples/nixl/) — point-to-point KV cache transfer
- [NVSHMEM](examples/nvshmem/) — one-sided GPU communication
- [RDMA Statistics](examples/rdma/) — shell-based RDMA stats

## How It Works

1. **Device enumeration** — `RDMA_NLDEV_CMD_GET` via netlink to discover all RDMA devices
2. **HW counters** — `RDMA_NLDEV_CMD_STAT_GET` per device/port, same as `rdma statistic show`
3. **Process detection** — `RDMA_NLDEV_CMD_RES_QP_GET` to map QPs → PIDs, enriched with `/proc` data
4. **Throughput** — Two snapshots per interval, delta / elapsed for rates

## License

Apache-2.0
