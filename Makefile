APP_NAME := edb-cnpg-gke-autopilot
APP_NAME_DEV := edb-cnpg-gke-autopilot-dev
REGISTRY := gcr.io/public-edb-ppas
TAG ?= 1.22.1
DOCKER_BUILDKIT := 1

export REGISTRY
export APP_NAME
export APP_NAME_DEV
export DOCKER_BUILDKIT
export TAG

# Setting SHELL to bash allows bash commands to be executed by recipes.
# This is a requirement for 'setup-envtest.sh' in the test target.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

all: build push

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Build
.PHONY: build-prod
build-prod: ## Build the deployer image
	docker build --build-arg TAG=${TAG} --tag "${REGISTRY}/${APP_NAME}/deployer:${TAG}" .

.PHONY: build
build: ## Build a dev deployer image
	docker build --build-arg TAG=${TAG} --tag "${REGISTRY}/${APP_NAME_DEV}/deployer:${TAG}" .

.PHONY: deployer-push-prod
deployer-push-prod: ## Push the deployer image.
	docker push ${REGISTRY}/${APP_NAME}/deployer:${TAG}

.PHONY: deployer-push
deployer-push: ## Push the deployer image to the dev project
	docker push ${REGISTRY}/${APP_NAME_DEV}/deployer:${TAG}

.PHONY: cnpg-push
cnpg-push: ## Push the cnpg image to the dev project
	docker pull ghcr.io/cloudnative-pg/cloudnative-pg:${TAG}
	docker tag ghcr.io/cloudnative-pg/cloudnative-pg:${TAG} ${REGISTRY}/${APP_NAME_DEV}/cloudnative-pg:${TAG}
	docker push ${REGISTRY}/${APP_NAME_DEV}/cloudnative-pg:${TAG}

.PHONY: cnpg-push-prod
cnpg-push-prod: ## Push the cnpg image to the production project
	docker pull ghcr.io/cloudnative-pg/cloudnative-pg:${TAG}
	docker tag ghcr.io/cloudnative-pg/cloudnative-pg:${TAG} ${REGISTRY}/${APP_NAME}/cloudnative-pg:${TAG}
	docker push ${REGISTRY}/${APP_NAME}/cloudnative-pg:${TAG}

.PHONY: update-chart
update-chart: ## Update the CNPG dependency chart
	helm repo add cnpg https://cloudnative-pg.github.io/charts
	helm dependency build chart/edb-cnpg-gke-autopilot

.PHONY: install
install: ## Install the deployer image via mpdev
	mpdev install \
		--deployer=${REGISTRY}/${APP_NAME_DEV}/deployer:${TAG} \
		--parameters='{"name": "edb-cnpg-gke-autopilot-test","namespace": "cnpg-system","metering.reportingSecret": "fake-reporting-secret"}'

.PHONY: install-prod
install-prod: ## Install the deployer image via mpdev
	mpdev install \
		--deployer=${REGISTRY}/${APP_NAME}/deployer:${TAG}  \
		--parameters='{"name": "edb-cnpg-gke-autopilot-test","namespace": "cnpg-system","metering.reportingSecret": "fake-reporting-secret"}'

.PHONY: verify-install
verify-install: ## Run the Marketplace verifier
	mpdev /scripts/verify \
		  --deployer=${REGISTRY}/${APP_NAME_DEV}/deployer:${TAG}

.PHONY: deploy
deploy: ## Deploy controller and metering in the configured Kubernetes cluster in ~/.kube/config.
	hack/deploy.sh
