#!/bin/bash

set -exo pipefail

DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
SQSH="${SQSH:-${DIR}/../../efa+latest.sqsh}"
NTASKS_PER_NODE="${NTASKS_PER_NODE:-8}"

cmd="$(cat <<EOF
export LD_LIBRARY_PATH=/opt/nvshmem/lib:/opt/amazon/ofi-nccl/lib:/opt/nccl/build/lib:/opt/amazon/efa/lib:\$LD_LIBRARY_PATH
export FI_PROVIDER=efa
export FI_EFA_USE_DEVICE_RDMA=1
export FI_EFA_FORK_SAFE=1
export FI_EFA_ENABLE_SHM_TRANSFER=0
export NVSHMEMTEST_USE_MPI_LAUNCHER=1
export NVSHMEM_REMOTE_TRANSPORT=libfabric
export NVSHMEM_LIBFABRIC_PROVIDER=efa
export NVSHMEM_DISABLE_CUDA_VMM=1
export NVIDIA_VISIBLE_DEVICES=all
export CUDA_VISIBLE_DEVICES=\$SLURM_LOCALID
$@
EOF
)"

srun --container-image "${SQSH}" \
  --container-name nvshmem \
  --mpi=pmix \
  --ntasks-per-node="${NTASKS_PER_NODE}" \
  bash -c "${cmd}"
