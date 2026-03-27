ARG BASE_IMAGE=efa:latest
FROM ${BASE_IMAGE}

# NOTE: vLLM >= v0.16 removed pplx-kernels support, pin to < v0.16
ARG VLLM_VERSION=0.15.1
ARG DEEPGEMM_VERSION=v2.1.1.post3
ARG PPLX_KERNELS_COMMIT=12cecfd

###################################################
## Install vLLM
RUN pip3 install --break-system-packages --no-cache-dir vllm==${VLLM_VERSION}

###################################################
## Install DeepGEMM (requires torch from vLLM)
RUN git clone --recursive -b ${DEEPGEMM_VERSION} https://github.com/deepseek-ai/DeepGEMM.git /tmp/deepgemm \
    && cd /tmp/deepgemm \
    && python3 setup.py bdist_wheel \
    && pip3 install --break-system-packages dist/*.whl \
    && rm -rf /tmp/deepgemm

###################################################
## Install pplx-kernels
## ref: https://github.com/perplexityai/pplx-kernels
RUN git clone https://github.com/ppl-ai/pplx-kernels.git /opt/pplx-kernels \
    && cd /opt/pplx-kernels \
    && git checkout ${PPLX_KERNELS_COMMIT} \
    && sed -i 's|"-DCMAKE_PREFIX_PATH=" + _get_torch_cmake_prefix_path()|"-DCMAKE_PREFIX_PATH=" + _get_torch_cmake_prefix_path() + ";/opt/nvshmem/lib/cmake"|' setup.py \
    && TORCH_CUDA_ARCH_LIST="9.0a+PTX" \
       python3 setup.py bdist_wheel \
    && pip3 install --break-system-packages dist/*.whl \
    && pip3 install --break-system-packages --no-cache-dir pytest
