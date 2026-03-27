# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Modifications copyright (c) 2025 Chang-Ning Tsai

# ref: https://github.com/aws-samples/awsome-distributed-training/blob/main/micro-benchmarks/nccl-tests
ARG CUDA_VERSION=12.8.1
FROM nvcr.io/nvidia/cuda:${CUDA_VERSION}-devel-ubuntu24.04

ARG GDRCOPY_VERSION=v2.5.1
ARG EFA_INSTALLER_VERSION=1.47.0
ARG UCX_VERSION=v1.20.0
ARG NIXL_VERSION=v1.0.0
ARG CUDA_ARCH=90
ARG NCCL_VERSION=v2.29.3-1
ARG NCCL_TESTS_VERSION=v2.17.9
ARG NVSHMEM_VERSION=v3.6.5-0

RUN apt-get update -y && apt-get upgrade -y
RUN apt-get remove -y --allow-change-held-packages \
    ibverbs-utils \
    libibverbs-dev \
    libibverbs1 \
    libmlx5-1 \
    libnccl2 \
    libnccl-dev

RUN rm -rf /opt/hpcx \
    && rm -rf /usr/local/mpi \
    && rm -f /etc/ld.so.conf.d/hpcx.conf \
    && ldconfig

ENV OPAL_PREFIX=

RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --allow-unauthenticated \
    apt-utils \
    autoconf \
    automake \
    build-essential \
    check \
    cmake \
    ninja-build \
    meson \
    curl \
    debhelper \
    devscripts \
    git \
    gcc \
    gdb \
    kmod \
    python3-dev \
    python3-venv \
    libsubunit-dev \
    libtool \
    openssh-client \
    openssh-server \
    libmnl-dev \
    libhwloc-dev \
    pybind11-dev \
    pkg-config \
    python3-pip \
    etcd-server \
    vim

RUN apt-get purge -y cuda-compat-*

RUN mkdir -p /var/run/sshd
RUN sed -i 's/[ #]\(.*StrictHostKeyChecking \).*/ \1no/g' /etc/ssh/ssh_config && \
    echo "    UserKnownHostsFile /dev/null" >> /etc/ssh/ssh_config && \
    sed -i 's/#\(StrictModes \).*/\1no/g' /etc/ssh/sshd_config

# Set paths for both aarch64 and x86_64
ENV LD_LIBRARY_PATH=/usr/local/cuda/extras/CUPTI/lib64:/opt/amazon/openmpi/lib:/opt/nccl/build/lib:/opt/amazon/efa/lib:/opt/amazon/ofi-nccl/lib/aarch64-linux-gnu:/opt/amazon/ofi-nccl/lib/x86_64-linux-gnu:/usr/local/lib:$LD_LIBRARY_PATH
ENV PATH=/opt/amazon/openmpi/bin/:/opt/amazon/efa/bin:/usr/bin:/usr/local/bin:$PATH

RUN pip3 install --break-system-packages awscli nvidia-ml-py Cython

#################################################
## Install NVIDIA GDRCopy
##
## NOTE: if `nccl-tests` or `/opt/gdrcopy/bin/sanity -v` crashes with incompatible version, ensure
## that the cuda-compat-xx-x package is the latest.
RUN git clone -b ${GDRCOPY_VERSION} https://github.com/NVIDIA/gdrcopy.git /tmp/gdrcopy \
    && cd /tmp/gdrcopy \
    && make prefix=/opt/gdrcopy install

ENV LD_LIBRARY_PATH=/opt/gdrcopy/lib:$LD_LIBRARY_PATH
ENV LIBRARY_PATH=/opt/gdrcopy/lib:$LIBRARY_PATH
ENV PATH=/opt/gdrcopy/bin:$PATH
ENV CPATH=/opt/gdrcopy/include

#################################################
## Install EFA installer
RUN cd $HOME \
    && curl -O https://efa-installer.amazonaws.com/aws-efa-installer-${EFA_INSTALLER_VERSION}.tar.gz \
    && tar -xf $HOME/aws-efa-installer-${EFA_INSTALLER_VERSION}.tar.gz \
    && cd aws-efa-installer \
    && ./efa_installer.sh -y -g -d --skip-kmod --skip-limit-conf --no-verify \
    && rm -rf $HOME/aws-efa-installer

###################################################
## Install UCX (verbs + rdmacm + dm + efa)
ENV UCX_PREFIX=/usr/local/ucx

RUN git clone --depth 1 --branch ${UCX_VERSION} https://github.com/openucx/ucx.git /tmp/ucx \
    && cd /tmp/ucx && ./autogen.sh \
    && ./contrib/configure-release-mt \
       --prefix=${UCX_PREFIX} \
       --enable-shared --disable-static \
       --enable-optimizations --enable-cma --enable-mt \
       --enable-devel-headers \
       --with-cuda=/usr/local/cuda \
       --with-gdrcopy=/opt/gdrcopy \
       --with-verbs --with-rdmacm --with-dm --with-efa \
    && make -j$(nproc) && make install \
    && echo "${UCX_PREFIX}/lib" > /etc/ld.so.conf.d/ucx.conf \
    && echo "${UCX_PREFIX}/lib/ucx" >> /etc/ld.so.conf.d/ucx.conf \
    && ldconfig && rm -rf /tmp/ucx

ENV PATH="${UCX_PREFIX}/bin:${PATH}"
ENV LD_LIBRARY_PATH="${UCX_PREFIX}/lib:${UCX_PREFIX}/lib/ucx:${LD_LIBRARY_PATH}"

###################################################
## Install NIXL
RUN git clone --depth 1 --branch ${NIXL_VERSION} \
      https://github.com/ai-dynamo/nixl.git /opt/nixl \
    && cd /opt/nixl \
    && pip3 install --break-system-packages --no-cache-dir tomlkit \
    && export PKG_CONFIG_PATH="/opt/amazon/efa/lib/pkgconfig:$PKG_CONFIG_PATH" \
    && export CPATH="/opt/amazon/efa/include:$CPATH" \
    && export LIBRARY_PATH="/opt/amazon/efa/lib:/usr/local/cuda/lib64/stubs" \
    && meson setup build \
       --prefix=/usr/local \
       --buildtype=release \
       -Ducx_path=${UCX_PREFIX} \
       -Dlibfabric_path=/opt/amazon/efa \
    && ninja -C build -j$(nproc) \
    && ninja -C build install \
    && ldconfig

###################################################
## Install nixlbench
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    libcpprest-dev libgrpc++-dev libgrpc-dev libprotobuf-dev protobuf-compiler-grpc libgflags-dev \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 https://github.com/etcd-cpp-apiv3/etcd-cpp-apiv3.git /tmp/etcd-cpp \
    && cd /tmp/etcd-cpp && mkdir build && cd build \
    && cmake .. -DCMAKE_INSTALL_PREFIX=/usr/local -DBUILD_SHARED_LIBS=ON -DCMAKE_BUILD_TYPE=Release \
    && make -j$(nproc) && make install && ldconfig \
    && rm -rf /tmp/etcd-cpp

RUN cd /opt/nixl/benchmark/nixlbench \
    && meson setup build --prefix=/usr/local --buildtype=release -Dnixl_path=/usr/local \
    && ninja -C build -j$(nproc) && ninja -C build install

###################################################
## Install NCCL
RUN git clone -b ${NCCL_VERSION} https://github.com/NVIDIA/nccl.git  /opt/nccl \
    && cd /opt/nccl \
    && make -j $(nproc) src.build CUDA_HOME=/usr/local/cuda \
    NVCC_GENCODE="-gencode=arch=compute_80,code=sm_80 -gencode=arch=compute_86,code=sm_86 -gencode=arch=compute_89,code=sm_89 -gencode=arch=compute_90,code=sm_90 -gencode=arch=compute_100,code=sm_100"

###################################################
## Install NCCL-tests
RUN git clone -b ${NCCL_TESTS_VERSION} https://github.com/NVIDIA/nccl-tests.git /opt/nccl-tests \
    && cd /opt/nccl-tests \
    && make -j $(nproc) \
    MPI=1 \
    MPI_HOME=/opt/amazon/openmpi/ \
    CUDA_HOME=/usr/local/cuda \
    NCCL_HOME=/opt/nccl/build \
    NVCC_GENCODE="-gencode=arch=compute_80,code=sm_80 -gencode=arch=compute_86,code=sm_86 -gencode=arch=compute_89,code=sm_89 -gencode=arch=compute_90,code=sm_90 -gencode=arch=compute_100,code=sm_100"

###################################################
## Install NVSHMEM
ENV NVSHMEM_DIR=/opt/nvshmem
ENV NVSHMEM_HOME=/opt/nvshmem

#RUN git clone --depth 1 --branch ${NVSHMEM_VERSION} https://github.com/NVIDIA/nvshmem.git /nvshmem \
RUN git clone --depth 1 --branch "hotfix/efa-rx-round-robin" https://github.com/crazyguitar/nvshmem.git /nvshmem \
    && cd /nvshmem \
    && mkdir -p build && cd build \
    && cmake -DNVSHMEM_PREFIX=/opt/nvshmem \
       -DCMAKE_CUDA_ARCHITECTURES="80;90;100" \
       -DNVSHMEM_MPI_SUPPORT=1 \
       -DNVSHMEM_PMIX_SUPPORT=1 \
       -DNVSHMEM_LIBFABRIC_SUPPORT=1 \
       -DNVSHMEM_IBRC_SUPPORT=1 \
       -DNVSHMEM_IBGDA_SUPPORT=1 \
       -DNVSHMEM_USE_GDRCOPY=1 \
       -DNVSHMEM_BUILD_TESTS=1 \
       -DNVSHMEM_BUILD_EXAMPLES=1 \
       -DNVSHMEM_BUILD_HYDRA_LAUNCHER=1 \
       -DNVSHMEM_BUILD_TXZ_PACKAGE=0 \
       -DNVSHMEM_BUILD_PYTHON_LIB=0 \
       -DMPI_HOME=/opt/amazon/openmpi \
       -DPMIX_HOME=/opt/amazon/pmix \
       -DGDRCOPY_HOME=/opt/gdrcopy \
       -DLIBFABRIC_HOME=/opt/amazon/efa \
       -G Ninja .. \
    && ninja -j $(nproc) \
    && ninja install \
    && echo /opt/nvshmem/lib > /etc/ld.so.conf.d/nvshmem.conf && ldconfig

## Add nvshmem::nvshmem alias target (source builds only export nvshmem::nvshmem_host/device)
RUN echo 'add_library(nvshmem::nvshmem INTERFACE IMPORTED)' >> /opt/nvshmem/lib/cmake/nvshmem/NVSHMEMConfig.cmake \
    && echo 'target_link_libraries(nvshmem::nvshmem INTERFACE nvshmem::nvshmem_host nvshmem::nvshmem_device)' >> /opt/nvshmem/lib/cmake/nvshmem/NVSHMEMConfig.cmake

###################################################
## Install nvshmem4py from source
RUN pip3 install --break-system-packages --no-cache-dir Cython numpy packaging \
    && touch /nvshmem/nvshmem4py/requirements.txt \
    && cd /nvshmem/nvshmem4py \
    && NVSHMEM_HOME=/opt/nvshmem \
       CUDA_HOME=/usr/local/cuda \
       CPATH=/usr/local/cuda/include:${CPATH:-} \
       pip3 install --break-system-packages --no-build-isolation .

ENV LD_LIBRARY_PATH=/opt/amazon/pmix/lib:/opt/nvshmem/lib:$LD_LIBRARY_PATH
ENV PATH=/opt/nvshmem/bin:$PATH
ENV NVSHMEM_REMOTE_TRANSPORT=libfabric
ENV NVSHMEM_LIBFABRIC_PROVIDER=efa
RUN rm -rf /var/lib/apt/lists/*

## Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
ENV PATH="/root/.cargo/bin:${PATH}"

## Set Open MPI variables to exclude network interface and conduit.
ENV OMPI_MCA_pml=^ucx            \
    OMPI_MCA_btl=tcp,self           \
    OMPI_MCA_btl_tcp_if_exclude=lo,docker0,veth_def_agent\
    OPAL_PREFIX=/opt/amazon/openmpi \
    NCCL_SOCKET_IFNAME=^docker,lo,veth

## Turn off PMIx Error https://github.com/open-mpi/ompi/issues/7516
ENV PMIX_MCA_gds=hash

## Set LD_PRELOAD for NCCL library
ENV LD_PRELOAD=/opt/nccl/build/lib/libnccl.so

# EFA settings
ENV FI_PROVIDER=efa
ENV FI_EFA_USE_DEVICE_RDMA=1
ENV FI_EFA_FORK_SAFE=1
ENV RDMAV_FORK_SAFE=1

# NVSHMEM settings
ENV NVSHMEM_DISABLE_CUDA_VMM=1
