# RDMA Statistics

This project's implementation is inspired by
[iproute2/rdma/stat.c](https://github.com/iproute2/iproute2/blob/main/rdma/stat.c),
the entrypoint of the `rdma statistic` command. The original
uses Linux [netlink](https://man7.org/linux/man-pages/man7/netlink.7.html)
to query RDMA state. This project uses the same netlink
interface to query RDMA information and display it in a
`top`-like TUI.

A shell script `examples/rdma/rdma.sh` is also provided for
quick RDMA stats using `rdma statistic` without the TUI.

## Shell Script

```
./examples/rdma/rdma.sh
========================================
RDMA Traffic Stats (1s interval)
========================================
Interface       TX Bytes   RX Bytes    TX Pkts ...
--------------------------------------------------
rdmap113s0       11.00GB    1.40MB   11761778 ...
rdmap114s0       11.00GB    1.40MB   11765604 ...
rdmap115s0       11.00GB    1.40MB   11784208 ...
rdmap116s0       11.00GB    1.40MB   11797348 ...
```

## Related Links

- [iproute2 rdma](https://github.com/iproute2/iproute2/tree/main/rdma)
  — upstream `rdma` CLI tool
- [rdma-core](https://github.com/linux-rdma/rdma-core)
  — userspace RDMA libraries and drivers
