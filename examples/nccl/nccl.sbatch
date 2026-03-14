#!/bin/bash
# Launch command inside enroot container via srun + pyxis
# Usage: salloc -N 2 ./run.enroot <command...>

set -exo pipefail

DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
SQSH="${SQSH:-${DIR}/../../efa+latest.sqsh}"

cmd="$(cat <<EOF
export LD_LIBRARY_PATH=/opt/amazon/ofi-nccl/lib:/opt/nccl/build/lib:/opt/amazon/efa/lib:\$LD_LIBRARY_PATH
export LD_PRELOAD=/opt/nccl/build/lib/libnccl.so.2
export FI_PROVIDER=efa
export FI_EFA_USE_DEVICE_RDMA=1
export FI_EFA_FORK_SAFE=1
export NCCL_NET_PLUGIN=/opt/amazon/ofi-nccl/lib/libnccl-net-ofi.so
export NCCL_TUNER_PLUGIN=/opt/amazon/ofi-nccl/lib/libnccl-tuner-ofi.so
export NCCL_DEBUG=WARN
export NCCL_BUFFSIZE=8388608
export NCCL_P2P_NET_CHUNKSIZE=524288
export OMP_NUM_THREADS=1
$@
EOF
)"

srun --container-image "${SQSH}" \
  --container-name nccl \
  --mpi=pmix \
  --ntasks-per-node=8 \
  bash -c "${cmd}"

