terraform {}

resource "terraform_data" "k3d_cluster" {
  input = {
    cluster_name = var.cluster_name
    servers      = var.servers
    agents       = var.nodes
    k3d_version  = var.k3d_version
    kubeconfig   = pathexpand(var.kubeconfig_path)
    argocd_ns    = var.argocd_namespace
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOF2
      set -euo pipefail

      if ! command -v k3d >/dev/null 2>&1; then
        echo "[TF] Missing required command: k3d" >&2
        exit 1
      fi
      if ! command -v kubectl >/dev/null 2>&1; then
        echo "[TF] Missing required command: kubectl" >&2
        exit 1
      fi

      if k3d cluster list --no-headers 2>/dev/null | awk '{print $1}' | grep -Fxq "${var.cluster_name}"; then
        echo "[TF] k3d cluster ${var.cluster_name} already exists."
      else
        echo "[TF] Creating k3d cluster ${var.cluster_name}..."
        k3d cluster create ${var.cluster_name} \
          --servers ${var.servers} \
          --agents ${var.nodes} \
          --image rancher/k3s:${var.k3d_version} \
          -p "80:80@loadbalancer" \
          -p "443:443@loadbalancer" \
          --k3s-arg "--disable=traefik@server:0"
      fi

      echo "[TF] Writing kubeconfig to ${pathexpand(var.kubeconfig_path)}"
      mkdir -p "$(dirname "${pathexpand(var.kubeconfig_path)}")"
      k3d kubeconfig get ${var.cluster_name} | sed 's#https://0\.0\.0\.0:#https://127.0.0.1:#' > "${pathexpand(var.kubeconfig_path)}"
      chmod 600 "${pathexpand(var.kubeconfig_path)}"

      export KUBECONFIG="${pathexpand(var.kubeconfig_path)}"

      echo "[TF] Waiting for Kubernetes API..."
      until kubectl version >/dev/null 2>&1; do
        sleep 2
      done

      echo "[TF] Waiting for nodes to become Ready..."
      kubectl wait --for=condition=Ready nodes --all --timeout=300s
    EOF2
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    when        = destroy
    command     = <<-EOF2
      set -euo pipefail
      echo "[TF] Deleting k3d cluster ${self.input.cluster_name}..."
      k3d cluster delete ${self.input.cluster_name} || true
    EOF2
  }
}

resource "terraform_data" "bootstrap_argocd" {
  input = {
    kubeconfig_path      = pathexpand(var.kubeconfig_path)
    argocd_namespace     = var.argocd_namespace
    argocd_chart_version = var.argocd_chart_version
    apps_root_app_path   = abspath("${path.module}/${var.apps_root_app_path}")
    monitoring_app_path  = abspath("${path.module}/${var.monitoring_app_path}")
  }

  triggers_replace = [
    terraform_data.k3d_cluster.id,
    var.argocd_chart_version,
    filesha256(abspath("${path.module}/${var.apps_root_app_path}")),
    filesha256(abspath("${path.module}/${var.monitoring_app_path}")),
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOF2
      set -euo pipefail

      if ! command -v kubectl >/dev/null 2>&1; then
        echo "[TF] Missing required command: kubectl" >&2
        exit 1
      fi
      if ! command -v helm >/dev/null 2>&1; then
        echo "[TF] Missing required command: helm" >&2
        exit 1
      fi

      export KUBECONFIG="${pathexpand(var.kubeconfig_path)}"

      echo "[TF] Creating required namespaces..."
      for ns in ${var.argocd_namespace} plane monitoring cert-manager cloudflare; do
        kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - --validate=false
      done

      echo "[TF] Installing or upgrading Argo CD..."
      helm repo add argo https://argoproj.github.io/argo-helm --force-update >/dev/null
      helm repo update >/dev/null
      helm upgrade --install argocd argo/argo-cd \
        --namespace ${var.argocd_namespace} \
        --create-namespace \
        --version ${var.argocd_chart_version} \
        --set server.service.type=ClusterIP \
        --set dex.enabled=false \
        --wait \
        --timeout 10m

      echo "[TF] Waiting for Argo CD API server..."
      kubectl wait --for=condition=available deployment/argocd-server -n ${var.argocd_namespace} --timeout=300s

      echo "[TF] Applying root Argo CD applications..."
      kubectl apply -n ${var.argocd_namespace} -f "${abspath("${path.module}/${var.apps_root_app_path}")}"
      kubectl apply -n ${var.argocd_namespace} -f "${abspath("${path.module}/${var.monitoring_app_path}")}"
    EOF2
  }

  depends_on = [terraform_data.k3d_cluster]
}

resource "terraform_data" "regenerate_sealed_secrets" {
  triggers_replace = [
    terraform_data.bootstrap_argocd.id,
    tostring(var.auto_generate_sealed_secrets),
    filesha256("${path.module}/../scripts/generate-sealed-secrets.sh"),
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOF2
      set -euo pipefail

      if [ "${var.auto_generate_sealed_secrets}" != "true" ]; then
        echo "[TF] auto_generate_sealed_secrets=false, skipping sealed secret regeneration."
        exit 0
      fi

      missing=""
      for name in CF_API_TOKEN TUNNEL_TOKEN GRAFANA_ADMIN_PASSWORD; do
        value="$${!name:-}"
        if [ -z "$value" ]; then
          missing="$missing $name"
        fi
      done

      if [ -n "$missing" ]; then
        echo "[TF] Skipping sealed secret regeneration. Missing env vars:$missing"
        echo "[TF] Export the secret env vars and rerun: terraform apply"
        exit 0
      fi

      export KUBECONFIG="${pathexpand(var.kubeconfig_path)}"

      echo "[TF] Waiting for sealed-secrets controller deployment to be created..."
      for attempt in {1..60}; do
        if kubectl get deployment sealed-secrets -n kube-system >/dev/null 2>&1; then
          break
        fi
        sleep 5
      done

      if ! kubectl get deployment sealed-secrets -n kube-system >/dev/null 2>&1; then
        echo "[TF] sealed-secrets deployment was not created in time." >&2
        exit 1
      fi

      echo "[TF] Waiting for sealed-secrets controller to become available..."
      kubectl wait --for=condition=available deployment/sealed-secrets -n kube-system --timeout=300s

      echo "[TF] Regenerating SealedSecrets from local env vars..."
      "${path.module}/../scripts/generate-sealed-secrets.sh"

      echo "[TF] Applying regenerated SealedSecrets to the cluster..."
      kubectl apply -f "${path.module}/../secrets/cloudflare-api-token.sealedsecret.yaml"
      kubectl apply -f "${path.module}/../secrets/cloudflared-token.sealedsecret.yaml"
      kubectl apply -f "${path.module}/../secrets/grafana-admin-credentials.sealedsecret.yaml"

      echo "[TF] Regenerated SealedSecrets applied. Commit and push the updated files so Argo's Git source matches the cluster."
    EOF2
  }

  depends_on = [terraform_data.bootstrap_argocd]
}
