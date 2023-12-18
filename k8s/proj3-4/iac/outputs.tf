output "gke_cluster_name" {
  description = "The name of the GKE cluster"
  value       = var.cluster_settings.create ? google_container_cluster.gke[0].name : null
}

output "gke_cluster_public_ip" {
  description = "The public IP address of the GKE cluster"
  value       = var.cluster_settings.create ? google_container_cluster.gke[0].endpoint : null
}

output "pubsub_topic_name" {
  value = var.application_settings.create ? google_pubsub_topic.pubsub_topic.name : null
}

output "pubsub_subscription_name" {
  value = var.application_settings.create ? google_pubsub_subscription.pubsub_subscription[0].name : null
}

output "storage_bucket_name" {
  value = var.application_settings.create ? google_storage_bucket.storage_bucket[0].name : null
}