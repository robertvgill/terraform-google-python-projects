# Activate Google Cloud
terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
    }
  }
}

provider "kubernetes" {
  host                   = var.cluster_settings.create ? "https://${google_container_cluster.gke[0].endpoint}" : null
  cluster_ca_certificate = var.cluster_settings.create ? base64decode(google_container_cluster.gke[0].master_auth.0.cluster_ca_certificate) : null
  token                  = var.cluster_settings.create ? data.google_client_config.current.access_token : null
}