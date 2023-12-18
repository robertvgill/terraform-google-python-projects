output "gke_cluster_name" {
  description = "The name of the GKE cluster"
  value       = var.cluster_settings.create ? google_container_cluster.gke[0].name : null
}

output "gke_cluster_public_ip" {
  description = "The public IP address of the GKE cluster"
  value       = var.cluster_settings.create ? google_container_cluster.gke[0].endpoint : null
}

output "psql_hostname" {
  description = "Name of the PostgreSQL server"
  value       = var.postgresql_settings.create ? "${kubernetes_service.postgresql[0].metadata[0].name}.${kubernetes_namespace.postgresql[0].metadata[0].name}.svc.cluster.local" : null
}

output "psql_port" {
  description = "Port for the PostgreSQL server"
  value       = var.postgresql_settings.create ? kubernetes_service.postgresql[0].spec[0].port[0].port : null
}

output "psql_database" {
  description = "Database name in PostgreSQL"
  value       = var.postgresql_settings.create ? kubernetes_config_map.postgresql[0].data.POSTGRESQL_DATABASE : null
  depends_on = [
    kubernetes_stateful_set.postgresql[0]
  ]
}

output "psql_username" {
  description = "Username that can login to the database"
  value       = var.postgresql_settings.create ? kubernetes_config_map.postgresql[0].data.POSTGRESQL_USERNAME : null
  depends_on = [
    kubernetes_stateful_set.postgresql
  ]
}
