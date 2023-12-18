# Step 1: Activate service APIs
resource "google_project_service" "api_services" {
  project = var.project
  service = each.value
  for_each = toset([
    "cloudbuild.googleapis.com",        # Cloud Build API
    "compute.googleapis.com",           # Compute Engine API
    "container.googleapis.com",         # Kubernetes Engine API
    "logging.googleapis.com",           # Cloud Logging API
    "pubsub.googleapis.com",            # Cloud Pub/Sub API
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

# Step 10: Create Pub/Sub topic
resource "google_pubsub_topic" "pubsub_topic" {
  name = "${var.application_settings.name}-topic"
}

# Step 11: Create Pub/Sub subscription
resource "google_pubsub_subscription" "pubsub_subscription" {
  count = var.application_settings.create ? 1 : 0

  name  = "${var.application_settings.name}-subscription"
  topic = google_pubsub_topic.pubsub_topic.name
}

# Step 12: Create Cloud Storage bucket name
resource "google_storage_bucket" "storage_bucket" {
  count = var.application_settings.create ? 1 : 0

  name     = "${var.application_settings.name}-bucket"
  location = var.region
}

# Step 13: Create Kubernetes namespace
resource "kubernetes_namespace" "namespace" {
  count = var.cluster_settings.create && var.application_settings.create ? 1 : 0

  metadata {
    annotations = {
      "scheduler.alpha.kubernetes.io/node-selector" : "agentpool=application-pool"
    }

    name = var.application_settings.namespace
  }

  depends_on = [
    google_container_node_pool.pools,
  ]
}

# Step 14: Create Kubernetes service account
resource "kubernetes_service_account" "service_account" {
  count = var.cluster_settings.create && var.application_settings.create ? 1 : 0

  metadata {
    name      = var.application_settings.name
    namespace = kubernetes_namespace.namespace[0].metadata[0].name
  }

  depends_on = [
    kubernetes_namespace.namespace,
  ]
}

# Step 15: Create Kubernetes configmap
resource "kubernetes_config_map" "config_map" {
  count = var.cluster_settings.create && var.application_settings.create ? 1 : 0

  metadata {
    name      = var.application_settings.name
    namespace = kubernetes_namespace.namespace[0].metadata[0].name
  }

  data = {
    PUBSUB_TOPIC_NAME = google_pubsub_topic.pubsub_topic.name
    BUCKET_NAME       = google_storage_bucket.storage_bucket[0].name
    SOCKET_PATH       = var.application_settings.socket_path
  }

  depends_on = [
    google_container_node_pool.pools,
    google_pubsub_topic.pubsub_topic,
    google_storage_bucket.storage_bucket,
    kubernetes_namespace.namespace,
  ]
}

# Step 16: Create Kubernetes deployment
resource "kubernetes_deployment" "deployment" {
  count = var.cluster_settings.create && var.application_settings.create ? 1 : 0

  metadata {
    name      = var.application_settings.name
    namespace = kubernetes_namespace.namespace[0].metadata[0].name
    labels    = local.common_labels
  }

  spec {
    replicas               = var.application_settings.replicas
    revision_history_limit = var.application_settings.revision_history

    selector {
      match_labels = local.common_labels
    }

    template {
      metadata {
        labels      = local.common_labels
        annotations = local.service_annotations
      }

      spec {
        service_account_name             = kubernetes_service_account.service_account[0].metadata[0].name
        termination_grace_period_seconds = 300

        container {
          name              = var.application_settings.name
          image             = "gcr.io/${var.project}/${var.application_settings.image}:${var.application_settings.version}"
          image_pull_policy = "IfNotPresent"

          env_from {
            config_map_ref {
              name = kubernetes_config_map.config_map[0].metadata[0].name
            }
          }

          resources {
            limits = {
              cpu    = var.application_settings.limits_cpu
              memory = var.application_settings.limits_mem
            }

            requests = {
              cpu    = var.application_settings.requests_cpu
              memory = var.application_settings.requests_mem
            }
          }
        }
      }
    }
  }

  depends_on = [
    google_container_node_pool.pools,
    google_pubsub_topic.pubsub_topic,
    google_storage_bucket.storage_bucket,
    kubernetes_namespace.namespace,
  ]
}
