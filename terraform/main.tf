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


