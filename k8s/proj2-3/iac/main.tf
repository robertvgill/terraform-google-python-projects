# Step 1: Activate service APIs
resource "google_project_service" "api_services" {
  project = var.project
  service = each.value
  for_each = toset([
    "cloudbuild.googleapis.com",        # Cloud Build API
    "compute.googleapis.com",           # Compute Engine API
    "container.googleapis.com",         # Kubernetes Engine API
    "logging.googleapis.com",           # Cloud Logging API
    "secretmanager.googleapis.com",     # Secret Manager API
    "servicenetworking.googleapis.com", # Service Networking API
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
resource "google_compute_network" "gke_network" {
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
  network = google_compute_network.gke_network.id
  region  = var.region

  depends_on = [
    google_compute_network.gke_network
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
  network       = google_compute_network.gke_network.id
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
    google_compute_network.gke_network,
  ]
}

# Step 7: Create firewall rules
resource "google_compute_firewall" "rules" {
  for_each = {
    for k, v in var.firewall_rules : k => v
  }

  project     = var.project
  name        = each.value["name"]
  network     = google_compute_network.gke_network.name
  description = each.value["description"]

  allow {
    protocol = each.value["protocol"]
    ports    = lookup(each.value, "ports", null)
  }

  source_ranges = try(each.value.source_ip_ranges, [])

  depends_on = [
    google_compute_network.gke_network
  ]
}

# Step 8: Create GKE-managed cluster
resource "random_shuffle" "available_zones" {
  count = local.zone_count == 0 ? 1 : 0

  input        = data.google_compute_zones.available[0].names
  result_count = 3
}

resource "google_container_cluster" "gke" {
  count = var.cluster_settings.create ? 1 : 0

  name           = "${var.organization}-gke"
  location       = local.location
  node_locations = local.node_locations

  release_channel {
    channel = "UNSPECIFIED"
  }

  remove_default_node_pool = var.node_pools[0].create ? true : false

  network    = google_compute_network.gke_network.self_link
  subnetwork = google_compute_subnetwork.subnetwork["gke"].self_link

  deletion_protection = var.cluster_settings.deletion_protection

  ip_allocation_policy {
    cluster_secondary_range_name  = google_compute_subnetwork.subnetwork["gke"].secondary_ip_range[0].range_name
    services_secondary_range_name = google_compute_subnetwork.subnetwork["gke"].secondary_ip_range[1].range_name
  }

  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  cluster_autoscaling {
    enabled = var.cluster_autoscaling.enabled
    dynamic "auto_provisioning_defaults" {
      for_each = var.cluster_autoscaling.enabled ? [1] : []

      content {
        service_account = google_service_account.service_account["terraform"].email
        oauth_scopes = [
          "https://www.googleapis.com/auth/cloud-platform",
        ]

        management {
          auto_repair  = lookup(var.cluster_autoscaling, "auto_repair", true)
          auto_upgrade = lookup(var.cluster_autoscaling, "auto_upgrade", true)
        }

        disk_size = lookup(var.cluster_autoscaling, "disk_size", 100)
        disk_type = lookup(var.cluster_autoscaling, "disk_type", "pd-standard")

      }
    }

    dynamic "resource_limits" {
      for_each = local.autoscaling_resource_limits
      content {
        resource_type = lookup(resource_limits.value, "resource_type")
        minimum       = lookup(resource_limits.value, "minimum")
        maximum       = lookup(resource_limits.value, "maximum")
      }
    }
  }

  vertical_pod_autoscaling {
    enabled = var.cluster_settings.vertical_pod_autoscaling_enabled
  }

  node_pool {
    name               = lookup(var.node_pools[0], "name", "default-pool")
    initial_node_count = var.cluster_settings.initial_node_count

    node_config {
      image_type       = lookup(var.node_pools[0], "image_type", "COS_CONTAINERD")
      machine_type     = lookup(var.node_pools[0], "machine_type", "e2-medium")
      min_cpu_platform = lookup(var.node_pools[0], "min_cpu_platform", "")
      service_account  = google_service_account.service_account["terraform"].email
      logging_variant  = lookup(var.node_pools[0], "logging_variant", "DEFAULT")

      dynamic "gcfs_config" {
        for_each = lookup(var.node_pools[0], "enable_gcfs", false) ? [true] : []
        content {
          enabled = gcfs_config.value
        }
      }

      dynamic "gvnic" {
        for_each = lookup(var.node_pools[0], "enable_gvnic", false) ? [true] : []
        content {
          enabled = gvnic.value
        }
      }

      shielded_instance_config {
        enable_secure_boot          = lookup(var.node_pools[0], "enable_secure_boot", false)
        enable_integrity_monitoring = lookup(var.node_pools[0], "enable_integrity_monitoring", true)
      }
    }
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      node_pool,
      initial_node_count,
    ]
  }

  depends_on = [
    google_compute_subnetwork.subnetwork
  ]
}

# Step 9: Create Container Cluster node pools
resource "google_container_node_pool" "pools" {
  for_each = {
    for k, v in var.node_pools : k => v
    if v.create
  }

  name    = each.value.name
  cluster = google_container_cluster.gke[0].id

  initial_node_count = lookup(each.value, "autoscaling", true) ? lookup(
    each.value,
    "initial_node_count",
    lookup(each.value, "min_count", 1)
  ) : null

  max_pods_per_node = lookup(each.value, "max_pods_per_node", null)
  node_count        = lookup(each.value, "autoscaling", true) ? null : lookup(each.value, "node_count", 1)

  dynamic "autoscaling" {
    for_each = lookup(each.value, "autoscaling", true) ? [each.value] : []
    content {
      min_node_count       = contains(keys(autoscaling.value), "total_min_count") ? null : lookup(autoscaling.value, "min_count", 1)
      max_node_count       = contains(keys(autoscaling.value), "total_max_count") ? null : lookup(autoscaling.value, "max_count", 100)
      location_policy      = lookup(autoscaling.value, "location_policy", null)
      total_min_node_count = lookup(autoscaling.value, "total_min_count", null)
      total_max_node_count = lookup(autoscaling.value, "total_max_count", null)
    }
  }

  management {
    auto_repair  = lookup(each.value, "auto_repair", true)
    auto_upgrade = lookup(each.value, "auto_upgrade", true)
  }

  node_config {
    image_type       = lookup(each.value, "image_type", "COS_CONTAINERD")
    machine_type     = lookup(each.value, "machine_type", "e2-medium")
    min_cpu_platform = lookup(each.value, "min_cpu_platform", "")
    local_ssd_count  = lookup(each.value, "local_ssd_count", 0)
    disk_size_gb     = lookup(each.value, "disk_size_gb", 100)
    disk_type        = lookup(each.value, "disk_type", "pd-standard")
    service_account  = google_service_account.service_account["terraform"].email
    preemptible      = lookup(each.value, "preemptible", false)
    spot             = lookup(each.value, "spot", false)

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    dynamic "guest_accelerator" {
      for_each = lookup(each.value, "accelerator_count", 0) > 0 ? [1] : []
      content {
        type               = lookup(each.value, "accelerator_type", "")
        count              = lookup(each.value, "accelerator_count", 0)
        gpu_partition_size = lookup(each.value, "gpu_partition_size", null)

        dynamic "gpu_driver_installation_config" {
          for_each = lookup(each.value, "gpu_driver_version", "") != "" ? [1] : []
          content {
            gpu_driver_version = lookup(each.value, "gpu_driver_version", "")
          }
        }
      }
    }

    dynamic "taint" {
      for_each = concat(
        var.node_pools_taints["all"],
        var.node_pools_taints[each.value["name"]],
      )
      content {
        effect = taint.value.effect
        key    = taint.value.key
        value  = taint.value.value
      }
    }
  }

  lifecycle {
    create_before_destroy = false
    ignore_changes = [
      initial_node_count,
    ]
  }

  timeouts {
    create = "45m"
    update = "45m"
    delete = "45m"
  }

  depends_on = [
    google_container_cluster.gke,
  ]
}

# Step 10: Create secrets
resource "random_password" "password" {
  for_each = {
    for k, v in var.secrets_map : k => v
  }

  length           = each.value["chars_count"]
  special          = each.value["use_special_charts"]
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Step 11: Populate secrets
resource "google_secret_manager_secret" "secret" {
  for_each = {
    for k, v in var.secrets_map : k => v
  }

  secret_id = each.value["secret_id"]

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  depends_on = [
    google_project_service.api_services["secretmanager.googleapis.com"],
    random_password.password,
  ]
}

resource "google_secret_manager_secret_version" "secret_version" {
  for_each = {
    for k, v in var.secrets_map : k => v
  }

  secret      = google_secret_manager_secret.secret[each.key].id
  secret_data = random_password.password[each.key].result

  depends_on = [
    google_project_service.api_services["secretmanager.googleapis.com"],
  ]
}
