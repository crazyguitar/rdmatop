IMAGE_NAME ?= efa
IMAGE_TAG ?= latest
PPLX_IMAGE_NAME ?= pplx
PPLX_IMAGE_TAG ?= latest
OUTPUT_DIR ?= $(PWD)

.PHONY: all build clean docker pplx-docker fmt install

all: build

build:
	cargo build --release

clean:
	cargo clean

fmt:
	cargo fmt

install:
	cargo install --path .

docker:
	docker build -t $(IMAGE_NAME) .
	docker save $(IMAGE_NAME):$(IMAGE_TAG) | pigz > $(OUTPUT_DIR)/$(IMAGE_NAME)+$(IMAGE_TAG).tar.gz
	enroot import -o $(OUTPUT_DIR)/$(IMAGE_NAME)+$(IMAGE_TAG).sqsh dockerd://$(IMAGE_NAME):$(IMAGE_TAG)

pplx-docker:
	docker build -t $(PPLX_IMAGE_NAME) --build-arg BASE_IMAGE=$(IMAGE_NAME):$(IMAGE_TAG) examples/pplx/
	docker save $(PPLX_IMAGE_NAME):$(PPLX_IMAGE_TAG) | pigz > $(OUTPUT_DIR)/$(PPLX_IMAGE_NAME)+$(PPLX_IMAGE_TAG).tar.gz
	enroot import -o $(OUTPUT_DIR)/$(PPLX_IMAGE_NAME)+$(PPLX_IMAGE_TAG).sqsh dockerd://$(PPLX_IMAGE_NAME):$(PPLX_IMAGE_TAG)
