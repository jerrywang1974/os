FORCE_PULL := 0
DEV_BUILD  := 0
HOST_ARCH   := amd64
ARCH       := amd64
SUFFIX := $(if $(filter-out amd64,$(ARCH)),_$(ARCH))

include build.conf
include build.conf.$(ARCH)


bin/ros:
	mkdir -p $(dir $@)
	ARCH=$(ARCH) VERSION=$(VERSION) ./scripts/mk-ros.sh $@

build/host_ros: bin/ros
	mkdir -p $(dir $@)
ifeq "$(ARCH)" "$(HOST_ARCH)"
	ln -sf ../bin/ros $@
else
	ARCH=$(HOST_ARCH) TOOLCHAIN= VERSION=$(VERSION) ./scripts/mk-ros.sh $@
endif


assets/docker:
	mkdir -p $(dir $@)
	curl -L "$(DOCKER_BINARY_URL)" > $@
	chmod +x $@

assets/selinux/policy.29:
	mkdir -p $(dir $@)
	curl -L "$(SELINUX_POLICY_URL)" > $@

ifdef COMPILED_KERNEL_URL

installer: minimal
	docker build -t $(IMAGE_NAME):$(VERSION)$(SUFFIX) -f Dockerfile.$(ARCH) .

dist/artifacts/vmlinuz: build/kernel/
	mkdir -p $(dir $@)
	mv $(or $(wildcard build/kernel/boot/vmlinuz*), $(wildcard build/kernel/boot/vmlinux*)) $@


build/kernel/:
	mkdir -p $@
	curl -L "$(COMPILED_KERNEL_URL)" | tar -xzf - -C $@


dist/artifacts/initrd: bin/ros assets/docker assets/selinux/policy.29 build/kernel/ build/images.tar
	mkdir -p $(dir $@)
	SUFFIX=$(SUFFIX) DFS_IMAGE=$(DFS_IMAGE) DEV_BUILD=$(DEV_BUILD) ./scripts/mk-initrd.sh $@


dist/artifacts/rancheros.iso: minimal
	./scripts/mk-rancheros-iso.sh

all: minimal installer iso

initrd: dist/artifacts/initrd

minimal: initrd dist/artifacts/vmlinuz

iso: dist/artifacts/rancheros.iso dist/artifacts/iso-checksums.txt

test: minimal
	cd tests/integration && HOST_ARCH=$(HOST_ARCH) ARCH=$(ARCH) tox

.PHONY: all minimal initrd iso installer test

endif


build/os-config.yml: build/host_ros
	ARCH=$(ARCH) VERSION=$(VERSION) ./scripts/gen-os-config.sh $@


build/images.tar: build/host_ros build/os-config.yml
	ARCH=$(ARCH) FORCE_PULL=$(FORCE_PULL) ./scripts/mk-images-tar.sh


dist/artifacts/rootfs.tar.gz: bin/ros assets/docker build/images.tar assets/selinux/policy.29
	mkdir -p $(dir $@)
	SUFFIX=$(SUFFIX) DFS_IMAGE=$(DFS_IMAGE) DEV_BUILD=$(DEV_BUILD) IS_ROOTFS=1 ./scripts/mk-initrd.sh $@


dist/artifacts/iso-checksums.txt: dist/artifacts/rancheros.iso
	./scripts/mk-iso-checksums-txt.sh


version:
	@echo $(VERSION)

rootfs: dist/artifacts/rootfs.tar.gz

.PHONY: rootfs version bin/ros
