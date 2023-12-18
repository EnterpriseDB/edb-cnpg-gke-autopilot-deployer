#!/usr/bin/env bash

set -eEuo pipefail

if [ "${DEBUG-}" = true ]; then
  set -x
fi

# General Vars
ROOT_DIR=$(cd "$(dirname "$0")/.."; pwd)
SERVICE_ACCOUNT_KEY_PATH=${SERVICE_ACCOUNT_KEY_PATH:=""}

# Registry Vars
REGISTRY=${REGISTRY:-"gcr.io/public-edb-ppas/edb-cnpg-gke-autopilot-dev"}
REGISTRY_DOMAIN=$(echo $REGISTRY | cut -d/ -f1)
SUPPORTED_DOMAINS=("asia.gcr.io" "eu.gcr.io" "gcr.io" "marketplace.gcr.io" "staging-k8s.gcr.io" "us.gcr.io")
REGISTRY_USERNAME=${REGISTRY_USERNAME:-""}
REGISTRY_PASSWORD=${REGISTRY_PASSWORD:-""}

# Image Vars
REPO_TAG=${TAG:-$(git describe --tags --abbrev=0 | cut -d- -f1)}
TAG=${REPO_TAG#v}
IMAGE_OPERATOR="ghcr.io/cloudnative-pg/cloudnative-pg"
IMAGE_METERING=${IMAGE_METERING:-"${REGISTRY}/metering:${TAG}"}

# Cluster Vars
NAMESPACE=cnpg-system
APP_INSTANCE_NAME=edb-gke-cnpg-autopilot
OPERATOR_SERVICE_ACCOUNT="${APP_INSTANCE_NAME}-cnpg"
METERING_SERVICE_ACCOUNT="${APP_INSTANCE_NAME}-cnpg-metering"
REPORTING_SECRET="${APP_INSTANCE_NAME}-reportingsecret"

# Manifests
SA_MANIFEST="${APP_INSTANCE_NAME}_sa_manifest.yaml"
MANIFEST="${APP_INSTANCE_NAME}_manifest.yaml"

create_namespace() {
  kubectl delete ns "${NAMESPACE}" 2&> /dev/null || true
  kubectl wait --for=delete ns "${NAMESPACE}"
  kubectl create ns "${NAMESPACE}"
  kubectl wait --for=jsonpath='.status.phase'=Active ns "${NAMESPACE}"
}

create_pullsecret() {
  if [ -n "${REGISTRY_USERNAME}" ] || [ -n "${REGISTRY_PASSWORD}" ]; then
    DOCKER_USERNAME="${REGISTRY_USERNAME}"
    DOCKER_PASSWORD="${REGISTRY_PASSWORD}"
  elif [[ ${SUPPORTED_DOMAINS[@]} =~ "$REGISTRY_DOMAIN" ]]; then
    CREDS=$(echo ${REGISTRY_DOMAIN} | docker-credential-gcloud get)
    DOCKER_USERNAME=$(echo ${CREDS} | jq -r '.Username')
    DOCKER_PASSWORD=$(echo ${CREDS} | jq -r '.Secret')
  else
    echo "No Registry Credentials found!"
    exit 1
  fi

  kubectl create secret docker-registry \
    -n "${NAMESPACE}" \
    registry-pullsecret \
    --docker-server="${REGISTRY}" \
    --docker-username="${DOCKER_USERNAME}" \
    --docker-password="${DOCKER_PASSWORD}" \
    --dry-run=client -o yaml | kubectl apply -f -
}

create_reportingsecret() {
  if [[ -f "$SERVICE_ACCOUNT_KEY_PATH" ]]; then
    sed -i "s/name:.*/name: ${REPORTING_SECRET}/" "${SERVICE_ACCOUNT_KEY_PATH}"
    kubectl apply -n "${NAMESPACE}" -f "${SERVICE_ACCOUNT_KEY_PATH}"
  else
    echo "SERVICE_ACCOUNT_KEY_PATH env is undefined. Will deploy using a fake reporting secret."
    REPORTING_SECRET="$REPORTING_SECRET" yq -i e '.metadata.name |= env(REPORTING_SECRET)' "${ROOT_DIR}/hack/fake-reportingsecret.yaml"
    kubectl apply -n "${NAMESPACE}" -f "${ROOT_DIR}/hack/fake-reportingsecret.yaml"
  fi
}

deploy_sa_manifest() {
  NAMESPACE="${NAMESPACE}" \
    OPERATOR_SERVICE_ACCOUNT="${OPERATOR_SERVICE_ACCOUNT}" \
    METERING_SERVICE_ACCOUNT="${METERING_SERVICE_ACCOUNT}" \
    envsubst < "${ROOT_DIR}/resources/service-accounts.yaml" > "${ROOT_DIR}/${SA_MANIFEST}"

  kubectl apply -f "${ROOT_DIR}/${SA_MANIFEST}" --namespace "${NAMESPACE}"
}

deploy_manifest() {
  make -C "${ROOT_DIR}" update-chart

  helm template "${APP_INSTANCE_NAME}" "${ROOT_DIR}/chart/edb-cnpg-gke-autopilot" \
    --namespace "${NAMESPACE}" \
    --set cloudnative-pg.image.repository="${IMAGE_OPERATOR}" \
    --set cloudnative-pg.image.tag="${TAG}" \
    --set cloudnative-pg.serviceAccount.name="${OPERATOR_SERVICE_ACCOUNT}" \
    --set metering.serviceAccountName="${METERING_SERVICE_ACCOUNT}" \
    --set metering.reportingSecret="${REPORTING_SECRET}" \
    --set metering.image.image="${IMAGE_METERING}" \
    --set metering.imagePullSecrets[0].name=registry-pullsecret \
    > "${ROOT_DIR}/${MANIFEST}"

  kubectl apply -f "${ROOT_DIR}/${MANIFEST}" --namespace "${NAMESPACE}"
}

kubectl apply -f "https://raw.githubusercontent.com/GoogleCloudPlatform/marketplace-k8s-app-tools/master/crd/app-crd.yaml"

create_namespace

create_reportingsecret

create_pullsecret

deploy_sa_manifest

deploy_manifest
