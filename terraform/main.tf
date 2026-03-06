terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.7.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.13.1"
    }
  }
}



provider "kubernetes" {
  config_path = pathexpand(var.kubeconfig_path)
}

provider "helm" {
  kubernetes = {
    config_path = pathexpand(var.kubeconfig_path)
  }
}


resource "terraform_data" "k3d_cluster" {
  input = {
    cluster_name = var.cluster_name
    server       = var.servers
    agents       = var.nodes
  }

  provisioner "local-exec" {
    command = <<-EOF
       set -e
       
       echo "Creating k3d cluster ${var.cluster_name}..."
       k3d cluster create ${var.cluster_name} \
         --servers ${var.servers} \
         --agents ${var.nodes} \
         -p "80:80@loadbalancer" \
         -p "443:443@loadbalancer" \
         --k3s-arg "--disable=traefik@server:0"

       echo "Writing kubeconig to ${pathexpand(var.kubeconfig_path)}.."
       mkdir -p "$(dirname "${pathexpand(var.kubeconfig_path)}")"
      k3d kubeconfig get ${self.input.cluster_name} > "${pathexpand(var.kubeconfig_path)}"
    EOF
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOF
      set -e
      echo "[TF] Deleting k3d cluster ${self.input.cluster_name}..."
      k3d cluster delete ${self.input.cluster_name} || true
    EOF
  }
}



resource "kubernetes_namespace" "argocd" {
  metadata { name = var.argocd_namespace }
  depends_on = [terraform_data.k3d_cluster]
}

resource "kubernetes_namespace" "plane" {
  metadata { name = "plane" }
  depends_on = [terraform_data.k3d_cluster]
}

resource "kubernetes_namespace" "monitoring" {
  metadata { name = "monitoring" }
  depends_on = [terraform_data.k3d_cluster]
}

resource "kubernetes_namespace" "cert_manager" {
  metadata { name = "cert-manager" }
  depends_on = [terraform_data.k3d_cluster]
}

resource "kubernetes_namespace" "cloudflare" {
  metadata { name = "cloudflare" }
  depends_on = [terraform_data.k3d_cluster]
}

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version

  values = [yamlencode({
    server = {
      service = { type = "ClusterIP" }
    }
    dex = { enabled = false }
  })]

  depends_on = [kubernetes_namespace.argocd]
}

resource "null_resource" "apps_root_app" {
  provisioner "local-exec" {
    command = <<-EOF
      set -e
      echo "Applying main apps root app"
      kubectl apply -n ${var.argocd_namespace} -f ${var.apps_root_app_path}
    EOF
  }


  depends_on = [
    helm_release.argocd
  ]
}

resource "null_resource" "monitoring_root_app" {
  provisioner "local-exec" {
    command = <<-EOF
     set -e
     echo "Applying monitoring root app"
     kubectl apply -n ${var.argocd_namespace} -f ${var.monitoring_app_path}
   EOF
  }

  depends_on = [
    helm_release.argocd
  ]
}


resource "null_resource" "regenerate_sealed_secrets" {
  triggers = {
    always_run = timestamp()
    enabled    = tostring(var.auto_generate_sealed_secrets)
    script     = filesha256("${path.module}/../scripts/generate-sealed-secrets.sh")
  }

  provisioner "local-exec" {
    command = <<-EOF
      set -e

      if [ "${var.auto_generate_sealed_secrets}" != "true" ]; then
        echo "[TF] auto_generate_sealed_secrets=false, skipping sealed secret regeneration."
        exit 0
      fi

      missing=""
      for name in CF_API_TOKEN TUNNEL_TOKEN GRAFANA_ADMIN_PASSWORD; do
        eval "value=\$${$name-}"
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

      echo "[TF] Waiting for sealed-secrets controller..."
      kubectl wait --for=condition=available deployment/sealed-secrets -n kube-system --timeout=300s

      echo "[TF] Regenerating SealedSecrets from local env vars..."
      "${path.module}/../scripts/generate-sealed-secrets.sh"

      echo "[TF] Applying regenerated SealedSecrets to the cluster..."
      kubectl apply -f "${path.module}/../secrets/cloudflare-api-token.sealedsecret.yaml"
      kubectl apply -f "${path.module}/../secrets/cloudflared-token.sealedsecret.yaml"
      kubectl apply -f "${path.module}/../secrets/grafana-admin-credentials.sealedsecret.yaml"

      echo "[TF] Regenerated SealedSecrets applied. Commit and push the updated files so Argo's Git source matches the cluster."
    EOF
  }

  depends_on = [
    null_resource.apps_root_app,
    null_resource.monitoring_root_app
  ]
}


