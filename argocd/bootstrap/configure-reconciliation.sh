#!/usr/bin/env bash

set -Eeuo pipefail

readonly ARGOCD_NAMESPACE="argocd"
readonly RECONCILIATION_TIMEOUT="30s"
readonly RECONCILIATION_JITTER="10s"

if ! kubectl get namespace "${ARGOCD_NAMESPACE}" >/dev/null 2>&1; then
  echo "Argo CD namespace was not found: ${ARGOCD_NAMESPACE}" >&2
  exit 1
fi

if ! kubectl get configmap argocd-cm \
  -n "${ARGOCD_NAMESPACE}" \
  >/dev/null 2>&1; then
  echo "Argo CD ConfigMap was not found: argocd-cm" >&2
  exit 1
fi

echo "Configuring Argo CD repository reconciliation..."

kubectl patch configmap argocd-cm \
  -n "${ARGOCD_NAMESPACE}" \
  --type merge \
  -p "{
    \"data\": {
      \"timeout.reconciliation\": \"${RECONCILIATION_TIMEOUT}\",
      \"timeout.reconciliation.jitter\": \"${RECONCILIATION_JITTER}\"
    }
  }"

echo "Restarting Argo CD components..."

kubectl rollout restart \
  statefulset/argocd-application-controller \
  -n "${ARGOCD_NAMESPACE}"

kubectl rollout restart \
  deployment/argocd-repo-server \
  -n "${ARGOCD_NAMESPACE}"

kubectl rollout status \
  statefulset/argocd-application-controller \
  -n "${ARGOCD_NAMESPACE}" \
  --timeout=180s

kubectl rollout status \
  deployment/argocd-repo-server \
  -n "${ARGOCD_NAMESPACE}" \
  --timeout=180s

echo "Current reconciliation configuration:"

kubectl get configmap argocd-cm \
  -n "${ARGOCD_NAMESPACE}" \
  -o jsonpath='RECONCILIATION={.data.timeout\.reconciliation}{"\n"}JITTER={.data.timeout\.reconciliation\.jitter}{"\n"}'

echo "Argo CD reconciliation configuration completed successfully."