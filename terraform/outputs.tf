output "kubeconfig" {
  description = "Kubeconfig for the cluster"
  value       = "k3d_cluster.homelab.kubeconfig[0].raw_kubeconfig"
  sensitive   = true
}
