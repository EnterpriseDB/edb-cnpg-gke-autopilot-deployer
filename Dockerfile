FROM gcr.io/cloud-marketplace-tools/k8s/deployer_helm/onbuild

# We require the manifest to be installed with server-side-apply
RUN sed -i 's@^kubectl apply@kubectl apply --server-side@g' usr/bin/deploy.sh usr/bin/deploy_with_tests.sh
