#!/usr/bin/env bash
set -euo pipefail

KUBERNETES_VERSION="${KUBERNETES_VERSION:-1.31.0}"
RENDER_PATH="${RENDER_PATH:-}"
MANIFEST_OUTPUT="${MANIFEST_OUTPUT:-rendered.yaml}"

if [ -z "${RENDER_PATH}" ]; then
  for candidate in k8s deploy; do
    if [ -f "${candidate}/kustomization.yaml" ]; then
      RENDER_PATH="${candidate}"
      break
    fi
  done
fi

if [ -n "${RENDER_PATH}" ] && [ -f "${RENDER_PATH}/kustomization.yaml" ]; then
  echo "Rendering kustomize path: ${RENDER_PATH}"
  kustomize build "${RENDER_PATH}" > "${MANIFEST_OUTPUT}"
elif [ -f "Chart.yaml" ]; then
  echo "Rendering helm chart from repository root"
  if [ -f "values.yaml" ]; then
    helm template tenant-app . -f values.yaml > "${MANIFEST_OUTPUT}"
  else
    helm template tenant-app . > "${MANIFEST_OUTPUT}"
  fi
else
  echo "No kustomization.yaml in k8s/ or deploy/, and no Chart.yaml at repository root."
  exit 1
fi

echo "Schema validation with kubeconform"
kubeconform -strict -summary -kubernetes-version "${KUBERNETES_VERSION}" "${MANIFEST_OUTPUT}"

echo "Policy validation with conftest"
if [ -f "homelab-tenant.yaml" ]; then
  conftest test "${MANIFEST_OUTPUT}" --policy policy --data homelab-tenant.yaml
else
  conftest test "${MANIFEST_OUTPUT}" --policy policy
fi

echo "Local validation passed."
