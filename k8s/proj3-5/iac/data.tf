data "google_compute_zones" "available" {
  count = local.zone_count == 0 ? 1 : 0

  region = var.region
  status = "UP"

  depends_on = [google_project_service.api_services]
}

data "google_client_config" "current" {}