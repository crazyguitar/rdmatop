//! Network interface stats via rtnetlink (NETLINK_ROUTE), same as `ip -s link show`.

use crate::netlink::*;
use crate::rdma::{NLM_F_DUMP, NLM_F_REQUEST};
use std::io;

const NETLINK_ROUTE: i32 = 0;
const RTM_GETLINK: u16 = 18;
const IFLA_STATS64: u16 = 23;
const IFLA_IFNAME: u16 = 3;
const IFINFOMSG_LEN: usize = 16; // sizeof(struct ifinfomsg)

/// Snapshot of per-interface byte counters.
#[derive(Clone, Debug)]
pub struct IfStats {
    pub name: String,
    pub rx_bytes: u64,
    pub tx_bytes: u64,
}

/// Aggregated network throughput rates.
#[derive(Clone, Debug, Default)]
pub struct NetRate {
    pub rx_bytes_per_sec: f64,
    pub tx_bytes_per_sec: f64,
}

/// Parse rx_bytes and tx_bytes from IFLA_STATS64 (struct rtnl_link_stats64).
fn parse_link_stats64(data: &[u8]) -> (u64, u64) {
    if data.len() < 16 {
        return (0, 0);
    }
    let rx = u64::from_ne_bytes(data[0..8].try_into().unwrap());
    let tx = u64::from_ne_bytes(data[8..16].try_into().unwrap());
    (rx, tx)
}

/// Parse a single RTM_GETLINK response into IfStats.
fn parse_ifstats(nlmsg: &NlMsg) -> Option<IfStats> {
    if nlmsg.payload.len() < IFINFOMSG_LEN {
        return None;
    }
    let mut name = String::new();
    let mut rx_bytes = 0u64;
    let mut tx_bytes = 0u64;
    for nla in NlaIter(&nlmsg.payload[IFINFOMSG_LEN..]) {
        match nla.attr_type {
            IFLA_IFNAME => name = nla.str().to_string(),
            IFLA_STATS64 => (rx_bytes, tx_bytes) = parse_link_stats64(nla.data),
            _ => {}
        }
    }
    if name.is_empty() || name == "lo" {
        return None;
    }
    Some(IfStats {
        name,
        rx_bytes,
        tx_bytes,
    })
}

/// Read stats for all network interfaces via RTM_GETLINK.
pub fn read_all_ifstats() -> io::Result<Vec<IfStats>> {
    let sock = NlSocket::open(NETLINK_ROUTE)?;
    let msg = NlMsgBuilder::new(RTM_GETLINK, NLM_F_REQUEST | NLM_F_DUMP, 1)
        .put_raw(&[0u8; IFINFOMSG_LEN])
        .build();
    collect_responses(&sock, msg, parse_ifstats)
}

/// Compute aggregate net throughput from two snapshots.
pub fn compute_net_rate(prev: &[IfStats], curr: &[IfStats], elapsed: f64) -> NetRate {
    let mut rx = 0u64;
    let mut tx = 0u64;
    for c in curr {
        if let Some(p) = prev.iter().find(|p| p.name == c.name) {
            rx += c.rx_bytes.saturating_sub(p.rx_bytes);
            tx += c.tx_bytes.saturating_sub(p.tx_bytes);
        }
    }
    NetRate {
        rx_bytes_per_sec: rx as f64 / elapsed,
        tx_bytes_per_sec: tx as f64 / elapsed,
    }
}
