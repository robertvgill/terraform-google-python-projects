# Step 12: Create Kubernetes namespace
resource "kubernetes_namespace" "postgresql" {
  count = var.cluster_settings.create && var.postgresql_settings.create ? 1 : 0

  metadata {
    annotations = {
      "scheduler.alpha.kubernetes.io/node-selector" : "agentpool=postgresql-pool"
    }

    name = var.postgresql_settings.namespace
  }

  depends_on = [
    google_container_node_pool.pools,
  ]
}

# Step 13: Create Kubernetes secret
resource "kubernetes_secret" "postgresql" {
  count = var.cluster_settings.create && var.postgresql_settings.create ? 1 : 0

  metadata {
    name      = var.postgresql_settings.username
    namespace = kubernetes_namespace.postgresql[0].metadata[0].name
    labels    = local.common_labels
  }

  data = {
    username = var.postgresql_settings.username
    password = random_password.password["postgresql"].result
  }

  type = "Opaque"

  depends_on = [
    kubernetes_namespace.postgresql,
  ]
}

# Step 14: Create Kubernetes persistent volume 
resource "google_compute_disk" "postgresql" {
  count = var.cluster_settings.create && var.postgresql_settings.create ? 1 : 0

  name = "dsk-postgresql"
  type = "pd-standard"
  zone = local.node_locations[0]
  size = 10

  depends_on = [
    google_container_node_pool.pools,
  ]
}

resource "kubernetes_persistent_volume" "postgresql" {
  count = var.cluster_settings.create && var.postgresql_settings.create ? 1 : 0

  metadata {
    name = "pv-postgresql"
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    capacity = {
      storage = "10Gi"
    }
    persistent_volume_source {
      gce_persistent_disk {
        pd_name = google_compute_disk.postgresql[0].name
        fs_type = "ext4"
      }
    }
    persistent_volume_reclaim_policy = "Delete"
    storage_class_name               = "standard-rwo"
    volume_mode                      = "Filesystem"
  }

  depends_on = [
    google_compute_disk.postgresql,
    kubernetes_namespace.postgresql,
  ]
}

# Step 15: Create Kubernetes persistent volume claim
resource "kubernetes_persistent_volume_claim" "postgresql" {
  count = var.cluster_settings.create && var.postgresql_settings.create ? 1 : 0

  metadata {
    name      = "pvc-postgresql"
    namespace = kubernetes_namespace.postgresql[0].metadata[0].name
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "10Gi"
      }
    }
    volume_name = kubernetes_persistent_volume.postgresql[0].metadata[0].name
  }

  depends_on = [
    kubernetes_namespace.postgresql,
    kubernetes_persistent_volume.postgresql,
  ]
}

# Step 16: Create Kubernetes service account
resource "kubernetes_service_account" "postgresql" {
  count = var.cluster_settings.create && var.postgresql_settings.create ? 1 : 0

  metadata {
    name      = "postgresql"
    namespace = kubernetes_namespace.postgresql[0].metadata[0].name
  }

  depends_on = [
    kubernetes_namespace.postgresql,
  ]
}

# Step 17: Create Kubernetes configmap
resource "kubernetes_config_map" "postgresql" {
  count = var.cluster_settings.create && var.postgresql_settings.create ? 1 : 0

  metadata {
    name      = "postgresql"
    namespace = kubernetes_namespace.postgresql[0].metadata[0].name
  }

  data = {
    POSTGRESQL_USERNAME    = var.postgresql_settings.username
    POSTGRESQL_DATABASE    = var.postgresql_settings.database
    POSTGRESQL_PORT_NUMBER = var.postgresql_settings.service_port
  }

  depends_on = [
    kubernetes_namespace.postgresql,
  ]
}

# Step 18: Create Kubernetes service 
resource "kubernetes_service" "postgresql" {
  count = var.cluster_settings.create && var.postgresql_settings.create ? 1 : 0

  metadata {
    name        = "postgresql"
    namespace   = kubernetes_namespace.postgresql[0].metadata[0].name
    labels      = local.common_labels
    annotations = local.service_annotations
  }

  spec {
    selector                = local.common_labels
    type                    = var.postgresql_settings.service_type
    internal_traffic_policy = contains(["Local", "Cluster"], var.postgresql_settings.service_type) ? var.postgresql_settings.service_traffic_policy : null
    port {
      name        = "sql"
      protocol    = "TCP"
      port        = var.postgresql_settings.service_port
      target_port = "sql"
    }
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations,
    ]
  }

  depends_on = [
    google_container_node_pool.pools,
  ]
}

# Step 19: Create Kubernetes statefulset
resource "kubernetes_stateful_set" "postgresql" {
  count = var.cluster_settings.create && var.postgresql_settings.create ? 1 : 0

  metadata {
    name      = "postgresql"
    namespace = kubernetes_namespace.postgresql[0].metadata[0].name
    labels    = local.common_labels
  }

  spec {
    pod_management_policy  = "OrderedReady"
    replicas               = 1
    revision_history_limit = var.postgresql_settings.revision_history
    service_name           = kubernetes_service.postgresql[0].metadata[0].name

    selector {
      match_labels = local.common_labels
    }

    template {
      metadata {
        labels      = local.common_labels
        annotations = local.service_annotations
      }

      spec {
        service_account_name             = kubernetes_service_account.postgresql[0].metadata[0].name
        termination_grace_period_seconds = 300

        volume {
          name = "database-volume"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.postgresql[0].metadata.0.name
            read_only  = false
          }
        }

        container {
          name              = "postgresql"
          image             = "${var.postgresql_settings.image}:${var.postgresql_settings.version}"
          image_pull_policy = "IfNotPresent"

          port {
            name           = "sql"
            protocol       = var.postgresql_settings.service_protocol
            container_port = var.postgresql_settings.service_port
          }

          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = var.postgresql_settings.username
                key  = "password"
              }
            }
          }

          volume_mount {
            name       = "database-volume"
            mount_path = "/var/lib/postgresql/data"
            sub_path   = "pgdata"
            read_only  = false
          }

          resources {
            limits = {
              cpu    = var.postgresql_settings.limits_cpu
              memory = var.postgresql_settings.limits_mem
            }

            requests = {
              cpu    = var.postgresql_settings.requests_cpu
              memory = var.postgresql_settings.requests_mem
            }
          }

          startup_probe {
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 1
            failure_threshold     = 15
            success_threshold     = 1
            exec {
              command = [
                "/bin/sh",
                "-c",
                "exec pg_isready -U postgres -h localhost -p 5432"
              ]
            }
          }

          readiness_probe {
            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 6
            success_threshold     = 1
            exec {
              command = [
                "/bin/sh",
                "-c",
                "exec pg_isready -U postgres -h localhost -p 5432"
              ]
            }
          }

          liveness_probe {
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 6
            success_threshold     = 1
            exec {
              command = [
                "/bin/sh",
                "-c",
                "exec pg_isready -U postgres -h localhost -p 5432"
              ]
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_namespace.postgresql,
    kubernetes_persistent_volume_claim.postgresql,
    kubernetes_service_account.postgresql,
  ]
}