#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${KUBECONFIG:-$HOME/.kube/config-homelab}"
CONTROLLER_NAMESPACE="${SEALED_SECRETS_NAMESPACE:-kube-system}"
CONTROLLER_NAME="${SEALED_SECRETS_NAME:-sealed-secrets}"
CERT_FILE="$(mktemp)"

cleanup() {
  rm -f "$CERT_FILE"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_env() {
  if [ -z "${!1:-}" ]; then
    echo "Missing required environment variable: $1" >&2
    exit 1
  fi
}

seal_secret() {
  local name="$1"
  local namespace="$2"
  local output="$3"
  shift 3

  kubectl create secret generic "$name" \
    -n "$namespace" \
    "$@" \
    --dry-run=client \
    -o yaml \
    | kubeseal --format yaml --cert "$CERT_FILE" > "$output"

  echo "Wrote $output"
}

trap cleanup EXIT

require_command kubectl
require_command kubeseal
require_env CF_API_TOKEN
require_env TUNNEL_TOKEN
require_env GRAFANA_ADMIN_PASSWORD

GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"

if ! kubectl --kubeconfig "$KUBECONFIG_PATH" get deployment -n "$CONTROLLER_NAMESPACE" "$CONTROLLER_NAME" >/dev/null 2>&1; then
  echo "Sealed Secrets controller not reachable at ${CONTROLLER_NAMESPACE}/${CONTROLLER_NAME} using kubeconfig ${KUBECONFIG_PATH}" >&2
  exit 1
fi

kubeseal \
  --fetch-cert \
  --kubeconfig "$KUBECONFIG_PATH" \
  --controller-namespace "$CONTROLLER_NAMESPACE" \
  --controller-name "$CONTROLLER_NAME" \
  > "$CERT_FILE"

seal_secret \
  "cloudflare-api-token-secret" \
  "cert-manager" \
  "$REPO_ROOT/secrets/cloudflare-api-token.sealedsecret.yaml" \
  "--from-literal=api-token=${CF_API_TOKEN}"

seal_secret \
  "cloudflared-token" \
  "cloudflare" \
  "$REPO_ROOT/secrets/cloudflared-token.sealedsecret.yaml" \
  "--from-literal=TUNNEL_TOKEN=${TUNNEL_TOKEN}"

seal_secret \
  "grafana-admin-credentials" \
  "monitoring" \
  "$REPO_ROOT/secrets/grafana-admin-credentials.sealedsecret.yaml" \
  "--from-literal=admin-user=${GRAFANA_ADMIN_USER}" \
  "--from-literal=admin-password=${GRAFANA_ADMIN_PASSWORD}"
