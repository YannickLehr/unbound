# override these values at runtime as desired
# eg. make build ARCH=arm BUILD_OPTIONS=--no-cache
ARCH := amd64
DOCKER_REPO := klutchell/unbound
BUILD_OPTIONS +=

# these values are used for container labels at build time
BUILD_DATE := $(strip $(shell docker run --rm busybox date -u +'%Y-%m-%dT%H:%M:%SZ'))
BUILD_VERSION := $(strip $(shell git describe --tags --always --dirty))
VCS_REF := $(strip $(shell git rev-parse --short HEAD))
# VSC_TAG := $(strip $(shell git describe --abbrev=0 --tags))
VCS_TAG := 1.9.0
DOCKER_TAG := ${VCS_TAG}-${ARCH}

# ARCH to FROM_ARCH mapping (don't change these)
# supported ARCH values: https://golang.org/doc/install/source#environment
# supported FROM_ARCH values: https://github.com/docker-library/official-images#architectures-other-than-amd64
amd64_FROM_ARCH = amd64
arm_FROM_ARCH = arm32v6
arm64_FROM_ARCH = arm64v8
FROM_ARCH = ${${ARCH}_FROM_ARCH}

.DEFAULT_GOAL := build

.EXPORT_ALL_VARIABLES:

## -- General --

## Display this help message
.PHONY: help
help:
	@awk '{ \
			if ($$0 ~ /^.PHONY: [a-zA-Z\-\_0-9]+$$/) { \
				helpCommand = substr($$0, index($$0, ":") + 2); \
				if (helpMessage) { \
					printf "\033[36m%-20s\033[0m %s\n", \
						helpCommand, helpMessage; \
					helpMessage = ""; \
				} \
			} else if ($$0 ~ /^[a-zA-Z\-\_0-9.]+:/) { \
				helpCommand = substr($$0, 0, index($$0, ":")); \
				if (helpMessage) { \
					printf "\033[36m%-20s\033[0m %s\n", \
						helpCommand, helpMessage; \
					helpMessage = ""; \
				} \
			} else if ($$0 ~ /^##/) { \
				if (helpMessage) { \
					helpMessage = helpMessage"\n                     "substr($$0, 3); \
				} else { \
					helpMessage = substr($$0, 3); \
				} \
			} else { \
				if (helpMessage) { \
					print "\n                     "helpMessage"\n" \
				} \
				helpMessage = ""; \
			} \
		}' \
		$(MAKEFILE_LIST)

.PHONY: qemu-user-static
qemu-user-static:
	@docker run --rm --privileged multiarch/qemu-user-static:register --reset

## -- Docker --

## Build an image for the selected platform
## Usage:
##    make build [PARAM1=] [PARAM2=] [PARAM3=]
## Optional parameters:
##    ARCH               eg. amd64 or arm or arm64
##    BUILD_OPTIONS      eg. --no-cache
##    DOCKER_REPO        eg. myrepo/myapp
##
.PHONY: build
build: qemu-user-static
	@docker build ${BUILD_OPTIONS} \
		--build-arg FROM_ARCH \
		--build-arg BUILD_VERSION \
		--build-arg BUILD_DATE \
		--build-arg VCS_REF \
		--tag ${DOCKER_REPO}:${DOCKER_TAG} .

## Test an image by running it locally and requesting DNSSEC lookups
## Usage:
##    make test [PARAM1=] [PARAM2=] [PARAM3=]
## Optional parameters:
##    ARCH               eg. amd64 or arm or arm64
##    DOCKER_REPO        eg. myrepo/myapp
##
.PHONY: test
test: qemu-user-static
	$(eval CONTAINER_ID=$(shell docker run --rm -d -p 5300:53/tcp -p 5300:53/udp ${DOCKER_REPO}:${DOCKER_TAG}))
	dig sigok.verteiltesysteme.net @127.0.0.1 -p 5300 | grep NOERROR || (docker stop ${CONTAINER_ID}; exit 1)
	dig sigfail.verteiltesysteme.net @127.0.0.1 -p 5300 | grep SERVFAIL || (docker stop ${CONTAINER_ID}; exit 1)
	@docker stop ${CONTAINER_ID}

## Push an image to the selected docker repo
## Usage:
##    make push [PARAM1=] [PARAM2=] [PARAM3=]
## Optional parameters:
##    ARCH               eg. amd64 or arm or arm64
##    DOCKER_REPO        eg. myrepo/myapp
##
.PHONY: push
push:
	@docker push ${DOCKER_REPO}:${DOCKER_TAG}

## Create and push a multi-arch manifest list
## Usage:
##    make manifest [PARAM1=] [PARAM2=] [PARAM3=]
## Optional parameters:
##    DOCKER_REPO        eg. myrepo/myapp
##
.PHONY: manifest
manifest:
	@manifest-tool push from-args \
		--platforms linux/amd64,linux/arm,linux/arm64 \
		--template ${DOCKER_REPO}:${VCS_TAG}-ARCH \
		--target ${DOCKER_REPO}:${VCS_TAG} \
		--ignore-missing
	@manifest-tool push from-args \
		--platforms linux/amd64,linux/arm,linux/arm64 \
		--template ${DOCKER_REPO}:${VCS_TAG}-ARCH \
		--target ${DOCKER_REPO}:latest \
		--ignore-missing

## Build, test, and push the image in one step
## Usage:
##    make release [PARAM1=] [PARAM2=] [PARAM3=]
## Optional parameters:
##    ARCH               eg. amd64 or arm or arm64
##    BUILD_OPTIONS      eg. --no-cache
##    DOCKER_REPO        eg. myrepo/myapp
##
.PHONY: release
release: build test push
