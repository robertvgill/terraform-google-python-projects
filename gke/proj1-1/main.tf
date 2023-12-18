# Step 1: Activate service APIs
resource "google_project_service" "api_services" {
  project = var.project
  service = each.value
  for_each = toset([
    "certificatemanager.googleapis.com", # Certificate Manager API
    "compute.googleapis.com",            # Compute Engine API
    "logging.googleapis.com",            # Cloud Logging API
    "secretmanager.googleapis.com",      # Secret Manager API
    "servicenetworking.googleapis.com",  # Service Networking API
  ])

  timeouts {
    create = "30m"
    update = "40m"
  }

  disable_dependent_services = false
  disable_on_destroy         = false
}

# Step 2: Create a custom Service Account
resource "google_service_account" "service_account" {
  for_each = {
    for idx, sa in local.service_accounts : idx => sa
    if sa["create"]
  }

  project      = format("%s", var.project)
  account_id   = each.value["account_id"]
  display_name = each.value["display_name"]
  description  = each.value["description"]

  depends_on = [
    google_project_service.api_services,
  ]
}

resource "google_project_iam_member" "iam_member_role" {
  for_each = {
    for idx, sa in local.sa_roles_flattened : "${sa["account_id"]}_${sa["role"]}" => sa
  }

  project = var.project
  role    = replace(each.value["role"], "{{PROJECT_ID}}", var.project)
  member  = "serviceAccount:${each.value["account_id"]}@${var.project}.iam.gserviceaccount.com"

  depends_on = [
    google_service_account.service_account,
  ]
}

# Step 3: Create a VPC
resource "google_compute_network" "vpc_network" {
  name                    = "${var.organization}-vpc"
  auto_create_subnetworks = false

  depends_on = [
    google_project_service.api_services
  ]
}

# Step 4: Create Cloud Router
resource "google_compute_router" "router" {
  project = var.project
  name    = "${var.organization}-router"
  network = google_compute_network.vpc_network.id
  region  = var.region

  depends_on = [
    google_compute_network.vpc_network
  ]
}

# Step 5: Create Nat Gateway
resource "google_compute_router_nat" "nat" {
  name                               = "${var.organization}-nat-router"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }

  depends_on = [
    google_compute_router.router
  ]
}

# Step 6: Create subnetworks
resource "google_compute_subnetwork" "subnetwork" {
  for_each = {
    for k, v in var.subnetwork_map : k => v
  }

  name          = each.value["name"]
  ip_cidr_range = each.value["cidr"]
  region        = var.region
  network       = google_compute_network.vpc_network.id
  secondary_ip_range = [
    for i in range(
      length(
        contains(
        keys(var.secondary_ranges), each.value.name) == true
        ? var.secondary_ranges[each.value.name]
        : []
    )) :
    var.secondary_ranges[each.value.name][i]
  ]

  depends_on = [
    google_compute_network.vpc_network,
  ]
}

# Step 7: Create firewall rules
resource "google_compute_firewall" "rules" {
  for_each = {
    for k, v in var.firewall_rules : k => v
  }

  project     = var.project
  name        = each.value["name"]
  network     = google_compute_network.vpc_network.name
  description = each.value["description"]

  allow {
    protocol = each.value["protocol"]
    ports    = lookup(each.value, "ports", null)
  }

  source_ranges = try(each.value.source_ip_ranges, [])

  depends_on = [
    google_compute_network.vpc_network
  ]
}
