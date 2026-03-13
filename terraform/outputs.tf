output "kubeconfig" {
  description = "Path to the generated kubeconfig for the homelab cluster"
  value       = pathexpand(var.kubeconfig_path)
}
