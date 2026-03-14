#!/bin/bash
# RDMA Interface Traffic Monitoring Script

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

DEFAULT_INTERVAL=1

# Format bytes to human-readable format
format_bytes() {
  local bytes=${1:-0}
  if [ "$bytes" -lt 1024 ] 2>/dev/null; then
    echo "${bytes}B"
  elif [ "$bytes" -lt 1048576 ] 2>/dev/null; then
    echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1024}")KB"
  elif [ "$bytes" -lt 1073741824 ] 2>/dev/null; then
    echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1048576}")MB"
  else
    echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1073741824}")GB"
  fi
}

# Parse rdma statistic for a device, output: tx_bytes rx_bytes tx_pkts rx_pkts rx_drops
parse_rdma_line() {
  local line="$1"
  echo "$line" | grep -oP '(tx_bytes|rx_bytes|tx_pkts|rx_pkts|rx_drops) \K[0-9]+' | tr '\n' ' '
}

# Snapshot all RDMA devices into associative arrays
# Usage: snapshot PREFIX  (creates PREFIX_tx_bytes[dev], etc.)
snapshot_all() {
  local prefix=$1
  while IFS= read -r line; do
    [[ $line == link* ]] || continue
    local dev=$(echo "$line" | awk '{print $2}' | cut -d'/' -f1)
    read tb rb tp rp rd <<< "$(parse_rdma_line "$line")"
    eval "${prefix}_tx_bytes[$dev]=${tb:-0}"
    eval "${prefix}_rx_bytes[$dev]=${rb:-0}"
    eval "${prefix}_tx_pkts[$dev]=${tp:-0}"
    eval "${prefix}_rx_pkts[$dev]=${rp:-0}"
    eval "${prefix}_rx_drops[$dev]=${rd:-0}"
  done <<< "$(rdma statistic show 2>/dev/null)"
}

# Display diff-based statistics (snapshot -> sleep -> diff)
show_stats() {
  local interval=${1:-$DEFAULT_INTERVAL}

  declare -A prev_tx_bytes prev_rx_bytes prev_tx_pkts prev_rx_pkts prev_rx_drops
  snapshot_all prev

  sleep "$interval"

  declare -A curr_tx_bytes curr_rx_bytes curr_tx_pkts curr_rx_pkts curr_rx_drops
  snapshot_all curr

  echo -e "${BLUE}========================================${NC}"
  echo -e "${GREEN}RDMA Traffic Stats - $(date) (${interval}s interval)${NC}"
  echo -e "${BLUE}========================================${NC}"
  printf "%-15s %15s %15s %15s %15s %12s %12s\n" \
    "Interface" "TX Bytes" "RX Bytes" "TX Pkts" "RX Pkts" "Drops" "TX Gbps"
  echo "--------------------------------------------------------------------------------------------------------------"

  for dev in "${!curr_tx_bytes[@]}"; do
    dtx=$((curr_tx_bytes[$dev] - prev_tx_bytes[$dev]))
    drx=$((curr_rx_bytes[$dev] - prev_rx_bytes[$dev]))
    dtp=$((curr_tx_pkts[$dev] - prev_tx_pkts[$dev]))
    drp=$((curr_rx_pkts[$dev] - prev_rx_pkts[$dev]))
    drd=$((curr_rx_drops[$dev] - prev_rx_drops[$dev]))
    tx_gbps=$(awk "BEGIN {printf \"%.2f\", $dtx*8/$interval/1000000000}")

    tx_human=$(format_bytes $dtx)
    rx_human=$(format_bytes $drx)

    if [ "$drd" -gt 0 ] 2>/dev/null; then
      drops_color="${RED}"
    else
      drops_color="${NC}"
    fi

    printf "%-15s %15s %15s %15s %15s ${drops_color}%12s${NC} %12s\n" \
      "$dev" "$tx_human" "$rx_human" "$dtp" "$drp" "$drd" "$tx_gbps"
  done | sort
  echo ""
}

# Continuous monitoring mode
monitor_mode() {
  local interval=${1:-$DEFAULT_INTERVAL}
  while true; do
    clear
    show_stats "$interval"
    echo -e "${YELLOW}Updating every ${interval}s, press Ctrl+C to stop${NC}"
  done
}

# Detailed statistics for a single interface (diff-based)
detailed_stats() {
  local interface=$1
  local interval=${2:-$DEFAULT_INTERVAL}

  local snap1 snap2
  snap1=$(rdma statistic show 2>/dev/null | grep "^link $interface")
  sleep "$interval"
  snap2=$(rdma statistic show 2>/dev/null | grep "^link $interface")

  if [ -z "$snap2" ]; then
    echo -e "${RED}Device $interface not found${NC}"
    return 1
  fi

  echo -e "${BLUE}========================================${NC}"
  echo -e "${GREEN}$interface Detailed Stats (${interval}s interval)${NC}"
  echo -e "${BLUE}========================================${NC}"

  # Build associative arrays from both snapshots, compute diff
  # Strip "link <dev>/<port>" prefix, then parse "key value" pairs
  declare -A vals1 vals2
  local kv1 kv2
  kv1=$(echo "$snap1" | sed 's/^link [^ ]* //')
  kv2=$(echo "$snap2" | sed 's/^link [^ ]* //')
  while read -r k v; do
    [ -n "$k" ] && vals1[$k]=$v
  done <<< "$(echo "$kv1" | xargs -n2)"
  while read -r k v; do
    [ -n "$k" ] && vals2[$k]=$v
  done <<< "$(echo "$kv2" | xargs -n2)"

  printf "%-35s %20s %20s\n" "Counter" "Delta" "Rate/s"
  echo "--------------------------------------------------------------------------"
  for k in $(echo "${!vals2[@]}" | tr ' ' '\n' | sort); do
    v1=${vals1[$k]:-0}
    v2=${vals2[$k]:-0}
    delta=$((v2 - v1))
    if [[ $k == *_bytes ]]; then
      rate=$(awk "BEGIN {printf \"%.2f Gbps\", $delta*8/$interval/1000000000}")
      delta_fmt=$(format_bytes $delta)
    else
      rate=$(awk "BEGIN {printf \"%.1f\", $delta/$interval}")
      delta_fmt=$delta
    fi
    printf "%-35s %20s %20s\n" "$k" "$delta_fmt" "$rate"
  done
  echo ""
}

# Bandwidth calculation mode (kept for backward compat, now uses shared logic)
bandwidth_mode() {
  local interval=${1:-$DEFAULT_INTERVAL}

  declare -A prev_tx_bytes prev_rx_bytes prev_tx_pkts prev_rx_pkts prev_rx_drops
  snapshot_all prev

  sleep "$interval"

  declare -A curr_tx_bytes curr_rx_bytes curr_tx_pkts curr_rx_pkts curr_rx_drops
  snapshot_all curr

  echo -e "${BLUE}========================================${NC}"
  echo -e "${GREEN}Real-time Bandwidth Monitor (${interval}s sampling)${NC}"
  echo -e "${BLUE}========================================${NC}"
  echo ""
  printf "%-15s %20s %20s\n" "Interface" "TX Bandwidth" "RX Bandwidth"
  echo "--------------------------------------------------------"

  for dev in "${!curr_tx_bytes[@]}"; do
    dtx=$((curr_tx_bytes[$dev] - prev_tx_bytes[$dev]))
    drx=$((curr_rx_bytes[$dev] - prev_rx_bytes[$dev]))
    tx_rate=$(awk "BEGIN {printf \"%.2f\", $dtx*8/$interval/1000000000}")
    rx_rate=$(awk "BEGIN {printf \"%.2f\", $drx*8/$interval/1000000000}")
    printf "%-15s %17s Gbps %17s Gbps\n" "$dev" "$tx_rate" "$rx_rate"
  done | sort
  echo ""
}

# Show help
show_help() {
  echo "RDMA Interface Traffic Monitoring Tool"
  echo ""
  echo "Usage: $0 [options]"
  echo ""
  echo "All modes compute deltas over a sampling interval (counters are cumulative)."
  echo ""
  echo "Options:"
  echo "  -s, --stats            Show traffic deltas (default)"
  echo "  -m, --monitor          Continuous monitoring mode"
  echo "  -b, --bandwidth        Real-time bandwidth monitor"
  echo "  -d, --detail <iface>   Detailed per-counter deltas"
  echo "  -i, --interval <sec>   Sampling interval (default ${DEFAULT_INTERVAL}s)"
  echo "  -l, --list             List all RDMA interfaces"
  echo "  -h, --help             Show this help message"
  echo ""
  echo "Examples:"
  echo "  $0                         # Show traffic deltas (1s sample)"
  echo "  $0 -s 5                    # Show traffic deltas (5s sample)"
  echo "  $0 -m 2                    # Continuous monitor, 2s interval"
  echo "  $0 -b                      # Bandwidth only (1s sample)"
  echo "  $0 -d rdmap85s0            # All counter deltas for rdmap85s0"
  echo "  $0 -d rdmap85s0 5          # Same but 5s sample window"
  echo "  $0 -d rdmap85s0 -i 5       # Same, explicit interval flag"
}

# List all RDMA interfaces
list_interfaces() {
  echo -e "${GREEN}Available RDMA interfaces:${NC}"
  ls /sys/class/infiniband/ | grep rdmap | nl
}

# Parse arguments
DEVICE=""
MODE="stats"
INTERVAL=$DEFAULT_INTERVAL

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--stats)     MODE="stats"; shift ;;
    -m|--monitor)   MODE="monitor"; shift ;;
    -b|--bandwidth) MODE="bandwidth"; shift ;;
    -d|--detail)    MODE="detail"; DEVICE="$2"; shift 2 ;;
    -i|--interval)  INTERVAL="$2"; shift 2 ;;
    -l|--list)      list_interfaces; exit 0 ;;
    -h|--help)      show_help; exit 0 ;;
    [0-9]*)         INTERVAL="$1"; shift ;;
    *)              echo "Unknown option: $1"; show_help; exit 1 ;;
  esac
done

if [ "$MODE" = "detail" ] && [ -z "$DEVICE" ]; then
  echo "Error: Please specify interface name"
  echo "Use $0 -l to list all interfaces"
  exit 1
fi

case "$MODE" in
  stats)     show_stats "$INTERVAL" ;;
  monitor)   monitor_mode "$INTERVAL" ;;
  bandwidth) bandwidth_mode "$INTERVAL" ;;
  detail)    detailed_stats "$DEVICE" "$INTERVAL" ;;
esac
