output "gke_cluster_name" {
  description = "The name of the GKE cluster"
  value       = var.cluster_settings.create ? google_container_cluster.gke[0].name : null
}

output "gke_cluster_public_ip" {
  description = "The public IP address of the GKE cluster"
  value       = var.cluster_settings.create ? google_container_cluster.gke[0].endpoint : null
}
