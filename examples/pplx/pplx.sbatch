#!/bin/bash

set -exo pipefail

DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
SQSH="${SQSH:-${DIR}/../../pplx+latest.sqsh}"
NTASKS_PER_NODE="${NTASKS_PER_NODE:-1}"
MASTER_ADDR="$(scontrol show hostnames $SLURM_JOB_NODELIST | head -n 1)"
MASTER_ADDR="$(getent hosts $MASTER_ADDR | awk '{print $1}')"

cmd="$(cat <<EOF
export LD_LIBRARY_PATH=/opt/nvshmem/lib:/opt/nccl/build/lib:/opt/amazon/efa/lib:\$LD_LIBRARY_PATH
export LD_PRELOAD=/opt/nvshmem/lib/libnvshmem_host.so
export FI_PROVIDER=efa
export FI_EFA_USE_DEVICE_RDMA=1
export FI_EFA_FORK_SAFE=1
export NVSHMEM_REMOTE_TRANSPORT=libfabric
export NVSHMEM_LIBFABRIC_PROVIDER=efa
export NVSHMEM_DISABLE_CUDA_VMM=1
export NVSHMEM_SYMMETRIC_SIZE=4294967296
export NVSHMEM_BOOTSTRAP_PLUGIN=/opt/nvshmem/lib/nvshmem_bootstrap_uid.so
export NVSHMEM_DEBUG=WARN
export NVIDIA_VISIBLE_DEVICES=all

export WORLD_SIZE=\$((\$SLURM_NNODES * 8))
export WORLD_LOCAL_SIZE=8
export NODE_RANK=\$SLURM_NODEID
export MASTER_ADDR=${MASTER_ADDR}
export MASTER_PORT=29500

cd /opt/pplx-kernels

NUM_REPEAT=\${NUM_REPEAT:-256}
sed -i "s/num_repeat = 20/num_repeat = \$NUM_REPEAT/" tests/bench_all_to_all.py

$@
EOF
)"

srun --container-image "${SQSH}" \
  --container-name pplx \
  --ntasks-per-node="${NTASKS_PER_NODE}" \
  bash -c "${cmd}"
