variable "cluster_name" {
  description = "Name of the cluster"
  type        = string
  default     = "homelab"
}

variable "servers" {
  description = "Number of main nodes"
  type        = number
  default     = "1"
}

variable "nodes" {
  description = "Number of nodes"
  type        = number
  default     = "2"
}

variable "k3d_version" {
  description = "Version of k3d cluster"
  type        = string
  default     = "v1.27.4-k3s1"
}

variable "kubeconfig_path" {
  type    = string
  default = "~/.kube/config"
}


variable "argocd_chart_version" {
  description = "ArgoCD chart version number"
  type        = string
  default     = "9.3.5"
}

variable "argocd_namespace" {
  description = "ArgoCD namespace"
  type        = string
  default     = "argocd"
}

variable "monitoring_app_path" {
  type        = string
  default     = "../monitoring/app-of-apps/app-of-apps.yaml"
  description = "Path to the monitoring argocd root app path"
}

variable "apps_root_app_path" {
  type        = string
  default     = "../apps/root/app-of-apps.yaml"
  description = "Path to the ArgoCD APP"
}
