#!/usr/bin/env bash
set -aeuo pipefail

echo "Running setup.sh"
CROSSPLANE_NAMESPACE="upbound-system"
SCRIPT_DIR=$( cd -- $( dirname -- "${BASH_SOURCE[0]}" ) &> /dev/null && pwd )

echo "Waiting until all configurations are healthy/installed..."
"${KUBECTL}" wait configuration.pkg --all --for=condition=Healthy --timeout 10m
"${KUBECTL}" wait configuration.pkg --all --for=condition=Installed --timeout 10m

echo "Creating cloud credential secret..."
"${KUBECTL}" -n upbound-system create secret generic aws-creds --from-literal=credentials="${UPTEST_CLOUD_CREDENTIALS}" \
    --dry-run=client -o yaml | "${KUBECTL}" apply -f -

echo "Waiting until all installed provider packages are healthy..."
"${KUBECTL}" wait provider.pkg --all --for condition=Healthy --timeout 5m

# use with crossplane v1.14.0
# echo "Waiting until all installed function packages are healthy..."
# "${KUBECTL}" wait function.pkg --all --for condition=Healthy --timeout 5m

echo "Waiting for all pods to come online..."
"${KUBECTL}" -n upbound-system wait --for=condition=Available deployment --all --timeout=5m

echo "Waiting for all XRDs to be established..."
"${KUBECTL}" wait xrd --all --for condition=Established

echo "Creating a default provider config..."
cat <<EOF | "${KUBECTL}" apply -f -
apiVersion: aws.upbound.io/v1beta1
kind: ProviderConfig
metadata:
  name: default
spec:
  credentials:
    secretRef:
      key: credentials
      name: aws-creds
      namespace: upbound-system
    source: Secret
EOF

echo "Installing providerconfigs"
"${KUBECTL}" apply -f ${SCRIPT_DIR}/provider/providerconfigs.yaml
echo "Installed providerconfigs"

echo "Adding provider-kubernetes Service Account permissions"
SA=$("${KUBECTL}" -n ${CROSSPLANE_NAMESPACE} get sa -o name|grep provider-kubernetes | sed -e "s|serviceaccount\/|${CROSSPLANE_NAMESPACE}:|g")
"${KUBECTL}" create clusterrolebinding provider-kubernetes-admin-binding --clusterrole cluster-admin --serviceaccount="${SA}"
echo "Added provider-kubernetes Service Account permissions"
